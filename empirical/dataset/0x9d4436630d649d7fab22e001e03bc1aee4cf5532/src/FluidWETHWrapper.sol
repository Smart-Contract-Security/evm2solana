// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20}    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Minimal interface for a Fluid Dex T1 pool. The pool exposes
///         swapIn(swap0to1, amountIn, amountOutMin, to) and a constants
///         view that tells us which side is native ETH (0xEeeeeEee...).
interface IFluidDexT1 {
    function swapIn(
        bool swap0to1,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external payable returns (uint256 amountOut);
}

/// @title FluidWETHWrapper
/// @notice Adapter that lets the MultiHopRouter route through Fluid Dex T1
///         pools whose underlying token is native ETH, by translating
///         WETH ↔ ETH at the call boundary.
///
///         Why an adapter is necessary:
///
///         Fluid T1 pools that contain ETH store it as the sentinel
///         `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` for token0/token1.
///         Their on-chain swapIn() expects msg.value when ETH is the input
///         side, and sends raw ETH back when ETH is the output side.
///
///         The relay's MultiHopRouter speaks pure ERC20 — its HOP_RAW path
///         calls IERC20.forceApprove and IERC20.balanceOf on the hop's
///         tokenIn/tokenOut, and uses a plain non-payable .call(data) for
///         the swap (msg.value is NOT forwarded). For an ETH-pool that
///         would either revert (approve on the sentinel) or silently
///         fail (no ETH delivered).
///
///         This adapter receives WETH from the MultiHopRouter and:
///
///         A) ETH-IN direction (WETH → tokenOut, where the pool side is ETH):
///            1. Pull `wethAmountIn` WETH from msg.sender
///            2. WETH.withdraw(amount) — now holds raw ETH
///            3. pool.swapIn{value: amount}(swap0to1, amount, minOut, recipient)
///               where swap0to1 reflects the ETH side per the pool's storage.
///               The pool sends tokenOut directly to recipient.
///
///         B) ETH-OUT direction (tokenIn → WETH, where the pool side is ETH):
///            1. Pull `tokenAmountIn` tokenIn from msg.sender, approve pool
///            2. pool.swapIn(swap0to1, amount, minOut, address(this))
///               receives raw ETH
///            3. WETH.deposit{value: ethReceived}() — wraps to WETH
///            4. Transfer WETH to recipient
///
///         For pools where NEITHER side is ETH, this adapter is not used —
///         the MultiHopRouter calls the pool directly via the existing
///         Fluid HOP_RAW branch (see calldataBuilder.js, branch isFluid).
///
///         Two functions, one per direction. The MultiHopRouter's
///         `amountOffset` patches the amount at the documented offset:
///
///           wethInToToken(...):  selector(4) + addr(32) + uint(32)
///             → amount at offset 4 + 32 = 36
///             → ABI: f(address pool, uint256 wethIn, uint256 minOut,
///                     address recipient, bool swap0to1)
///
///           tokenInToWeth(...):  same layout
///             → amount at offset 4 + 32 = 36
///
///         Immutable: WETH and pool addresses are configured per
///         (chain, pool); deploy one wrapper per chain. No owner, no
///         setters, no upgrade path. The wrapper supports ANY Fluid T1
///         pool whose addresses are passed at call time — the wrapper
///         doesn't whitelist pools. Caller (MultiHopRouter) is trusted
///         to pass a real Fluid pool; if not, the call to swapIn() reverts.
///
/// @author VoidPool Team
contract FluidWETHWrapper {
    using SafeERC20 for IERC20;

    /// @notice The WETH9 contract on this chain.
    IWETH9 public immutable weth;

    error EthSendFailed();
    error InsufficientOutput(uint256 received, uint256 minRequired);
    error WrappedAmountMismatch(uint256 expected, uint256 actual);

    event Wrapped(
        address indexed caller,
        address indexed pool,
        address indexed recipient,
        bool swap0to1,
        bool ethInDirection,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @param _weth WETH9 contract on this chain (canonical wrapped native).
    constructor(address _weth) {
        require(_weth != address(0), "zero WETH");
        weth = IWETH9(_weth);
    }

    /// @notice Called by MultiHopRouter for WETH → tokenOut swaps where
    ///         the Fluid pool's input side is native ETH. Unwraps WETH
    ///         to ETH and forwards as msg.value to the pool.
    ///
    /// @param pool         Fluid Dex T1 pool address
    /// @param wethAmountIn WETH amount to swap (caller must have approved)
    /// @param minOut       Minimum tokenOut amount (pool-level slippage check)
    /// @param recipient    Where the pool should send tokenOut. Zero =
    ///                     msg.sender (the MultiHopRouter).
    /// @param swap0to1     Direction flag. True if token0 is the ETH side
    ///                     (the pool's underlying ordering). The caller
    ///                     (calldataBuilder) computes this from pi.swap0to1
    ///                     of the leg.
    /// @return amountOut   Amount of tokenOut received by recipient.
    function wethInToToken(
        address pool,
        uint256 wethAmountIn,
        uint256 minOut,
        address recipient,
        bool    swap0to1
    ) external returns (uint256 amountOut) {
        if (recipient == address(0)) recipient = msg.sender;

        // 1. Pull WETH from caller (MultiHopRouter).
        IERC20(address(weth)).safeTransferFrom(msg.sender, address(this), wethAmountIn);

        // 2. Unwrap to raw ETH. After withdraw() the WETH contract sends us
        //    `wethAmountIn` ETH via call{}, which lands in this contract.
        uint256 ethBefore = address(this).balance;
        weth.withdraw(wethAmountIn);
        uint256 ethReceived = address(this).balance - ethBefore;
        if (ethReceived != wethAmountIn) {
            revert WrappedAmountMismatch(wethAmountIn, ethReceived);
        }

        // 3. Call the Fluid pool with msg.value carrying ETH. The pool
        //    sends tokenOut directly to `recipient`, so we don't need to
        //    relay it ourselves.
        amountOut = IFluidDexT1(pool).swapIn{value: wethAmountIn}(
            swap0to1, wethAmountIn, minOut, recipient
        );
        if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);

        emit Wrapped(msg.sender, pool, recipient, swap0to1, /*ethInDirection*/ true,
                     wethAmountIn, amountOut);
    }

    /// @notice Called by MultiHopRouter for tokenIn → WETH swaps where
    ///         the Fluid pool's output side is native ETH. Receives ETH
    ///         from the pool, wraps to WETH, forwards to recipient.
    ///
    /// @param pool          Fluid Dex T1 pool address
    /// @param tokenIn       The non-ETH token (the pool's other side)
    /// @param tokenAmountIn Amount of tokenIn to swap
    /// @param minOut        Minimum ETH amount expected from the pool.
    ///                      Becomes the minimum WETH amount delivered to
    ///                      recipient (wrap is 1:1).
    /// @param recipient     Where to send the wrapped WETH. Zero = msg.sender.
    /// @param swap0to1      Direction flag. True if token0 is tokenIn.
    /// @return amountOut    Amount of WETH delivered to recipient.
    function tokenInToWeth(
        address pool,
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minOut,
        address recipient,
        bool    swap0to1
    ) external returns (uint256 amountOut) {
        if (recipient == address(0)) recipient = msg.sender;

        // 1. Pull tokenIn, approve to the pool.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
        IERC20(tokenIn).forceApprove(pool, tokenAmountIn);

        // 2. Swap. The pool sends raw ETH to `to` = this adapter.
        uint256 ethBefore = address(this).balance;
        IFluidDexT1(pool).swapIn(swap0to1, tokenAmountIn, minOut, address(this));
        uint256 ethReceived = address(this).balance - ethBefore;
        if (ethReceived < minOut) revert InsufficientOutput(ethReceived, minOut);

        // 3. Revoke residual allowance (pool may pull < amountIn).
        IERC20(tokenIn).forceApprove(pool, 0);

        // 4. Wrap raw ETH into WETH and forward.
        weth.deposit{value: ethReceived}();
        amountOut = ethReceived;
        IERC20(address(weth)).safeTransfer(recipient, amountOut);

        emit Wrapped(msg.sender, pool, recipient, swap0to1, /*ethInDirection*/ false,
                     tokenAmountIn, amountOut);
    }

    /// @notice Allow this contract to receive raw ETH (from WETH.withdraw
    ///         and from the Fluid pool's swapIn output path).
    receive() external payable {}
}
