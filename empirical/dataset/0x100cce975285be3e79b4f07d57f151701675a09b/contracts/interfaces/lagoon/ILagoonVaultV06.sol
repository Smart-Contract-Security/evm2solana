// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ILagoonVaultBase} from "./ILagoonVaultBase.sol";

/// @title ILagoonVaultV06
/// @notice Lagoon v0.6.0 additions on top of the shared base — adds per-batch frozen fee
///         getters, the sync-mode enum, the async-only irreversible flag, and v0.6.0 roles.
interface ILagoonVaultV06 is ILagoonVaultBase {
    /// @notice Lagoon v0.6.0 `Rates` struct — adds entry / exit / haircut on top of v0.5.x.
    struct Rates {
        uint16 managementRate;
        uint16 performanceRate;
        uint16 entryRate;
        uint16 exitRate;
        uint16 haircutRate;
    }

    /// @notice v0.6.0 role that can update totalAssets bypassing guardrails.
    function securityCouncil() external view returns (address);

    /// @notice v0.6.0 role that bypasses the whitelist on `_deposit` / `_redeem` and can
    ///         call `claimSharesOnBehalf`. Does NOT bypass `_onlyOperator` on request paths.
    function superOperator() external view returns (address);

    /// @notice v0.6.0 vault-level deposit cap.
    function maxCap() external view returns (uint256);

    /// @notice v0.6.0 irreversible flag — once `activateAsyncOnly()` is pulled, syncMode and
    ///         `totalAssetsLifespan` are locked; sync deposit/redeem can never re-enable.
    function isAsyncOnly() external view returns (bool);

    /// @notice v0.6.0 whitelist check. Renamed from `isWhitelisted` in v0.5.x.
    function isAllowed(address account) external view returns (bool);

    /// @notice Current `FeeManager.Rates`.
    function feeRates() external view returns (Rates memory);

    /// @notice Entry-fee rate frozen at the settle of `epochId` (basis points).
    function getSettlementEntryFeeRate(uint40 epochId) external view returns (uint16);

    /// @notice Exit-fee rate frozen at the settle of `epochId` (basis points).
    function getSettlementExitFeeRate(uint40 epochId) external view returns (uint16);

    /// @notice v0.6.0 SyncMode enum mirror. Layout MUST match Lagoon's
    ///         `src/v0.6.0/primitives/Enums.sol::SyncMode` ABI ordering.
    enum SyncMode {
        Both,
        SyncDeposit,
        SyncRedeem,
        None
    }

    /// @notice Current sync mode setting. Combined with `isTotalAssetsValid()` and
    ///         `isAsyncOnly()`, determines whether `syncDeposit` / `syncRedeem` are open.
    function syncMode() external view returns (SyncMode);

    /// @notice Cancels `controller`'s pending redeem request and returns shares from the
    ///         pendingSilo. Reverts with `RequestNotCancelable(requestId)` once settled.
    ///         v0.6.0 only — v0.5.x has no redeem-cancel path.
    function cancelRequestRedeem(address controller) external;
}
