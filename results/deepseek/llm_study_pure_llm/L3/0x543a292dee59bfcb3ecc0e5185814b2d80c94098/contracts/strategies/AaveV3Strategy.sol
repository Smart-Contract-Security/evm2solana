// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseStrategy} from "./BaseStrategy.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function forceApprove(address spender, uint256 amount) external;
}

library SafeERC20 {
    function forceApprove(IERC20 token, address spender, uint256 amount) internal {
        token.forceApprove(spender, amount);
    }
}

interface IAaveV3Pool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (AaveDataTypes.ReserveData memory);
}

library AaveDataTypes {
    struct ReserveData {
        uint256 currentLiquidityRate;
    }
}

library Errors {
    error ZeroAddress();
}

contract AaveV3Strategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IAaveV3Pool public immutable aavePool;
    IERC20 public immutable aToken;

    uint256 private constant RAY_TO_BPS_DIVISOR = 1e23;

    constructor(
        address vault_,
        address asset_,
        address aavePool_,
        address aToken_,
        bytes32 strategyVersionHash_
    ) BaseStrategy(vault_, asset_, strategyVersionHash_) {
        if (aavePool_ == address(0) || aToken_ == address(0)) revert Errors.ZeroAddress();
        aavePool = IAaveV3Pool(aavePool_);
        aToken = IERC20(aToken_);

        underlyingAsset.forceApprove(aavePool_, type(uint256).max);
    }

    function _deposit(uint256 amount) internal override {
        aavePool.supply(address(underlyingAsset), amount, address(this), 0);
    }

    function _withdraw(uint256 amount) internal override returns (uint256 withdrawn) {
        withdrawn = aavePool.withdraw(address(underlyingAsset), amount, address(this));
    }

    function _emergencyWithdraw() internal override returns (uint256 withdrawn) {
        uint256 bal = aToken.balanceOf(address(this));
        if (bal == 0) return 0;
        withdrawn = aavePool.withdraw(address(underlyingAsset), type(uint256).max, address(this));
    }

    function balanceOf() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function currentAPY() external view override returns (uint256) {
        AaveDataTypes.ReserveData memory data = aavePool.getReserveData(address(underlyingAsset));
        return uint256(data.currentLiquidityRate) / RAY_TO_BPS_DIVISOR;
    }

    function harvestable() external pure override returns (uint256) {
        return 0;
    }
}