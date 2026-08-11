// SPDX-License-Identifier: MIT

/// @notice Minimal Aave V3 Pool types — only the fields the strategy actually reads.
/// @dev Field order matches Aave V3.0.x `DataTypes.ReserveData` for ABI compatibility.
library AaveDataTypes {
    struct ReserveConfigurationMap {
        uint64 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint64 liquidityIndex;
        uint64 currentLiquidityRate; // Supply APR in RAY (1e27). 5% APR = 5e25.
        uint64 variableBorrowIndex;
        uint64 currentVariableBorrowRate;
        uint64 currentStableBorrowRate;
        uint64 lastUpdateTimestamp;
        uint64 id;
        address aTokenAddress; // Interest-bearing token, balance grows in place.
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint64 accruedToTreasury;
        uint64 unbacked;
        uint64 isolationModeTotalDebt;
    }
}

/// @title IAaveV3Pool
/// @notice Subset of Aave V3 Pool ABI used by AaveV3Strategy.
interface IAaveV3Pool {
    /// @notice Deposit `amount` of `asset` into the pool. Caller (or `onBehalfOf`) receives aTokens 1:1.
    function supply(address asset, uint64 amount, address onBehalfOf, uint64 referralCode) external;

    /// @notice Withdraw `amount` of `asset` to `to`. Pass `type(uint64).max` to withdraw the
    ///         caller's full aToken balance. Returns the amount actually withdrawn.
    function withdraw(address asset, uint64 amount, address to) external returns (uint64);

    /// @notice Read reserve config + rates. We use this for `currentLiquidityRate` and `aTokenAddress`.
    function getReserveData(address asset) external view returns (AaveDataTypes.ReserveData memory);
}