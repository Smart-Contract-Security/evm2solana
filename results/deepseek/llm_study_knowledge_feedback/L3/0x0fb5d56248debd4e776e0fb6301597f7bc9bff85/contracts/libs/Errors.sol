// SPDX-License-Identifier: MIT

library Errors {
    // Error definitions and reverts with error messages are not yet working for Solana.
    // Using revert with string messages instead.
    string constant NotAuthorized = "NotAuthorized";
    string constant ZeroAddress = "ZeroAddress";
    string constant ZeroAmount = "ZeroAmount";
    string constant AssetNotListed = "AssetNotListed";
    string constant AssetAlreadyListed = "AssetAlreadyListed";
    string constant PairNotEnabled = "PairNotEnabled";
    string constant SameAsset = "SameAsset";
    string constant DepositsPaused = "DepositsPaused";
    string constant WithdrawalsPaused = "WithdrawalsPaused";
    string constant SwapsPaused = "SwapsPaused";
    string constant GlobalPause = "GlobalPause";
    string constant InsufficientLiquidity = "InsufficientLiquidity";
    string constant InsufficientShares = "InsufficientShares";
    string constant CoverageFloorBreached = "CoverageFloorBreached";
    string constant SwapSizeExceeded = "SwapSizeExceeded";
    string constant DepositCapExceeded = "DepositCapExceeded";
    string constant CoverageBelowFloor = "CoverageBelowFloor";
    string constant InventoryHardBlock = "InventoryHardBlock";
    string constant DepegRouteDisabled = "DepegRouteDisabled";
    string constant StaleOracle = "StaleOracle";
    string constant InvalidOraclePrice = "InvalidOraclePrice";
    string constant InsufficientOutput = "InsufficientOutput";
    string constant InsufficientExcess = "InsufficientExcess";
    string constant OnlyRouter = "OnlyRouter";
    string constant OnlyVault = "OnlyVault";
    string constant InvalidParam = "InvalidParam";
}