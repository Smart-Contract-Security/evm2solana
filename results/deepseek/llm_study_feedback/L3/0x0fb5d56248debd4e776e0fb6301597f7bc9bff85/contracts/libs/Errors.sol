// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library Errors {
    error NotAuthorized();
    error ZeroAddress();
    error ZeroAmount();
    error AssetNotListed();
    error AssetAlreadyListed();
    error PairNotEnabled();
    error SameAsset();
    error DepositsPaused();
    error WithdrawalsPaused();
    error SwapsPaused();
    error GlobalPause();
    error InsufficientLiquidity();
    error InsufficientShares();
    error CoverageFloorBreached();
    error SwapSizeExceeded();
    error DepositCapExceeded();
    error CoverageBelowFloor();
    error InventoryHardBlock();
    error DepegRouteDisabled();
    error StaleOracle();
    error InvalidOraclePrice();
    error InsufficientOutput();
    error InsufficientExcess();
    error OnlyRouter();
    error OnlyVault();
    error InvalidParam();
}