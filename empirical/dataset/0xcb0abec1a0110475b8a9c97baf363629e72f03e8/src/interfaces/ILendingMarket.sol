// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

type Id is bytes32;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 ltv;
    uint256 lltv;
    address whitelist;
}

struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

struct MarketConstants {
    uint128 maturityGracePeriod;
    uint128 liquidationIncentive;
}

/// @notice Minimal subset of Fira's LendingMarket used by FiraLiquidator.
/// Mirrors signatures in fira-lending-market/src/interfaces/ILendingMarket.sol.
interface ILendingMarket {
    function liquidate(
        MarketParams calldata marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external returns (uint256 seizedAssetsActual, uint256 repaidAssets);

    /// @notice Post-maturity liquidation of a borrower's entire position
    /// (FiraLendingMarket extension). The market seizes collateral and computes
    /// the repaid amount internally from oracle price × liquidationIncentive;
    /// there is no `seizedAssets`/`repaidShares` input. Reverts unless
    /// `block.timestamp >= btExpiry + maturityGracePeriod`.
    function liquidateExpiredBt(MarketParams calldata marketParams, address borrower, bytes calldata data)
        external
        returns (uint256 seizedAssets, uint256 repaidAssets);

    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    function position(Id id, address user) external view returns (Position memory);
    function market(Id id) external view returns (Market memory);
    function idToMarketParams(Id id) external view returns (MarketParams memory);
    function marketConstants(Id id) external view returns (MarketConstants memory);
}
