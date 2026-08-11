// SPDX-License-Identifier: MIT
// solhint-disable
pragma solidity ^0.8.0;

import {IAdapter} from "@interfaces/IAdapter.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {IERC4626} from "@interfaces/IERC4626.sol";
import {RefundLib} from "@libraries/RefundLib.sol";
import {SafeERC20} from "@libraries/SafeERC20.sol";

/// @title UniversalERC4626Adapter
/// @notice Universal adapter for ERC4626 vaults (asset <-> share)
/// @dev sellBase: asset -> shares (deposit), sellQuote: shares -> asset (redeem)
contract UniversalERC4626Adapter is IAdapter {
    error InvalidAmount();

    function sellBase(address to, address pool, bytes memory) external override {
        address asset = IERC4626(pool).asset();
        uint256 amountIn = IERC20(asset).balanceOf(address(this));
        if (amountIn == 0) revert InvalidAmount();
        SafeERC20.safeApprove(IERC20(asset), pool, amountIn);
        IERC4626(pool).deposit(amountIn, to);
        RefundLib.refund(asset);
    }

    function sellQuote(address to, address pool, bytes memory) external override {
        address asset = IERC4626(pool).asset();
        uint256 amountIn = IERC20(pool).balanceOf(address(this));
        if (amountIn == 0) revert InvalidAmount();
        IERC4626(pool).redeem(amountIn, to, address(this));
        RefundLib.refund(asset);
    }
}
