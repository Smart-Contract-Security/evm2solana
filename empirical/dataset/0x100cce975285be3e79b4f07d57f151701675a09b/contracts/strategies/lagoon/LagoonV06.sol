// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ILagoonVaultBase} from "../../interfaces/lagoon/ILagoonVaultBase.sol";
import {ILagoonVaultV06} from "../../interfaces/lagoon/ILagoonVaultV06.sol";
import {LagoonBase} from "./LagoonBase.sol";

/// @title LagoonV06
/// @notice Vesper Lagoon strategy bound to Lagoon Finance v0.6.0 vaults.
/// @dev    Only the v0.6.0-specific surface lives here: the per-batch frozen entry/exit fee
///         getters, the `isAllowed` whitelist function, and the `"v0.6.0"` version assertion.
///         All sweep / claim / rebalance / withdrawal logic is inherited from `LagoonBase`.
contract LagoonV06 is LagoonBase {
    bytes32 private constant SUPPORTED_VERSION_HASH = keccak256(bytes("v0.6.0"));

    error SyncRedeemNotAvailable();

    event RedeemCanceled(uint256 indexed requestId, uint256 sharesReturned);
    event RedeemSynced(uint256 shares, uint256 assetsReceived);

    function isStrategyAllowedInVault() external view override returns (bool) {
        return ILagoonVaultV06(address(vault())).isAllowed(address(this));
    }

    /// @dev v0.6.0 sync-deposit gate: `!isAsyncOnly && isTotalAssetsValid && syncMode is "Both" or "SyncDeposit"`.
    function _canSyncDeposit(ILagoonVaultBase vault_) internal view override returns (bool) {
        ILagoonVaultV06 _vault = ILagoonVaultV06(address(vault_));
        if (_vault.isAsyncOnly() || !_vault.isTotalAssetsValid()) return false;
        ILagoonVaultV06.SyncMode _mode = _vault.syncMode();
        return _mode == ILagoonVaultV06.SyncMode.Both || _mode == ILagoonVaultV06.SyncMode.SyncDeposit;
    }

    /// @dev v0.6.0 sync-redeem gate: `!isAsyncOnly && isTotalAssetsValid && syncMode is "Both" or "SyncRedeem"`.
    function _canSyncRedeem(ILagoonVaultV06 vault_) internal view returns (bool) {
        if (vault_.isAsyncOnly() || !vault_.isTotalAssetsValid()) return false;
        ILagoonVaultV06.SyncMode _mode = vault_.syncMode();
        return _mode == ILagoonVaultV06.SyncMode.Both || _mode == ILagoonVaultV06.SyncMode.SyncRedeem;
    }

    function _entryFeeBpsForId(ILagoonVaultBase vault_, uint256 requestId_) internal view override returns (uint16) {
        return ILagoonVaultV06(address(vault_)).getSettlementEntryFeeRate(uint40(requestId_));
    }

    function _exitFeeBpsForId(ILagoonVaultBase vault_, uint256 requestId_) internal view override returns (uint16) {
        return ILagoonVaultV06(address(vault_)).getSettlementExitFeeRate(uint40(requestId_));
    }

    function _postInitVaultChecks(ILagoonVaultBase vault_) internal view override {
        string memory _version = vault_.version();
        if (keccak256(bytes(_version)) != SUPPORTED_VERSION_HASH) revert UnsupportedVaultVersion(_version);
    }

    /// @notice Cancel the outstanding async redeem request and pull shares back from the
    ///         pendingSilo. Same epoch-limited semantics as `cancelDeposit` — Lagoon reverts
    ///         with `RequestNotCancelable(id)` once settled. v0.6.0 only.
    /// @param  minReturned_ slippage floor on the returned shares; pass `0` to skip.
    /// @return _sharesReturned vault shares delivered back to the strategy.
    function cancelRedeem(uint256 minReturned_) external onlyKeeper returns (uint256 _sharesReturned) {
        LagoonStorage storage $ = _getLagoonStorage();
        uint256 _id = $._redeemRequestId;
        if (_id == 0) revert NoOutstandingRequest();
        ILagoonVaultV06 _vault = ILagoonVaultV06(address(vault()));
        uint256 _sharesBefore = _vault.balanceOf(address(this));
        $._redeemRequestId = 0;
        _vault.cancelRequestRedeem(address(this));
        _sharesReturned = _vault.balanceOf(address(this)) - _sharesBefore;
        if (_sharesReturned < minReturned_) revert SlippageExceeded(minReturned_, _sharesReturned);
        emit RedeemCanceled(_id, _sharesReturned);
    }

    /// @notice Keeper-driven sync redeem. Reverts with `SyncRedeemNotAvailable` when the gate
    ///         is closed. Passes `minAssets_` straight through to Lagoon's `BelowMinimumAssets`.
    /// @param  shares_     vault shares to burn; must be ≤ `vault.balanceOf(self)`.
    /// @param  minAssets_  minimum collateral the strategy will accept post-fees.
    /// @return _assetsOut  collateral actually delivered to the strategy.
    function instantRedeem(uint256 shares_, uint256 minAssets_) external onlyKeeper returns (uint256 _assetsOut) {
        if (shares_ == 0) revert ZeroAmount();
        ILagoonVaultV06 _vault = ILagoonVaultV06(address(vault()));
        if (!_canSyncRedeem(_vault)) revert SyncRedeemNotAvailable();
        uint256 _idleBefore = collateralToken().balanceOf(address(this));
        _vault.syncRedeem(shares_, address(this), minAssets_);
        _assetsOut = collateralToken().balanceOf(address(this)) - _idleBefore;
        emit RedeemSynced(shares_, _assetsOut);
    }
}
