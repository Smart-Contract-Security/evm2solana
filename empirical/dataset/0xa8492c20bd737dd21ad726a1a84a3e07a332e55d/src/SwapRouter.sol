// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniversalRouter} from "./interfaces/IUniversalRouter.sol";

/// @title SwapRouter
/// @notice Trustless forwarder for Uniswap Universal Router swaps. The off-chain
///         router (backend `services/routing`) builds the entire route — V2/V3/V4,
///         multi-hop, bridging native ETH<->WETH and through stablecoin
///         intermediaries — as Universal Router `(commands, inputs)`. This contract
///         positions the input funds inside the Universal Router and forwards the
///         call, then enforces the caller-supplied `minOut` against the actual
///         balance delta of the intended output on `msg.sender` (the Treasury).
///
///         Funding model (no Permit2): for buys the ETH is forwarded via
///         `execute{value:}`; for sells the input token is transferred to the
///         Universal Router first. Every route therefore pays from the router's
///         own balance (the encoder uses CONTRACT_BALANCE / V4 SETTLE-from-balance)
///         and delivers the output directly to the caller. A wrong, stale, or
///         malicious route cannot misappropriate funds: the balance-delta check
///         fails and the whole transaction reverts atomically.
contract SwapRouter {
    using SafeERC20 for IERC20;

    address public immutable universalRouter;

    error EthValueMismatch();
    error InsufficientOutput(uint256 received, uint256 minOut);

    constructor(address _universalRouter) {
        universalRouter = _universalRouter;
    }

    receive() external payable {}

    /// @notice Spend `msg.value` ETH on `tokenOut` via the supplied Universal Router route.
    /// @dev The route MUST deliver `tokenOut` to `msg.sender`; output is verified by balance delta.
    function swapExactEthForToken(
        address tokenOut,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOut
    ) external payable returns (uint256 out) {
        if (msg.value == 0) revert EthValueMismatch();

        uint256 pre = IERC20(tokenOut).balanceOf(msg.sender);
        IUniversalRouter(universalRouter).execute{value: msg.value}(commands, inputs, block.timestamp);
        out = IERC20(tokenOut).balanceOf(msg.sender) - pre;
        if (out < minOut) revert InsufficientOutput(out, minOut);
    }

    /// @notice Sell `amountIn` of `tokenIn` for ETH via the supplied Universal Router route.
    /// @dev Pulls `tokenIn` from `msg.sender` and pre-positions it in the Universal Router.
    ///      The route MUST deliver native ETH to `msg.sender`; output is verified by balance delta.
    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOut
    ) external returns (uint256 ethOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, universalRouter, amountIn);

        uint256 pre = msg.sender.balance;
        IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp);
        ethOut = msg.sender.balance - pre;
        if (ethOut < minOut) revert InsufficientOutput(ethOut, minOut);
    }
}
