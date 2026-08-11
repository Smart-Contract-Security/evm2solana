// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function forceApprove(address spender, uint256 amount) external;
}

library SafeERC20 {
    function forceApprove(address token, address spender, uint256 amount) internal {
        IERC20(token).forceApprove(spender, amount);
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
    // Custom errors not supported on Solana; using string revert instead.
    // error ZeroAddress();
}

abstract contract BaseStrategy {
    address public immutable underlyingAsset;
    address public immutable vault;

    constructor(address vault_, address asset_, bytes32 strategyVersionHash_) {
        vault = vault_;
        underlyingAsset = asset_;
    }

    function _deposit(uint256 amount) internal virtual;
    function _withdraw(uint256 amount) internal virtual returns (uint256);
    function _emergencyWithdraw() internal virtual returns (uint256);
    function balanceOf() external view virtual returns (uint256);
    function currentAPY() external view virtual returns (uint256);
    function harvestable() external pure virtual returns (uint256);
}

contract AaveV3Strategy is BaseStrategy {
    address public immutable aavePool;
    address public immutable aToken;

    uint256 private constant RAY_TO_BPS_DIVISOR = 1e23;

    constructor(
        address vault_,
        address asset_,
        address aavePool_,
        address aToken_,
        bytes32 strategyVersionHash_
    ) BaseStrategy(vault_, asset_, strategyVersionHash_) {
        if (aavePool_ == address(0) || aToken_ == address(0)) {
            // revert Errors.ZeroAddress();
            revert("ZeroAddress");
        }
        aavePool = aavePool_;
        aToken = aToken_;

        IERC20(underlyingAsset).forceApprove(aavePool_, type(uint256).max);
    }

    function _deposit(uint256 amount) internal override {
        IAaveV3Pool(aavePool).supply(underlyingAsset, amount, address(this), 0);
    }

    function _withdraw(uint256 amount) internal override returns (uint256 withdrawn) {
        withdrawn = IAaveV3Pool(aavePool).withdraw(underlyingAsset, amount, address(this));
    }

    function _emergencyWithdraw() internal override returns (uint256 withdrawn) {
        uint256 bal = IERC20(aToken).balanceOf(address(this));
        if (bal == 0) return 0;
        withdrawn = IAaveV3Pool(aavePool).withdraw(underlyingAsset, type(uint256).max, address(this));
    }

    function balanceOf() external view override returns (uint256) {
        return IERC20(aToken).balanceOf(address(this));
    }

    function currentAPY() external view override returns (uint256) {
        AaveDataTypes.ReserveData memory data = IAaveV3Pool(aavePool).getReserveData(underlyingAsset);
        return uint256(data.currentLiquidityRate) / RAY_TO_BPS_DIVISOR;
    }

    function harvestable() external pure override returns (uint256) {
        return 0;
    }
}