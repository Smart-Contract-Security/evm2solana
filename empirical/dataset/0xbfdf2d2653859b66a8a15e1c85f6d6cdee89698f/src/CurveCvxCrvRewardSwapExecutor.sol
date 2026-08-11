// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICurveCvxCrvCryptoPool {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external;
}

interface ICurveCvxCrvStablePool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

contract CurveCvxCrvRewardSwapExecutor {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BPS = 10_000;

    address public immutable crvUsd;
    address public immutable crv;
    address public immutable cvx;
    address public immutable weth;
    address public immutable cvxCrv;
    ICurveCvxCrvCryptoPool public immutable crvUsdWethCrvPool;
    ICurveCvxCrvCryptoPool public immutable cvxWethPool;
    ICurveCvxCrvStablePool public immutable crvCvxCrvPool;

    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(
        address crvUsd_,
        address crv_,
        address cvx_,
        address weth_,
        address cvxCrv_,
        address crvUsdWethCrvPool_,
        address cvxWethPool_,
        address crvCvxCrvPool_
    ) {
        crvUsd = crvUsd_;
        crv = crv_;
        cvx = cvx_;
        weth = weth_;
        cvxCrv = cvxCrv_;
        crvUsdWethCrvPool = ICurveCvxCrvCryptoPool(crvUsdWethCrvPool_);
        cvxWethPool = ICurveCvxCrvCryptoPool(cvxWethPool_);
        crvCvxCrvPool = ICurveCvxCrvStablePool(crvCvxCrvPool_);
    }

    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn, uint256 maxSlippageBps, bytes calldata)
        external
        returns (uint256 amountOut)
    {
        require(tokenOut == cvxCrv, "output");
        require(maxSlippageBps <= MAX_BPS, "slippage");

        uint256 cvxCrvBefore = IERC20(cvxCrv).balanceOf(address(this));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (tokenIn == crv) {
            _swapCrvToCvxCrv(amountIn, maxSlippageBps);
        } else if (tokenIn == crvUsd) {
            _swapCrvUsdToCrv(amountIn);
            _swapAllCrvToCvxCrv(maxSlippageBps);
        } else if (tokenIn == cvx) {
            _swapCvxToCrv(amountIn);
            _swapAllCrvToCvxCrv(maxSlippageBps);
        } else {
            revert("token");
        }

        amountOut = IERC20(cvxCrv).balanceOf(address(this)) - cvxCrvBefore;
        IERC20(cvxCrv).safeTransfer(msg.sender, amountOut);
        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    }

    function _swapCrvUsdToCrv(uint256 amountIn) internal {
        IERC20(crvUsd).forceApprove(address(crvUsdWethCrvPool), amountIn);
        crvUsdWethCrvPool.exchange(0, 2, amountIn, 0);
        IERC20(crvUsd).forceApprove(address(crvUsdWethCrvPool), 0);
    }

    function _swapCvxToCrv(uint256 amountIn) internal {
        IERC20(cvx).forceApprove(address(cvxWethPool), amountIn);
        cvxWethPool.exchange(1, 0, amountIn, 0);
        IERC20(cvx).forceApprove(address(cvxWethPool), 0);

        uint256 wethAmount = IERC20(weth).balanceOf(address(this));
        IERC20(weth).forceApprove(address(crvUsdWethCrvPool), wethAmount);
        crvUsdWethCrvPool.exchange(1, 2, wethAmount, 0);
        IERC20(weth).forceApprove(address(crvUsdWethCrvPool), 0);
    }

    function _swapAllCrvToCvxCrv(uint256 maxSlippageBps) internal {
        _swapCrvToCvxCrv(IERC20(crv).balanceOf(address(this)), maxSlippageBps);
    }

    function _swapCrvToCvxCrv(uint256 amount, uint256 maxSlippageBps) internal {
        uint256 quote = crvCvxCrvPool.get_dy(0, 1, amount);
        uint256 minOut = quote * (MAX_BPS - maxSlippageBps) / MAX_BPS;

        IERC20(crv).forceApprove(address(crvCvxCrvPool), amount);
        crvCvxCrvPool.exchange(0, 1, amount, minOut);
        IERC20(crv).forceApprove(address(crvCvxCrvPool), 0);
    }
}
