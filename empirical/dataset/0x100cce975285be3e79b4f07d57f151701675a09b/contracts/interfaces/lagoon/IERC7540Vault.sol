// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IERC7540Vault
/// @notice Minimal ERC-7540 (async ERC-4626) interface — the subset the Lagoon strategy uses.
/// @dev Lagoon vaults (and any 7540-compliant async vault) implement this. We intentionally drop
///      operator / authorize / mint-by-shares / withdraw-by-assets variants we don't call.
interface IERC7540Vault is IERC20 {
    /*//////////////////////////////////////////////////////////////
                            ERC-4626 SUBSET
    //////////////////////////////////////////////////////////////*/

    function asset() external view returns (address);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function totalAssets() external view returns (uint256);

    function maxDeposit(address controller) external view returns (uint256);

    /// @notice Asset-value of `controller`'s claimable redeems at the vault's *settled* rate.
    ///         On Lagoon this uses per-batch `convertToAssets(shares, redeemId)` so the result
    ///         reflects realized assets-out even if vault NAV moves after settlement.
    function maxWithdraw(address controller) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          7540 — DEPOSIT REQUESTS
    //////////////////////////////////////////////////////////////*/

    /// @return requestId protocol-assigned id; epoch-aggregated vaults (Lagoon) return the
    ///         current depositId so multiple calls in the same epoch share an id.
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    function pendingDepositRequest(uint256 requestId, address controller) external view returns (uint256 pendingAssets);

    function claimableDepositRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 claimableAssets);

    /// @notice Claim assets for the controller's settled deposit request → mint shares to receiver.
    /// @return shares the number of vault shares minted.
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /*//////////////////////////////////////////////////////////////
                          7540 — REDEEM REQUESTS
    //////////////////////////////////////////////////////////////*/

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 pendingShares);

    function claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 claimableShares);

    /// @notice Claim shares from the controller's settled redeem request → send assets to receiver.
    /// @return assets the amount of underlying received.
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);
}
