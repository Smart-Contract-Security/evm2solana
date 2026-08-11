// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Implemented by the caller of `ILendingMarket.flashLoan`. The market
/// invokes this on `msg.sender` after transferring the borrowed assets.
/// Mirrors fira-lending-market/src/interfaces/ICallbacks.sol.
interface IFlashLoanCallback {
    /// @notice Invoked by the market after `assets` have been transferred to this
    /// contract. The implementer must leave at least `assets` (plus zero fee for
    /// Fira) approved for the market before returning, or the outer transaction
    /// reverts.
    function onFlashLoan(uint256 assets, bytes calldata data) external;
}
