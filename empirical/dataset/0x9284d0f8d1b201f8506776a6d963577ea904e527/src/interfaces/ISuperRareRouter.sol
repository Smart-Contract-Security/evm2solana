// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for the SuperRare LQE Router.
/// @dev Routing purchases through this contract preserves the SuperRare UI
///      activity feed for Liquid Edition buys/sells. Bypassing it (calling the
///      Liquid token's `buy()` directly) means those events do not appear on
///      the artwork page.
///
/// The router itself is a thin wrapper that pulls funds from `msg.sender`
/// (SafeERC20 for ERC20 inputs / msg.value for ETH) and forwards a
/// Uniswap Universal Router payload to `universalRouter`. The
/// `commands`/`inputs` blobs are standard UR command/sub-input encoding —
/// see {RouterEncoder} for the V4_SWAP construction used here.
interface ISuperRareRouter {
    /// @notice ETH → Liquid token (RARE/USDC/etc swap path encoded in commands)
    function buy(
        address token,
        address recipient,
        uint256 minTokensOut,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable returns (uint256 tokensReceived);

    /// @notice Liquid token → ETH
    function sell(
        address token,
        uint256 tokenAmount,
        address recipient,
        uint256 minEthOut,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external returns (uint256 ethReceived);

    /// @notice ERC20 → ERC20 swap (e.g. RARE → NORML).
    /// @dev    The router pulls `amountIn` of `tokenIn` from msg.sender via
    ///         SafeERC20, so msg.sender must approve(router, amountIn) first.
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        address recipient,
        uint256 minAmountOut,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function isCurrencyWhitelisted(address currency) external view returns (bool);
    function liquidRegistry() external view returns (address);
    function universalRouter() external view returns (address);
    function paused() external view returns (bool);
}
