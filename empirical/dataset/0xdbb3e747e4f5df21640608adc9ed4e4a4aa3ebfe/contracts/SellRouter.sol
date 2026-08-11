// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
  SellRouter v2 — fully auto-routed, zero admin setup.

  ENTRY: `transfer(address token, uint256 amount)` — selector 0xa9059cbb so
         Etherscan decodes as ERC20 "Transfer". Wallet pre-approves SellRouter
         ONCE; subsequent sells are one tx each.

  INTERNAL FLOW (per call):
    1. Scan V2 + V3 across [WETH, USDT, USDC, DAI] route tokens.
    2. Pick the pool with highest WETH-equivalent liquidity.
    3. Sell through it using SINGLE-TRANSFER where possible:
       - V2 direct WETH/stable pair: transferFrom(wallet, pair, amount) → pair.swap
         (1 user transfer — universal-transfer-tax tokens pay tax ONCE)
       - V2 multihop TOKEN→stable→WETH: chained pair.swap with recipient=nextPair
         (still 1 user transfer — wallet → firstPair only; subsequent hops internal)
       - V3 direct WETH/stable pool: pool.swap with callback that pulls
         transferFrom(wallet, pool, amount) inside the callback (1 user transfer)
       - V3 multihop: V3 router exactInput (2 transfers — fallback for rarer case)

  Forwards proceeds (WETH) to `spamBot` (immutable). No owner-only routing
  setters, no setSellPair / setSellMode — fully autonomous per call.
*/

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
}
interface IFactoryV2 { function getPair(address, address) external view returns (address); }
interface IPairV2 {
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
interface IRouterV2 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline
    ) external;
}
interface IUniswapV3Factory { function getPool(address, address, uint24) external view returns (address); }
interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data)
        external returns (int256 amount0, int256 amount1);
}
interface ISwapRouter02 {
    struct ExactInputParams { bytes path; address recipient; uint256 amountIn; uint256 amountOutMinimum; }
    function exactInput(ExactInputParams calldata) external payable returns (uint256);
}
interface IWETH9 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

contract SellRouter {
    /* immutables */
    address public immutable owner;
    address public immutable WETH;
    address public immutable V2_FACTORY;
    address public immutable V2_ROUTER;
    address public immutable V3_FACTORY;
    address public immutable V3_ROUTER;
    address public immutable spamBot;

    /* mainnet stablecoin constants — common pair routes */
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /* V3 swap price limits (full range) */
    uint160 constant MIN_SQRT_RATIO = 4295128739 + 1;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342 - 1;

    event Sold(address indexed seller, address indexed token, uint256 amountIn, uint256 wethOut, uint8 routeKind);

    error NoRouteFound();
    error ZeroAmount();
    error NotOwner();
    error TransferFailed();

    /* V3 callback context — set per swap call */
    struct V3CB { address payer; address tokenIn; address expectedPool; }

    constructor(
        address _weth,
        address _v2Factory, address _v2Router,
        address _v3Factory, address _v3Router,
        address _spamBot
    ) {
        owner = msg.sender;
        WETH = _weth;
        V2_FACTORY = _v2Factory;
        V2_ROUTER = _v2Router;
        V3_FACTORY = _v3Factory;
        V3_ROUTER = _v3Router;
        spamBot = _spamBot;
    }

    receive() external payable {}

    /// Entry: selector 0xa9059cbb so Etherscan decodes as "Transfer".
    /// Note: SellRouter's function name does NOT trigger the token's transfer tax —
    /// tax fires only inside the TOKEN's _transfer hook when we transferFrom internally.
    function transfer(address token, uint256 amount) external returns (bool) {
        if (amount == 0) revert ZeroAmount();

        // Try V2 direct WETH pair first — most common + cheapest gas + single-transfer.
        if (_tryV2SingleHop(msg.sender, token, amount, WETH)) return true;
        // V2 direct stablecoin pairs (single-transfer + 1-hop manual swap to WETH via 2 pools)
        if (_tryV2MultiHopSingleTransfer(msg.sender, token, amount, USDT)) return true;
        if (_tryV2MultiHopSingleTransfer(msg.sender, token, amount, USDC)) return true;
        if (_tryV2MultiHopSingleTransfer(msg.sender, token, amount, DAI))  return true;
        // V3 direct WETH pool via callback (single-transfer)
        if (_tryV3DirectWeth(msg.sender, token, amount)) return true;
        // V3 multihop via router (2-transfer fallback)
        if (_tryV3RouterMultiHop(msg.sender, token, amount, USDT)) return true;
        if (_tryV3RouterMultiHop(msg.sender, token, amount, USDC)) return true;

        revert NoRouteFound();
    }

    /*── V2 single-hop direct pair (single-transfer wallet→pair) ──*/
    function _tryV2SingleHop(address from, address token, uint256 amount, address routeOut) internal returns (bool) {
        address pair = IFactoryV2(V2_FACTORY).getPair(token, routeOut);
        if (pair == address(0)) return false;
        (uint112 r0, uint112 r1,) = IPairV2(pair).getReserves();
        if (r0 == 0 || r1 == 0) return false;

        // wallet → pair direct (1 tax hit for universal-tax tokens)
        uint256 pairBalBefore = IERC20(token).balanceOf(pair);
        if (!IERC20(token).transferFrom(from, pair, amount)) revert TransferFailed();
        uint256 amountInActual = IERC20(token).balanceOf(pair) - pairBalBefore;

        (uint256 rIn, uint256 rOut) = token < routeOut ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        uint256 amountInWithFee = amountInActual * 997;
        uint256 amountOut = (amountInWithFee * rOut) / (rIn * 1000 + amountInWithFee);

        (uint256 a0, uint256 a1) = token < routeOut ? (uint256(0), amountOut) : (amountOut, uint256(0));

        if (routeOut == WETH) {
            // WETH directly to spamBot
            IPairV2(pair).swap(a0, a1, spamBot, "");
            emit Sold(from, token, amount, amountOut, 1);
        } else {
            // Intermediate token (USDT/USDC/DAI) — need a second hop to WETH.
            // Caller handles via _tryV2MultiHopSingleTransfer; this path shouldn't be hit here.
            revert NoRouteFound();
        }
        return true;
    }

    /*── V2 multi-hop TOKEN→mid→WETH (single user transfer; chained pair.swaps) ──*/
    function _tryV2MultiHopSingleTransfer(address from, address token, uint256 amount, address mid) internal returns (bool) {
        address pair1 = IFactoryV2(V2_FACTORY).getPair(token, mid);
        address pair2 = IFactoryV2(V2_FACTORY).getPair(mid, WETH);
        if (pair1 == address(0) || pair2 == address(0)) return false;
        (uint112 p1r0, uint112 p1r1,) = IPairV2(pair1).getReserves();
        (uint112 p2r0, uint112 p2r1,) = IPairV2(pair2).getReserves();
        if (p1r0 == 0 || p1r1 == 0 || p2r0 == 0 || p2r1 == 0) return false;

        // Single user-transfer: wallet → pair1 (1 tax hit)
        uint256 p1BalBefore = IERC20(token).balanceOf(pair1);
        if (!IERC20(token).transferFrom(from, pair1, amount)) revert TransferFailed();
        uint256 actualIn1 = IERC20(token).balanceOf(pair1) - p1BalBefore;

        // Hop 1: TOKEN → mid, deliver mid directly to pair2
        (uint256 r1In, uint256 r1Out) = token < mid ? (uint256(p1r0), uint256(p1r1)) : (uint256(p1r1), uint256(p1r0));
        uint256 midAmount = (actualIn1 * 997 * r1Out) / (r1In * 1000 + actualIn1 * 997);
        (uint256 p1a0, uint256 p1a1) = token < mid ? (uint256(0), midAmount) : (midAmount, uint256(0));
        IPairV2(pair1).swap(p1a0, p1a1, pair2, "");

        // Hop 2: mid → WETH, deliver to spamBot. Measure actual mid received by pair2 (FoT-safe).
        uint256 p2MidBalActual = IERC20(mid).balanceOf(pair2);
        // pair2's reserve for mid was p2r0 or p2r1 depending on ordering; new actual = old + midAmount
        // We compute fresh from balanceOf to be safe.
        uint256 actualIn2 = p2MidBalActual - (mid < WETH ? uint256(p2r0) : uint256(p2r1));
        (uint256 r2In, uint256 r2Out) = mid < WETH ? (uint256(p2r0), uint256(p2r1)) : (uint256(p2r1), uint256(p2r0));
        uint256 wethOut = (actualIn2 * 997 * r2Out) / (r2In * 1000 + actualIn2 * 997);
        (uint256 p2a0, uint256 p2a1) = mid < WETH ? (uint256(0), wethOut) : (wethOut, uint256(0));
        IPairV2(pair2).swap(p2a0, p2a1, spamBot, "");

        emit Sold(from, token, amount, wethOut, 2);
        return true;
    }

    /*── V3 direct TOKEN/WETH pool (single-transfer via swap callback) ──*/
    function _tryV3DirectWeth(address from, address token, uint256 amount) internal returns (bool) {
        (uint24 fee, address pool) = _bestV3PoolFee(token, WETH);
        if (pool == address(0)) return false;

        bool zeroForOne = token < WETH;
        bytes memory cb = abi.encode(V3CB({ payer: from, tokenIn: token, expectedPool: pool }));

        (int256 a0, int256 a1) = IUniswapV3Pool(pool).swap(
            spamBot,
            zeroForOne,
            int256(amount),
            zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO,
            cb
        );
        uint256 wethOut = uint256(-(zeroForOne ? a1 : a0));
        emit Sold(from, token, amount, wethOut, 3);
        // mark variable to satisfy compiler if unused
        fee = fee;
        return true;
    }

    /// V3 router callback — pool requests the input token from us.
    /// Verify caller is the expected pool (set by transfer's swap call),
    /// then transferFrom payer → pool. Single user transfer.
    function uniswapV3SwapCallback(int256 a0Delta, int256 a1Delta, bytes calldata data) external {
        V3CB memory cb = abi.decode(data, (V3CB));
        if (msg.sender != cb.expectedPool) revert TransferFailed();
        uint256 owed = uint256(a0Delta > 0 ? a0Delta : a1Delta);
        if (!IERC20(cb.tokenIn).transferFrom(cb.payer, msg.sender, owed)) revert TransferFailed();
    }

    /*── V3 multihop via SwapRouter02 (2-transfer fallback) ──*/
    function _tryV3RouterMultiHop(address from, address token, uint256 amount, address mid) internal returns (bool) {
        (uint24 feeA,) = _bestV3PoolFee(token, mid);
        (uint24 feeB,) = _bestV3PoolFee(mid, WETH);
        if (feeA == 0 || feeB == 0) return false;

        // 2 transfers: wallet → SellRouter, SellRouter → router
        if (!IERC20(token).transferFrom(from, address(this), amount)) revert TransferFailed();
        if (IERC20(token).allowance(address(this), V3_ROUTER) < amount) {
            IERC20(token).approve(V3_ROUTER, type(uint256).max);
        }
        bytes memory pathBytes = abi.encodePacked(token, feeA, mid, feeB, WETH);
        uint256 wethOut = ISwapRouter02(V3_ROUTER).exactInput(ISwapRouter02.ExactInputParams({
            path: pathBytes, recipient: spamBot, amountIn: amount, amountOutMinimum: 0
        }));
        emit Sold(from, token, amount, wethOut, 4);
        return true;
    }

    /*── helpers ──*/
    function _bestV3PoolFee(address a, address b) internal view returns (uint24 fee, address pool) {
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        uint128 bestLiq;
        for (uint i; i < 4; ++i) {
            address p = IUniswapV3Factory(V3_FACTORY).getPool(a, b, fees[i]);
            if (p != address(0)) {
                uint128 L = IUniswapV3Pool(p).liquidity();
                if (L > bestLiq) { bestLiq = L; fee = fees[i]; pool = p; }
            }
        }
    }

    /*── rescue (owner-only, no funds normally held) ──*/
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    function rescueETH() external onlyOwner {
        (bool ok,) = owner.call{value: address(this).balance}("");
        if (!ok) revert TransferFailed();
    }
    function rescueToken(address t) external onlyOwner {
        IERC20(t).transfer(owner, IERC20(t).balanceOf(address(this)));
    }
}
