// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ── Interfaces ───────────────────────────────────────────────────────────────

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
}

interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

// ── FlashLoanExecutor ────────────────────────────────────────────────────────

/// @title FlashLoanExecutor
/// @notice Atomic cross-DEX arbitrage using Aave V3 flash loans.
///         Borrows `tokenIn` (e.g. USDC), swaps to `tokenMid` (e.g. WETH) on
///         the cheaper DEX, swaps back on the more expensive DEX, repays Aave,
///         and keeps the spread minus fees.
/// @dev Supports both Uniswap V2-style (swapExactTokensForTokens) and
///      Uniswap V3-style (exactInputSingle) swap routes for each leg.
///      Aave V3 pool on Ethereum mainnet: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
///      Flash loan fee: 0.05% (5 bps). Break-even requires spread > 0.40%
///      (0.35% combined DEX fees + 0.05% Aave fee).
contract FlashLoanExecutor is IFlashLoanSimpleReceiver {
    address public immutable AAVE_POOL;

    address public owner;
    address public pendingOwner;
    uint256 public executionCount;
    bool public paused;
    bool public allowlistEnforced;

    bool private _entered;

    // ── Internal encode/decode structs ───────────────────────────────────────

    struct TwoLegParams {
        bytes32 opportunityId;
        address tokenMid;
        uint256 minAmountOutBuy;
        uint256 minAmountOutSell;
        uint256 minProfit;
        address buyRouter;
        address sellRouter;
        bool buyIsV3;
        bool sellIsV3;
        uint24 buyFeeTier;
        uint24 sellFeeTier;
    }

    struct TriangParams {
        bytes32 opportunityId;
        address tokenB;
        address tokenC;
        uint256 minAmountLeg1;
        uint256 minAmountLeg2;
        uint256 minAmountLeg3;
        uint256 minProfit;
        address routerAB;
        address routerBC;
        address routerCA;
        bool isV3AB;
        bool isV3BC;
        bool isV3CA;
        uint24 feeTierAB;
        uint24 feeTierBC;
        uint24 feeTierCA;
    }

    mapping(address => bool) public authorizedOperators;
    mapping(address => bool) public allowedRouters;
    mapping(address => bool) public allowedTokens;
    mapping(address => uint256) public totalProfitExtracted;

    // ── Events ───────────────────────────────────────────────────────────────

    event FlashLoanArbitrageExecuted(
        bytes32 indexed opportunityId,
        address indexed tokenIn,
        address indexed tokenMid,
        uint256 flashLoanAmount,
        uint256 premium,
        uint256 profit,
        address buyRouter,
        address sellRouter,
        uint256 timestamp
    );
    event TriangularArbitrageExecuted(
        bytes32 indexed opportunityId,
        address indexed tokenA,
        uint256 flashLoanAmount,
        uint256 premium,
        uint256 profit,
        uint256 timestamp
    );
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event RouterAllowed(address indexed router, bool allowed);
    event TokenAllowed(address indexed token, bool allowed);
    event AllowlistEnforced(bool enforced);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event OwnershipTransferStarted(address indexed current, address indexed next);
    event OwnershipTransferred(address indexed previous, address indexed next);
    event OperatorSet(address indexed operator, bool authorized);

    // ── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner || authorizedOperators[msg.sender], "Not authorized");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    modifier nonReentrant() {
        require(!_entered, "Reentrancy");
        _entered = true;
        _;
        _entered = false;
    }

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(address aavePool, address initialOwner) {
        require(aavePool != address(0), "Invalid pool");
        AAVE_POOL = aavePool;
        owner = initialOwner == address(0) ? msg.sender : initialOwner;
        allowlistEnforced = true;
    }

    receive() external payable {}
    fallback() external payable {}

    // ── Admin ────────────────────────────────────────────────────────────────

    function setOperator(address operator, bool authorized) external onlyOwner {
        require(operator != address(0), "Invalid operator");
        authorizedOperators[operator] = authorized;
        emit OperatorSet(operator, authorized);
    }

    function setRouterAllowed(address router, bool allowed) external onlyOwner {
        require(router != address(0), "Invalid router");
        allowedRouters[router] = allowed;
        emit RouterAllowed(router, allowed);
    }

    function setTokenAllowed(address token, bool allowed) external onlyOwner {
        require(token != address(0), "Invalid token");
        allowedTokens[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    function setAllowlistEnforced(bool enforced) external onlyOwner {
        allowlistEnforced = enforced;
        emit AllowlistEnforced(enforced);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        address previous = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }

    // ── Views ────────────────────────────────────────────────────────────────

    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getFlashLoanPremiumBps() external view returns (uint256) {
        return IPool(AAVE_POOL).FLASHLOAN_PREMIUM_TOTAL();
    }

    // ── Withdrawal ───────────────────────────────────────────────────────────

    function withdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 actual = amount == type(uint256).max ? balance : amount;
        require(actual > 0 && actual <= balance, "Invalid amount");
        totalProfitExtracted[token] += actual;
        require(IERC20(token).transfer(to, actual), "Transfer failed");
        emit Withdrawn(token, to, actual);
    }

    function rescueEth(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid to");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // ── Core: initiate flash loan arbitrage ──────────────────────────────────

    /// @notice Entry point called by the MEV bot backend.
    /// @param opportunityId   Correlation ID for the detected opportunity.
    /// @param tokenIn         Token to borrow (quote, e.g. USDC). Also the token returned.
    /// @param tokenMid        Intermediate token (base, e.g. WETH).
    /// @param amountIn        Amount to borrow from Aave V3.
    /// @param minAmountOutBuy Min tokenMid received after the buy leg.
    /// @param minAmountOutSell Min tokenIn received after the sell leg.
    /// @param minProfit       Min profit in tokenIn units (net of flash loan fee).
    /// @param buyRouter       DEX router for buy leg (cheap WETH).
    /// @param sellRouter      DEX router for sell leg (expensive WETH).
    /// @param buyIsV3         true → Uniswap V3 exactInputSingle; false → V2 swapExactTokensForTokens.
    /// @param sellIsV3        Same flag for the sell leg.
    /// @param buyFeeTier      V3 pool fee (e.g. 500, 3000). Ignored when buyIsV3=false.
    /// @param sellFeeTier     V3 pool fee for sell leg. Ignored when sellIsV3=false.
    function executeFlashLoanArbitrage(
        bytes32 opportunityId,
        address tokenIn,
        address tokenMid,
        uint256 amountIn,
        uint256 minAmountOutBuy,
        uint256 minAmountOutSell,
        uint256 minProfit,
        address buyRouter,
        address sellRouter,
        bool buyIsV3,
        bool sellIsV3,
        uint24 buyFeeTier,
        uint24 sellFeeTier
    ) external onlyOwnerOrOperator whenNotPaused nonReentrant {
        require(tokenIn != address(0) && tokenMid != address(0), "Invalid token");
        require(tokenIn != tokenMid, "Same token");
        require(amountIn > 0, "Invalid amount");
        require(buyRouter != address(0) && sellRouter != address(0), "Invalid router");

        if (allowlistEnforced) {
            require(allowedRouters[buyRouter], "Buy router not allowed");
            require(allowedRouters[sellRouter], "Sell router not allowed");
            require(allowedTokens[tokenIn], "TokenIn not allowed");
            require(allowedTokens[tokenMid], "TokenMid not allowed");
        }

        TwoLegParams memory tlp;
        tlp.opportunityId    = opportunityId;
        tlp.tokenMid         = tokenMid;
        tlp.minAmountOutBuy  = minAmountOutBuy;
        tlp.minAmountOutSell = minAmountOutSell;
        tlp.minProfit        = minProfit;
        tlp.buyRouter        = buyRouter;
        tlp.sellRouter       = sellRouter;
        tlp.buyIsV3          = buyIsV3;
        tlp.sellIsV3         = sellIsV3;
        tlp.buyFeeTier       = buyFeeTier;
        tlp.sellFeeTier      = sellFeeTier;
        bytes memory params  = abi.encode(uint8(0), tlp);

        _startFlashLoan(tokenIn, amountIn, params);
    }

    // ── Core: initiate triangular flash loan arbitrage ───────────────────────

    /// @notice Three-hop triangular arbitrage via Aave V3 flash loan.
    ///         Borrows `tokenA`, swaps A→B→C→A across three DEX routes, repays.
    /// @param opportunityId  Correlation ID for off-chain tracking.
    /// @param tokenA         Token to borrow and return (starting token of the cycle).
    /// @param tokenB         First intermediate token (A→B).
    /// @param tokenC         Second intermediate token (B→C).
    /// @param amountIn       Flash loan amount (in tokenA units).
    /// @param minAmounts     [leg1_min, leg2_min, leg3_min] — slippage guards per leg.
    /// @param minProfit      Minimum profit in tokenA units after flash loan repayment.
    /// @param routers        [router_AB, router_BC, router_CA] — one per leg.
    /// @param isV3           [leg1_v3, leg2_v3, leg3_v3] — true → V3 exactInputSingle.
    /// @param feeTiers       [fee_AB, fee_BC, fee_CA] — V3 pool fee; ignored for V2 legs.
    function executeTriangularFlashLoan(
        bytes32 opportunityId,
        address tokenA,
        address tokenB,
        address tokenC,
        uint256 amountIn,
        uint256[3] calldata minAmounts,
        uint256 minProfit,
        address[3] calldata routers,
        bool[3] calldata isV3,
        uint24[3] calldata feeTiers
    ) external onlyOwnerOrOperator whenNotPaused nonReentrant {
        require(tokenA != address(0) && tokenB != address(0) && tokenC != address(0), "Invalid token");
        require(tokenA != tokenB && tokenB != tokenC && tokenA != tokenC, "Duplicate token");
        require(amountIn > 0, "Invalid amount");

        if (allowlistEnforced) {
            require(allowedRouters[routers[0]] && allowedRouters[routers[1]] && allowedRouters[routers[2]], "Router not allowed");
            require(allowedTokens[tokenA] && allowedTokens[tokenB] && allowedTokens[tokenC], "Token not allowed");
        }

        TriangParams memory tp;
        tp.opportunityId = opportunityId;
        tp.tokenB        = tokenB;
        tp.tokenC        = tokenC;
        tp.minAmountLeg1 = minAmounts[0];
        tp.minAmountLeg2 = minAmounts[1];
        tp.minAmountLeg3 = minAmounts[2];
        tp.minProfit     = minProfit;
        tp.routerAB      = routers[0];
        tp.routerBC      = routers[1];
        tp.routerCA      = routers[2];
        tp.isV3AB        = isV3[0];
        tp.isV3BC        = isV3[1];
        tp.isV3CA        = isV3[2];
        tp.feeTierAB     = feeTiers[0];
        tp.feeTierBC     = feeTiers[1];
        tp.feeTierCA     = feeTiers[2];
        bytes memory params = abi.encode(uint8(1), tp);

        _startFlashLoan(tokenA, amountIn, params);
    }

    // ── Private decode helpers ───────────────────────────────────────────────
    // Each helper decodes exactly 4 ABI words (≤ 4 types in abi.decode).
    // This caps assembly-internal variables at headStart + dataEnd + 4 = 6,
    // plus ≤ 6 outer slots (calldata ptr+len, returns, optional _s) = 12 total,
    // well inside the 16-slot EVM stack limit for Remix legacy codegen.
    //
    // abi.encode layout — every field occupies one 32-byte word:
    //   TwoLeg  (12 words = 384 bytes): arbType(0) oid(1) tm(2) mb(3)
    //                                   ms(4) mp(5) br(6) sr(7)
    //                                   bv3(8) sv3(9) bf(10) sf(11)
    //   Triang  (17 words = 544 bytes): arbType(0) oid(1) tb(2) tc(3)
    //                                   ma1(4) ma2(5) ma3(6) mp(7)
    //                                   rab(8) rbc(9) rca(10) v3ab(11)
    //                                   v3bc(12) v3ca(13) fab(14) fbc(15)
    //                                   fca(16)

    // ── TwoLeg slice A  words 0-3  params[0:]  ───────────────────────────────
    function _decodeTL_A(bytes calldata d)
        private pure
        returns (bytes32 oid, address tm, uint256 mb)
    {
        uint8 _s;
        (_s, oid, tm, mb) = abi.decode(d, (uint8, bytes32, address, uint256));
    }

    // ── TwoLeg slice B  words 4-7  params[128:]  ─────────────────────────────
    function _decodeTL_B(bytes calldata d)
        private pure
        returns (uint256 ms, uint256 mp, address br, address sr)
    {
        (ms, mp, br, sr) = abi.decode(d, (uint256, uint256, address, address));
    }

    // ── TwoLeg slice C  words 8-11  params[256:]  ────────────────────────────
    function _decodeTL_C(bytes calldata d)
        private pure
        returns (bool bv3, bool sv3, uint24 bf, uint24 sf)
    {
        (bv3, sv3, bf, sf) = abi.decode(d, (bool, bool, uint24, uint24));
    }

    // ── Triang slice A  words 0-3  params[0:]  ───────────────────────────────
    function _decodeTP_A(bytes calldata d)
        private pure
        returns (bytes32 oid, address tb, address tc)
    {
        uint8 _s;
        (_s, oid, tb, tc) = abi.decode(d, (uint8, bytes32, address, address));
    }

    // ── Triang slice B  words 4-7  params[128:]  ─────────────────────────────
    function _decodeTP_B(bytes calldata d)
        private pure
        returns (uint256 ma1, uint256 ma2, uint256 ma3, uint256 mp)
    {
        (ma1, ma2, ma3, mp) = abi.decode(d, (uint256, uint256, uint256, uint256));
    }

    // ── Triang slice C  words 8-11  params[256:]  ────────────────────────────
    function _decodeTP_C(bytes calldata d)
        private pure
        returns (address rab, address rbc, address rca, bool v3ab)
    {
        (rab, rbc, rca, v3ab) = abi.decode(d, (address, address, address, bool));
    }

    // ── Triang slice D  words 12-15  params[384:]  ───────────────────────────
    function _decodeTP_D(bytes calldata d)
        private pure
        returns (bool v3bc, bool v3ca, uint24 fab, uint24 fbc)
    {
        (v3bc, v3ca, fab, fbc) = abi.decode(d, (bool, bool, uint24, uint24));
    }

    // ── Triang slice E  word 16  params[512:]  ───────────────────────────────
    function _decodeTP_E(bytes calldata d)
        private pure
        returns (uint24 fca)
    {
        fca = abi.decode(d, (uint24));
    }

    // ── Flash loan initiator ─────────────────────────────────────────────────

    /// @dev Isolated to keep stack depth in callers within the 16-slot EVM limit.
    function _startFlashLoan(address asset, uint256 amount, bytes memory params) internal {
        IPool(AAVE_POOL).flashLoanSimple(address(this), asset, amount, params, 0);
    }

    // ── Aave V3 callback ─────────────────────────────────────────────────────

    /// @notice Called by Aave pool during flashLoanSimple. Dispatches to either the
    ///         two-leg or three-leg handler based on the arbType field in params.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == AAVE_POOL, "Caller not Aave pool");
        require(initiator == address(this), "Invalid initiator");

        // First ABI word encodes the arbType discriminant (uint8, padded to 32 bytes).
        uint8 arbType = abi.decode(params, (uint8));

        if (arbType == 0) {
            return _executeTwoLegCallback(asset, amount, premium, params);
        } else if (arbType == 1) {
            return _executeTriangularCallback(asset, amount, premium, params);
        }

        revert("Unknown arbType");
    }

    /// @dev Handles the two-leg cross-DEX arbitrage callback (arbType == 0).
    function _executeTwoLegCallback(
        address asset,
        uint256 amount,
        uint256 premium,
        bytes calldata params
    ) internal returns (bool) {
        TwoLegParams memory p;
        (p.opportunityId, p.tokenMid, p.minAmountOutBuy)
            = _decodeTL_A(params);
        (p.minAmountOutSell, p.minProfit, p.buyRouter, p.sellRouter)
            = _decodeTL_B(params[128:]);
        (p.buyIsV3, p.sellIsV3, p.buyFeeTier, p.sellFeeTier)
            = _decodeTL_C(params[256:]);

        // Leg 1: buy tokenMid with asset (borrow token)
        uint256 amountOutBuy = p.buyIsV3
            ? _swapV3(asset, p.tokenMid, amount, p.minAmountOutBuy, p.buyRouter, p.buyFeeTier)
            : _swapV2(asset, p.tokenMid, amount, p.minAmountOutBuy, p.buyRouter);

        // Leg 2: sell tokenMid back to asset on the more expensive venue
        uint256 amountOutSell = p.sellIsV3
            ? _swapV3(p.tokenMid, asset, amountOutBuy, p.minAmountOutSell, p.sellRouter, p.sellFeeTier)
            : _swapV2(p.tokenMid, asset, amountOutBuy, p.minAmountOutSell, p.sellRouter);

        // Profitability gate: must cover debt AND deliver minProfit
        uint256 totalDebt = amount + premium;
        require(amountOutSell >= totalDebt, "Flash loan not repayable");
        uint256 profit = amountOutSell - totalDebt;
        require(profit >= p.minProfit, "Profit below minimum");

        _approveExact(asset, AAVE_POOL, totalDebt);
        executionCount += 1;

        emit FlashLoanArbitrageExecuted(
            p.opportunityId,
            asset,
            p.tokenMid,
            amount,
            premium,
            profit,
            p.buyRouter,
            p.sellRouter,
            block.timestamp
        );

        return true;
    }

    /// @dev Handles the three-leg triangular arbitrage callback (arbType == 1).
    ///      Executes A→B→C→A across three independent DEX routes.
    function _executeTriangularCallback(
        address asset,
        uint256 amount,
        uint256 premium,
        bytes calldata params
    ) internal returns (bool) {
        TriangParams memory p;
        (p.opportunityId, p.tokenB, p.tokenC)
            = _decodeTP_A(params);
        (p.minAmountLeg1, p.minAmountLeg2, p.minAmountLeg3, p.minProfit)
            = _decodeTP_B(params[128:]);
        (p.routerAB, p.routerBC, p.routerCA, p.isV3AB)
            = _decodeTP_C(params[256:]);
        (p.isV3BC, p.isV3CA, p.feeTierAB, p.feeTierBC)
            = _decodeTP_D(params[384:]);
        p.feeTierCA = _decodeTP_E(params[512:]);

        // Leg 1: asset (tokenA) → tokenB
        uint256 amountB = p.isV3AB
            ? _swapV3(asset, p.tokenB, amount, p.minAmountLeg1, p.routerAB, p.feeTierAB)
            : _swapV2(asset, p.tokenB, amount, p.minAmountLeg1, p.routerAB);

        // Leg 2: tokenB → tokenC
        uint256 amountC = p.isV3BC
            ? _swapV3(p.tokenB, p.tokenC, amountB, p.minAmountLeg2, p.routerBC, p.feeTierBC)
            : _swapV2(p.tokenB, p.tokenC, amountB, p.minAmountLeg2, p.routerBC);

        // Leg 3: tokenC → asset (tokenA)
        uint256 amountOut = p.isV3CA
            ? _swapV3(p.tokenC, asset, amountC, p.minAmountLeg3, p.routerCA, p.feeTierCA)
            : _swapV2(p.tokenC, asset, amountC, p.minAmountLeg3, p.routerCA);

        // Profitability gate
        uint256 totalDebt = amount + premium;
        require(amountOut >= totalDebt, "Flash loan not repayable");
        uint256 profit = amountOut - totalDebt;
        require(profit >= p.minProfit, "Profit below minimum");

        _approveExact(asset, AAVE_POOL, totalDebt);
        executionCount += 1;

        emit TriangularArbitrageExecuted(
            p.opportunityId,
            asset,
            amount,
            premium,
            profit,
            block.timestamp
        );

        return true;
    }

    // ── Swap helpers ─────────────────────────────────────────────────────────

    function _swapV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address router
    ) internal returns (uint256) {
        _approveExact(tokenIn, router, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = IUniswapV2RouterLike(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        return amounts[amounts.length - 1];
    }

    function _swapV3(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address router,
        uint24 fee
    ) internal returns (uint256) {
        _approveExact(tokenIn, router, amountIn);

        return ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _approveExact(address token, address spender, uint256 amount) internal {
        IERC20(token).approve(spender, 0);
        IERC20(token).approve(spender, amount);
    }
}
