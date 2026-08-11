// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// =============================================================================
// ADDRESSES
// =============================================================================

address constant UNISWAP_V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

/**
 * @title UniswapV4FlashLoanArbitrageV6
 * @notice V4 flash loans + V3 self-flash (zero fee) + V3 OPENING self-flash + V3/V2/Sushi multi-DEX swaps
 * @dev VERSION: 6.0.0
 *      Adds, on top of V5:
 *      - Opening self-flash entry point (cbType 7): use first pool of an arb circle as a zero-fee
 *        flash source via exact-INPUT swap-callback, run the rest of the circle in the callback,
 *        then repay the opening pool. Mirror of the closing self-flash.
 *      - C1 fix: authenticate the legacy `0x00` callback path in uniswapV3SwapCallback /
 *        pancakeV3SwapCallback by stashing the expected pool + tokenIn in TSLOTs around each
 *        `_swapV3Direct` invocation.
 *      - C5 cleanup: strict dispatch in V3 callbacks; unknown discriminator values revert
 *        with `InvalidCallbackType(uint8)` instead of falling through to the legacy branch.
 */
contract UniswapV4FlashLoanArbitrageV6 {

    struct ForkBranch {
        bytes path;
        uint16 proportionBps;
    }

    struct ForkPoint {
        ForkBranch[] branches;
        address convergenceToken;
    }

    struct CircleSpec {
        address flashToken;
        uint256 flashAmount;
        bytes path;
        uint256 minAmountOut;
    }

    // =============================================================================
    // STATE
    // =============================================================================

    address public immutable owner;
    IPoolManager private constant poolManager = IPoolManager(UNISWAP_V4_POOL_MANAGER);

    /// @notice When true, skips the profitability check in _settleAndDistribute.
    ///         Used in integration tests to allow lossy swaps without revert.
    bool public testMode;

    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant HOP_SIZE = 44;
    /// @dev Gas not seen by (startGas - gasleft()): tx base (21k) + calldata + the tail after
    ///      the final gasleft() read (WETH.withdraw + coinbase.call + owner transfer + modifier
    ///      epilogue). Rounded UP conservatively so GAS_OVERHEAD >= true unseen gas always.
    ///
    ///      Multi-point calibration (12 data points: V2-closing/V3-closing/V3-opening circles
    ///      x tipBps{0,9900} x coinbase{cold,warm}; see test/GasOverheadCalibration.t.sol):
    ///        unseen = 21 000 (tx intrinsic) + calldata_gas + tail
    ///        calldata_gas scales +760 gas per hop (2-hop ~2 488 .. 6-hop ~5 528 .. 13-hop ~10 848)
    ///        tail ~28-30k (worst case, tipBps=9900); entrypoint-independent; warm coinbase saves ~2 500
    ///        max MEASURED unseen (3-hop, cold, tip9900)        = 54 580 gas
    ///        projected 6-hop (cold, max realistic submitted)   = 57 013 gas
    ///        projected 13-hop (cold, theoretical max in cycles)= 62 333 gas
    ///
    ///      Worst-case unseen by hop count (both self-flash AND V4-PoolManager-flash paths,
    ///      cold-coinbase bound; V4-flash measured in test/GasOverheadV4.t.sol):
    ///        6-hop  (max circle size we submit) = 58 958 gas  ← binding constraint
    ///        13-hop (theoretical max in cycles) = 63 214 gas
    ///      GAS_OVERHEAD = 65 000 covers the 6-hop worst case with ~10% margin, and remains
    ///      safe (positive margin) even at 13 hops (+2.8%) — so the <=6-hop assumption is a
    ///      comfort, not a load-bearing dependency; no hop-cap guard required. Tuned down from
    ///      75 000 to reclaim ~10k gas of tip headroom (more competitive bids on marginal arbs)
    ///      while keeping the never-land-a-loss guarantee. Erring high is the safe direction.
    ///
    ///      Safety invariant: GAS_OVERHEAD >= unseen for every circle. Verified by
    ///      test_gasOverhead_calibrationAndInvariant() in test/NetTip.t.sol.
    ///      Erring high is safe: over-stating gasCost slightly reduces tip (keeps a bit
    ///      more for owner). Erring low causes over-tipping → EOA cash flow goes negative.
    uint256 private constant GAS_OVERHEAD = 65000;
    uint8 private constant DEX_V3 = 0;
    uint8 private constant DEX_V2 = 1;
    uint8 private constant DEX_SUSHI = 2;
    uint8 private constant DEX_CURVE = 3;
    uint8 private constant DEX_PSM = 4;
    uint8 private constant DEX_CURVE_UNDERLYING = 5;
    uint8 private constant DEX_CURVE_CRYPTO = 6;
    uint8 private constant DEX_V4 = 7;

    // Transient storage slots for passing data through V4 unlock
    // Slot 0 is used by reentrancy guard
    uint256 private constant TSLOT_CALLBACK_TYPE   = 1;
    uint256 private constant TSLOT_FLASH_TOKEN      = 2;
    uint256 private constant TSLOT_FLASH_AMOUNT     = 3;
    uint256 private constant TSLOT_MIN_AMOUNT_OUT   = 4;
    uint256 private constant TSLOT_TIP_BPS          = 5;
    /// @notice Authenticates self-flash callbacks: only the entry-point-set closing
    ///         pool may invoke the cbType=5/6 branch of uniswapV3SwapCallback /
    ///         pancakeV3SwapCallback. Set on entry, cleared on return.
    uint256 private constant TSLOT_CLOSING_POOL     = 6;
    /// @notice Authenticates the opening self-flash callback (cbType=7): the entry
    ///         point sets this to the opening V3 pool before calling pool.swap(),
    ///         and clears it after. The callback rejects any sender that does not match.
    uint256 private constant TSLOT_OPENING_POOL     = 7;
    /// @notice Authenticates the legacy nested-V3 callback (data[0] == 0x00):
    ///         `_swapV3Direct` stashes the pool it's about to call here, then clears
    ///         it after the call returns. The callback rejects any sender that does
    ///         not match. Pair with TSLOT_NESTED_V3_TOKEN_IN to lock both axes.
    uint256 private constant TSLOT_NESTED_V3_POOL   = 8;
    /// @notice Authenticates the legacy nested-V3 callback's `tokenIn` parameter.
    ///         `_swapV3Direct` stashes the tokenIn it's about to spend here, then
    ///         clears it after the call returns. The callback rejects any payload
    ///         whose embedded tokenIn does not match.
    uint256 private constant TSLOT_NESTED_V3_TOKEN_IN = 9;
    uint256 private constant TSLOT_START_GAS           = 10; // gasleft() captured at entry for net-tip

    /// @notice Maps non-WETH token → WETH/token V3 pool address for builder tip swaps
    mapping(address => address) public wethPools;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event TokensWithdrawn(address indexed token, uint256 amount, address indexed recipient);

    // =============================================================================
    // ERRORS
    // =============================================================================

    error UnauthorizedAccess(address caller);
    error InvalidCallback(address caller, address expected);
    error InsufficientOutput(uint256 actual, uint256 required);
    error NoTokensToWithdraw(address token);
    error InvalidProfitThreshold(uint256 bps);
    error InvalidSlippage(uint256 minOutput, uint256 payback);
    error TransferFailed(address token, address to, uint256 amount);
    error ReentrancyDetected();
    error InvalidProportions(uint256 totalBps);
    error InvalidBranchCount(uint256 count);
    error InvalidConvergenceToken(address expected, address actual);
    error EmptyPath();
    error PathTooShort(uint256 length);
    error NoForkPoints();
    error CoinbasePaymentFailed(address coinbase, uint256 amount);
    error CoinbasePaymentRequiresWETH(address actualToken); // kept for ABI compatibility
    error NoWethPoolConfigured(address token);
    error InvalidDexType(uint8 dexType);
    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error PathNotCircular(address flashToken, address finalToken);
    error InvalidCallbackType(uint8 cbType);
    error InsufficientProfit(uint256 grossProfit, uint256 gasCostWei);

    // =============================================================================
    // CONSTRUCTOR & MODIFIERS
    // =============================================================================

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedAccess(msg.sender);
        _;
    }

    modifier nonReentrant() {
        assembly {
            if tload(0) {
                mstore(0x00, 0xc5f2be51) // ReentrancyDetected()
                revert(0x1c, 0x04)
            }
            tstore(0, 1)
            tstore(TSLOT_START_GAS, gas())
        }
        _;
        assembly {
            tstore(0, 0)
            tstore(TSLOT_START_GAS, 0)
        }
    }

    // =============================================================================
    // ENTRY POINTS
    // =============================================================================

    function executeFlashLoanArbitrage(
        address flashToken,
        uint256 flashAmount,
        bytes calldata encodedPath,
        uint256 minAmountOut,
        uint256 tipBps
    ) external payable onlyOwner nonReentrant {
        _validateEntry(flashAmount, minAmountOut, tipBps);
        // Store scalars in transient storage — avoid abi.encode overhead
        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  255)        // callback type 255 = simple V3-only path
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   flashAmount)
            tstore(TSLOT_MIN_AMOUNT_OUT, minAmountOut)
            tstore(TSLOT_TIP_BPS,        tipBps)
        }
        // Pass only path bytes through unlock
        poolManager.unlock(encodedPath);
    }

    function executeFlashLoanArbitrageWithForks(
        address flashToken,
        uint256 flashAmount,
        bytes calldata preForkPath,
        ForkPoint[] calldata forkPoints,
        bytes calldata postForkPath,
        uint256 minAmountOut,
        uint256 tipBps
    ) external payable onlyOwner nonReentrant {
        _validateEntry(flashAmount, minAmountOut, tipBps);
        if (forkPoints.length == 0) revert NoForkPoints();
        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  1)          // callback type 1 = fork
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   flashAmount)
            tstore(TSLOT_MIN_AMOUNT_OUT, minAmountOut)
            tstore(TSLOT_TIP_BPS,        tipBps)
        }
        // Pass fork structure data through unlock
        poolManager.unlock(abi.encode(preForkPath, forkPoints, postForkPath));
    }

    function executeFlashLoanArbitrageMultiDex(
        address flashToken,
        uint256 flashAmount,
        bytes calldata encodedPath,
        uint256 minAmountOut,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        _validateEntry(flashAmount, minAmountOut, tipBps);
        address finalToken = _extractLastTokenCalldata(encodedPath);
        if (finalToken != flashToken) revert PathNotCircular(flashToken, finalToken);
        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  2)          // callback type 2 = multi-dex
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   flashAmount)
            tstore(TSLOT_MIN_AMOUNT_OUT, minAmountOut)
            tstore(TSLOT_TIP_BPS,        tipBps)
        }
        // Pass only path bytes through unlock
        poolManager.unlock(encodedPath);
    }

    function executeFlashLoanArbitrageMultiDexWithForks(
        address flashToken,
        uint256 flashAmount,
        bytes calldata preForkPath,
        ForkPoint[] calldata forkPoints,
        bytes calldata postForkPath,
        uint256 minAmountOut,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        _validateEntry(flashAmount, minAmountOut, tipBps);
        if (forkPoints.length == 0) revert NoForkPoints();
        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  3)          // callback type 3 = multi-dex with forks
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   flashAmount)
            tstore(TSLOT_MIN_AMOUNT_OUT, minAmountOut)
            tstore(TSLOT_TIP_BPS,        tipBps)
        }
        // Pass fork structure data through unlock
        poolManager.unlock(abi.encode(preForkPath, forkPoints, postForkPath));
    }

    function executeFlashLoanArbitrageSequential(
        CircleSpec[] calldata circles,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (tipBps > 9999) revert InvalidProfitThreshold(tipBps);
        if (circles.length == 0) revert EmptyPath();

        // Validate each circle: flashAmount > 0, minAmountOut >= flashAmount,
        // and the path must end at flashToken (circular).
        for (uint256 i = 0; i < circles.length; i++) {
            if (circles[i].flashAmount == 0) revert InvalidSlippage(circles[i].minAmountOut, 0);
            if (circles[i].minAmountOut < circles[i].flashAmount) {
                revert InvalidSlippage(circles[i].minAmountOut, circles[i].flashAmount);
            }
            address last = _extractLastTokenCalldata(circles[i].path);
            if (last != circles[i].flashToken) revert PathNotCircular(circles[i].flashToken, last);
        }

        assembly {
            tstore(TSLOT_CALLBACK_TYPE, 4)
            tstore(TSLOT_TIP_BPS, tipBps)
        }

        // Pass the encoded array through unlock; _unlockSequential (Task 3.2) decodes.
        poolManager.unlock(abi.encode(circles));
    }

    function _validateEntry(uint256 flashAmount, uint256 minAmountOut, uint256 tipBps) private pure {
        if (minAmountOut < flashAmount) revert InvalidSlippage(minAmountOut, flashAmount);
        if (tipBps > 9999) revert InvalidProfitThreshold(tipBps);
    }

    // =============================================================================
    // V3 SELF-FLASH ENTRY POINTS (cbType 5: pure, 6: V4-wrapped)
    // =============================================================================

    /// @notice Pure V3 self-flash. Use ONLY when the path contains no V4 hops.
    ///         The closing V3 pool serves as the loan source via exact-output swap-callback;
    ///         this skips poolManager.unlock entirely and saves ~68 k gas vs the V4-flash path.
    /// @param closingPool         V3-style pool (Uniswap V3 / Pancake V3) used as flash + closing leg.
    /// @param loanAmount          Amount of flashToken to drive through the intermediate path.
    /// @param exactOutputAmount   Amount of flashToken to extract from closingPool. Must exceed
    ///                            loanAmount; the difference is the realised profit.
    /// @param intermediatePath    Encoded path for hops 0..N-2 (excludes closing hop).
    ///                            First 20 B = flashToken; last 20 B = closingTokenIn.
    /// @param tipBps              Builder tip as bps of profit (max 9999 / 99.99 %).
    /// @param deadline            Tx-level deadline (unix seconds).
    function executeFlashLoanArbitrageV3SelfFlash(
        address closingPool,
        uint256 loanAmount,
        uint256 exactOutputAmount,
        bytes calldata intermediatePath,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        _validateSelfFlash(loanAmount, exactOutputAmount, tipBps, deadline, intermediatePath);

        address flashToken;
        assembly { flashToken := shr(96, calldataload(intermediatePath.offset)) }
        address closingTokenIn = _extractLastTokenCalldata(intermediatePath);
        if (closingTokenIn == flashToken) revert PathNotCircular(flashToken, closingTokenIn);

        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  5)
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   loanAmount)
            tstore(TSLOT_TIP_BPS,        tipBps)
            tstore(TSLOT_CLOSING_POOL,   closingPool)
        }

        uint256 actualReceived = _runV3SelfFlashSwap(
            closingPool, flashToken, closingTokenIn,
            loanAmount, exactOutputAmount, intermediatePath
        );

        uint256 profit = actualReceived - loanAmount;
        _distributeProfitWeth(flashToken, profit, tipBps);

        assembly { tstore(TSLOT_CLOSING_POOL, 0) }
    }

    /// @notice V3 self-flash wrapped in poolManager.unlock — for circles whose closing leg is V3
    ///         but which include a V4 hop somewhere in the path. The unlock context lets the V4
    ///         mid-leg execute via _v4Settle/_v4Take normally; the V3 closing-pool callback
    ///         supplies the loan, so we still avoid poolManager.take/settle of flashToken.
    function executeFlashLoanArbitrageV3SelfFlashV4Wrapped(
        address closingPool,
        uint256 loanAmount,
        uint256 exactOutputAmount,
        bytes calldata intermediatePath,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        _validateSelfFlash(loanAmount, exactOutputAmount, tipBps, deadline, intermediatePath);

        address flashToken;
        assembly { flashToken := shr(96, calldataload(intermediatePath.offset)) }
        address closingTokenIn = _extractLastTokenCalldata(intermediatePath);
        if (closingTokenIn == flashToken) revert PathNotCircular(flashToken, closingTokenIn);

        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  6)
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   loanAmount)
            tstore(TSLOT_TIP_BPS,        tipBps)
            tstore(TSLOT_CLOSING_POOL,   closingPool)
        }

        // unlockCallback handles _runV3SelfFlashSwap + profit distribution for cbType==6.
        poolManager.unlock(abi.encode(closingPool, exactOutputAmount, intermediatePath));

        assembly { tstore(TSLOT_CLOSING_POOL, 0) }
    }

    // =============================================================================
    // V2/SUSHI CLOSING SELF-FLASH ENTRY POINT (cbType 8)
    // =============================================================================

    /// @notice V2/Sushi closing self-flash. Uses the LAST pool of an arb circle (a V2 or Sushi
    ///         pair) as a zero-fee flash source. The pair sends us `exactOutputAmount` of
    ///         `flashToken`; in the `uniswapV2Call` callback we run the intermediate path
    ///         (hops 0..N-2) to produce the `closingTokenIn` needed to repay the pair.
    ///         Structurally mirrors `executeFlashLoanArbitrageV3SelfFlash` but uses the V2
    ///         flash-swap interface (pair.swap with non-empty calldata) instead of V3's
    ///         exact-output swap-callback.
    ///
    /// @param closingPair       V2/Sushi pair used as the flash source and closing leg.
    ///                          Must hold flashToken as one of its tokens.
    /// @param loanAmount        Amount of flashToken fed into the intermediate path (hops 0..N-2).
    ///                          This is also the amount the intermediate path receives as input.
    /// @param exactOutputAmount Amount of flashToken to borrow from closingPair. Must be >
    ///                          loanAmount; the difference is the realised profit.
    /// @param intermediatePath  Encoded path for hops 0..N-2 (excludes closing hop).
    ///                          First 20 B = flashToken; last 20 B = closingTokenIn.
    /// @param tipBps            Builder tip as bps of profit (max 9999 / 99.99%).
    /// @param deadline          Tx-level deadline (unix seconds).
    function executeFlashLoanArbitrageV2SelfFlash(
        address closingPair,
        uint256 loanAmount,
        uint256 exactOutputAmount,
        bytes calldata intermediatePath,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        _validateSelfFlash(loanAmount, exactOutputAmount, tipBps, deadline, intermediatePath);

        address flashToken;
        assembly { flashToken := shr(96, calldataload(intermediatePath.offset)) }
        address closingTokenIn = _extractLastTokenCalldata(intermediatePath);
        if (closingTokenIn == flashToken) revert PathNotCircular(flashToken, closingTokenIn);

        assembly {
            tstore(TSLOT_CALLBACK_TYPE, 8)
            tstore(TSLOT_FLASH_TOKEN,   flashToken)
            tstore(TSLOT_FLASH_AMOUNT,  loanAmount)
            tstore(TSLOT_TIP_BPS,       tipBps)
            tstore(TSLOT_CLOSING_POOL,  closingPair)
        }

        uint256 balBefore = IERC20(flashToken).balanceOf(address(this));

        // V2/Sushi flash-swap: request exactOutputAmount of flashToken from closingPair.
        // data is non-empty so the pair calls uniswapV2Call on us.
        bool flashIsToken0 = flashToken < closingTokenIn;
        bytes memory cbData = abi.encodePacked(bytes1(0x01), closingTokenIn, intermediatePath);
        if (flashIsToken0) {
            IUniswapV2Pair(closingPair).swap(exactOutputAmount, 0, address(this), cbData);
        } else {
            IUniswapV2Pair(closingPair).swap(0, exactOutputAmount, address(this), cbData);
        }

        uint256 profit = IERC20(flashToken).balanceOf(address(this)) - balBefore;
        _distributeProfitWeth(flashToken, profit, tipBps);

        assembly { tstore(TSLOT_CLOSING_POOL, 0) }
    }

    // =============================================================================
    // V2/SUSHI CLOSING SELF-FLASH V4-WRAPPED ENTRY POINT (cbType 9)
    // =============================================================================

    /// @notice V2/Sushi closing self-flash wrapped in poolManager.unlock — for circles whose
    ///         closing leg is a V2/Sushi pair but which include a V4 hop somewhere in the
    ///         intermediate path. The unlock context lets the V4 mid-leg execute via
    ///         _v4Settle/_v4Take normally; the V2 flash-swap (pair.swap with non-empty data)
    ///         supplies the loan and its callback runs the intermediate path.
    ///
    ///         Mirrors `executeFlashLoanArbitrageV3SelfFlashV4Wrapped` (cbType 6) but triggers
    ///         the V2 closing swap inside `unlockCallback` (cbType 9) rather than the V3
    ///         swap-callback.
    ///
    /// @param closingPair       V2/Sushi pair used as the flash source and closing leg.
    /// @param loanAmount        Amount of flashToken fed into the intermediate path.
    /// @param exactOutputAmount Amount of flashToken to borrow from closingPair.
    /// @param intermediatePath  Encoded path for hops 0..N-2. First 20B = flashToken; last 20B = closingTokenIn.
    /// @param tipBps            Builder tip as bps of profit (max 9999 / 99.99%).
    /// @param deadline          Tx-level deadline (unix seconds).
    function executeFlashLoanArbitrageV2SelfFlashV4Wrapped(
        address closingPair,
        uint256 loanAmount,
        uint256 exactOutputAmount,
        bytes calldata intermediatePath,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        _validateSelfFlash(loanAmount, exactOutputAmount, tipBps, deadline, intermediatePath);

        address flashToken;
        assembly { flashToken := shr(96, calldataload(intermediatePath.offset)) }
        address closingTokenIn = _extractLastTokenCalldata(intermediatePath);
        if (closingTokenIn == flashToken) revert PathNotCircular(flashToken, closingTokenIn);

        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  9)
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   loanAmount)
            tstore(TSLOT_TIP_BPS,        tipBps)
            tstore(TSLOT_CLOSING_POOL,   closingPair)
        }

        // unlockCallback handles the V2 flash-swap + profit distribution for cbType==9.
        poolManager.unlock(abi.encode(closingPair, exactOutputAmount, intermediatePath));

        assembly { tstore(TSLOT_CLOSING_POOL, 0) }
    }

    function _validateSelfFlash(
        uint256 loanAmount,
        uint256 exactOutputAmount,
        uint256 tipBps,
        uint256 deadline,
        bytes calldata intermediatePath
    ) private view {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (tipBps > 9999) revert InvalidProfitThreshold(tipBps);
        if (loanAmount == 0) revert InvalidSlippage(exactOutputAmount, 0);
        if (exactOutputAmount <= loanAmount) revert InvalidSlippage(exactOutputAmount, loanAmount);
        if (intermediatePath.length < 64) revert PathTooShort(intermediatePath.length);
    }

    // =============================================================================
    // V3 OPENING SELF-FLASH ENTRY POINT (cbType 7)
    // =============================================================================

    /// @notice V3 opening self-flash. Use the FIRST pool of an arb circle as a zero-fee flash
    ///         source via an exact-INPUT swap; the swap callback runs the remainder of the
    ///         circle (hops 1..N-1) and repays the opening pool from the realised WETH.
    ///
    ///         Use ONLY when the path's hops 1..N-1 contain no V4 hops. Circles that include
    ///         a V4 mid-hop must fall through to the V4-flash entry point (caller's filter).
    ///
    /// @param openingPool      V3-style pool (Uniswap V3 / Pancake V3) used as flash + opening leg.
    /// @param loanAmount       Exact-input amount of flashToken pushed into openingPool.
    /// @param remainingPath    Encoded path for hops 1..N-1. First 20 B = openingPool's output
    ///                         token (the intermediate token); last 20 B = WETH (the flash token
    ///                         we will repay with). Minimum length 64 B (one 44-B hop).
    /// @param minAmountOut     Strict floor on the WETH amount produced by `remainingPath`.
    ///                         Must satisfy `minAmountOut > loanAmount` (break-even is a
    ///                         guaranteed loss after gas).
    /// @param tipBps           Builder tip as bps of profit (max 9999 / 99.99 %).
    /// @param deadline         Tx-level deadline (unix seconds).
    ///
    ///         INVARIANT: the contract must hold zero pre-existing balance of `flashToken`
    ///         (= last 20 B of remainingPath) and of the intermediate token (= first 20 B of
    ///         remainingPath). Same invariant `_distributeProfitWeth` already assumes; documented
    ///         here because the callback uses `balanceOf` to read what the opening pool delivered.
    function executeFlashLoanArbitrageV3OpeningSelfFlash(
        address openingPool,
        uint256 loanAmount,
        bytes calldata remainingPath,
        uint256 minAmountOut,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        _validateOpeningSelfFlash(loanAmount, minAmountOut, tipBps, deadline, remainingPath);

        // intermediateToken = first 20 B of remainingPath = opening pool's output token.
        address intermediateToken;
        assembly { intermediateToken := shr(96, calldataload(remainingPath.offset)) }

        // flashToken = last 20 B of remainingPath = WETH (the token we repay with).
        address flashToken = _extractLastTokenCalldata(remainingPath);
        if (intermediateToken == flashToken) revert PathNotCircular(flashToken, intermediateToken);

        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  7)
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_FLASH_AMOUNT,   loanAmount)
            tstore(TSLOT_MIN_AMOUNT_OUT, minAmountOut)
            tstore(TSLOT_TIP_BPS,        tipBps)
            tstore(TSLOT_OPENING_POOL,   openingPool)
        }

        // Snapshot flashToken balance before the opening swap. After the callback returns,
        // any flashToken left in the contract above `balBefore` is the realised profit (the
        // callback paid `owed` to openingPool and kept the residual here).
        uint256 balBefore = IERC20(flashToken).balanceOf(address(this));

        bool zeroForOne = flashToken < intermediateToken;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? uint160(4295128740)
            : uint160(1461446703485210103287273052203988822378723970341);

        // Callback payload: [0x02 discriminator][remainingPath]. The first 20 B of remainingPath
        // IS the intermediate token; no separate field needed.
        bytes memory cbData = abi.encodePacked(bytes1(0x02), remainingPath);

        IUniswapV3Pool(openingPool).swap(
            address(this),
            zeroForOne,
            int256(loanAmount),       // positive = exact input
            sqrtPriceLimitX96,
            cbData
        );

        uint256 balAfter = IERC20(flashToken).balanceOf(address(this));
        uint256 profit = balAfter - balBefore;
        _distributeProfitWeth(flashToken, profit, tipBps);

        assembly { tstore(TSLOT_OPENING_POOL, 0) }
    }

    /// @dev Validation for opening self-flash. Distinct from `_validateSelfFlash` because:
    ///        - it uses minAmountOut (strict > loanAmount) instead of exactOutputAmount,
    ///        - it imposes the 44-byte hop-grid constraint on `remainingPath` (the closing
    ///          variant does not, because its callback validates `intermediatePath` indirectly
    ///          via `_executeMultiDexPath`'s own length checks).
    function _validateOpeningSelfFlash(
        uint256 loanAmount,
        uint256 minAmountOut,
        uint256 tipBps,
        uint256 deadline,
        bytes calldata remainingPath
    ) private view {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (tipBps > 9999) revert InvalidProfitThreshold(tipBps);
        if (loanAmount == 0) revert InvalidSlippage(minAmountOut, 0);
        // Strict `<=`: break-even (minAmountOut == loanAmount) is a guaranteed loss after gas.
        if (minAmountOut <= loanAmount) revert InvalidSlippage(minAmountOut, loanAmount);
        if (remainingPath.length < 64) revert PathTooShort(remainingPath.length);
        // 44-byte hop grid: total = 20 (first token) + N * 44 hops.
        if ((remainingPath.length - 20) % 44 != 0) revert PathTooShort(remainingPath.length);
    }

    // =============================================================================
    // V2/SUSHI OPENING SELF-FLASH ENTRY POINT (cbType 10)
    // =============================================================================

    /// @notice V2/Sushi opening self-flash. Use the FIRST pool of an arb circle (a V2/Sushi
    ///         pair) as a zero-cost flash source via an exact-OUTPUT swap; the pair's callback
    ///         runs the remainder of the circle (hops 1..N-1) producing flashToken, then repays
    ///         the opening pair the exact flashToken it is owed (computed via _getAmountIn).
    ///
    ///         Use ONLY when the path's hops 1..N-1 contain no V4 hops.
    ///
    /// @param openingPair          V2/Sushi pair used as flash source and opening leg.
    /// @param intermediateOutAmount Exact amount of intermediate token to pull from openingPair
    ///                              (amount0 or amount1 per the intermediateToken ordering).
    /// @param remainingPath        Encoded path for hops 1..N-1. First 20 B = intermediate token
    ///                              (what we receive from openingPair); last 20 B = flashToken
    ///                              (what we repay openingPair with). Minimum 64 B (one 44-B hop).
    /// @param minAmountOut         Strict floor on flashToken produced by remainingPath.
    ///                              Must be > 0 (checked; the owed amount is unknown until the
    ///                              callback, so we cannot compare against it at entry time).
    /// @param tipBps               Builder tip as bps of profit (max 9999 / 99.99 %).
    /// @param deadline             Tx-level deadline (unix seconds).
    ///
    ///         INVARIANT: the contract must hold zero pre-existing balance of flashToken and of
    ///         the intermediate token before the opening swap.
    function executeFlashLoanArbitrageV2OpeningSelfFlash(
        address openingPair,
        uint256 intermediateOutAmount,
        bytes calldata remainingPath,
        uint256 minAmountOut,
        uint256 tipBps,
        uint256 deadline
    ) external payable onlyOwner nonReentrant {
        _validateV2OpeningSelfFlash(intermediateOutAmount, minAmountOut, tipBps, deadline, remainingPath);

        // intermediateToken = first 20 B of remainingPath = what the opening pair will send us.
        address intermediateToken;
        assembly { intermediateToken := shr(96, calldataload(remainingPath.offset)) }

        // flashToken = last 20 B of remainingPath = the token we will repay the opening pair.
        address flashToken = _extractLastTokenCalldata(remainingPath);
        if (intermediateToken == flashToken) revert PathNotCircular(flashToken, intermediateToken);

        assembly {
            tstore(TSLOT_CALLBACK_TYPE,  10)
            tstore(TSLOT_FLASH_TOKEN,    flashToken)
            tstore(TSLOT_MIN_AMOUNT_OUT, minAmountOut)
            tstore(TSLOT_TIP_BPS,        tipBps)
            tstore(TSLOT_OPENING_POOL,   openingPair)
        }

        // Snapshot flashToken balance before the opening swap. After the callback returns,
        // any flashToken left above balBefore is the realised profit (the callback paid owedFlash
        // to the opening pair and the residual stays here).
        uint256 balBefore = IERC20(flashToken).balanceOf(address(this));

        // V2/Sushi flash-swap: request intermediateOutAmount of intermediateToken from openingPair.
        // Non-empty data triggers uniswapV2Call → _handleV2OpeningSelfFlashCallback (cbType 10).
        // Ordering: intermediateToken is amount0 if intermediateToken < flashToken.
        bool intermediateIsToken0 = intermediateToken < flashToken;
        bytes memory cbData = abi.encodePacked(bytes1(0x02), remainingPath);
        if (intermediateIsToken0) {
            IUniswapV2Pair(openingPair).swap(intermediateOutAmount, 0, address(this), cbData);
        } else {
            IUniswapV2Pair(openingPair).swap(0, intermediateOutAmount, address(this), cbData);
        }

        uint256 balAfter = IERC20(flashToken).balanceOf(address(this));
        uint256 profit = balAfter - balBefore;
        _distributeProfitWeth(flashToken, profit, tipBps);

        assembly { tstore(TSLOT_OPENING_POOL, 0) }
    }

    /// @dev Validation for V2/Sushi opening self-flash. Mirrors _validateOpeningSelfFlash
    ///      but drops the loanAmount vs minAmountOut comparison: the flashToken owed to the
    ///      opening pair is not known until the callback (it depends on live reserves), so we
    ///      can only validate that intermediateOutAmount and minAmountOut are non-zero, the
    ///      path grid is valid, and the standard deadline/tipBps constraints hold.
    function _validateV2OpeningSelfFlash(
        uint256 intermediateOutAmount,
        uint256 minAmountOut,
        uint256 tipBps,
        uint256 deadline,
        bytes calldata remainingPath
    ) private view {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (tipBps > 9999) revert InvalidProfitThreshold(tipBps);
        if (intermediateOutAmount == 0) revert InvalidSlippage(minAmountOut, 0);
        if (minAmountOut == 0) revert InvalidSlippage(minAmountOut, 0);
        if (remainingPath.length < 64) revert PathTooShort(remainingPath.length);
        // 44-byte hop grid: total = 20 (first token) + N * 44 hops.
        if ((remainingPath.length - 20) % 44 != 0) revert PathTooShort(remainingPath.length);
    }

    /// @notice Triggers the closing-pool exact-output swap and returns the actually received
    ///         amount of flashToken. Reverts if the V3 pool partial-fills (insufficient liquidity).
    function _runV3SelfFlashSwap(
        address closingPool,
        address flashToken,
        address closingTokenIn,
        uint256 loanAmount,
        uint256 exactOutputAmount,
        bytes memory intermediatePath
    ) private returns (uint256 actualReceived) {
        loanAmount; // silence unused-arg warning; loanAmount is read via TSLOT inside callback

        bool zeroForOne = closingTokenIn < flashToken;

        // Discriminator 0x01 = top-level self-flash; intermediate path follows closingTokenIn.
        bytes memory cbData = abi.encodePacked(
            bytes1(0x01),
            closingTokenIn,
            intermediatePath
        );

        uint160 sqrtPriceLimitX96 = zeroForOne
            ? uint160(4295128740)
            : uint160(1461446703485210103287273052203988822378723970341);

        (int256 amount0, int256 amount1) = IUniswapV3Pool(closingPool).swap(
            address(this),
            zeroForOne,
            -int256(exactOutputAmount), // negative = exact output
            sqrtPriceLimitX96,
            cbData
        );

        actualReceived = uint256(zeroForOne ? -amount1 : -amount0);
        if (actualReceived < exactOutputAmount) {
            revert InsufficientOutput(actualReceived, exactOutputAmount);
        }
    }

    // =============================================================================
    // V4 UNLOCK CALLBACK
    // =============================================================================

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != UNISWAP_V4_POOL_MANAGER) {
            revert InvalidCallback(msg.sender, UNISWAP_V4_POOL_MANAGER);
        }

        // Read scalars from transient storage
        uint8 callbackType;
        address flashToken;
        uint256 flashAmount;
        uint256 minAmountOut;
        uint256 tipBps;
        assembly {
            callbackType  := tload(TSLOT_CALLBACK_TYPE)
            flashToken    := tload(TSLOT_FLASH_TOKEN)
            flashAmount   := tload(TSLOT_FLASH_AMOUNT)
            minAmountOut  := tload(TSLOT_MIN_AMOUNT_OUT)
            tipBps        := tload(TSLOT_TIP_BPS)
        }

        if (callbackType == 4) {
            _unlockSequential(data);
            return "";
        }

        if (callbackType == 6) {
            _unlockSelfFlashV4Wrapped(data, flashToken, flashAmount, tipBps);
            return "";
        }

        if (callbackType == 9) {
            _unlockV2SelfFlashV4Wrapped(data, flashToken, flashAmount, tipBps);
            return "";
        }

        poolManager.take(Currency.wrap(flashToken), address(this), flashAmount);

        uint256 amountOut;

        if (callbackType == 1) {
            // Fork arbitrage (V3-style paths)
            (
                bytes memory preForkPath,
                ForkPoint[] memory forkPoints,
                bytes memory postForkPath
            ) = abi.decode(data, (bytes, ForkPoint[], bytes));

            uint256 currentAmount = flashAmount;
            if (preForkPath.length > 0) {
                currentAmount = _executeMultiDexPath(preForkPath, currentAmount, 0);
            }
            for (uint256 i = 0; i < forkPoints.length; i++) {
                currentAmount = _executeForkPoint(forkPoints[i], currentAmount, i);
            }
            if (postForkPath.length > 0) {
                currentAmount = _executeMultiDexPath(postForkPath, currentAmount, 0);
            }
            amountOut = currentAmount;
        } else if (callbackType == 2) {
            // Simple multi-dex: data IS the encoded path
            bytes memory path = data;
            amountOut = _executeMultiDexPath(path, flashAmount, minAmountOut);
        } else if (callbackType == 3) {
            // Multi-dex with forks
            (
                bytes memory preForkPath,
                ForkPoint[] memory forkPoints,
                bytes memory postForkPath
            ) = abi.decode(data, (bytes, ForkPoint[], bytes));

            uint256 currentAmount = flashAmount;
            if (preForkPath.length > 0) {
                currentAmount = _executeMultiDexPath(preForkPath, currentAmount, 0);
            }
            for (uint256 i = 0; i < forkPoints.length; i++) {
                currentAmount = _executeForkPoint(forkPoints[i], currentAmount, i);
            }
            if (postForkPath.length > 0) {
                currentAmount = _executeMultiDexPath(postForkPath, currentAmount, 0);
            }
            amountOut = currentAmount;
        } else if (callbackType == 255) {
            // Simple path: data IS the encoded path
            bytes memory path = data;
            amountOut = _executeMultiDexPath(path, flashAmount, minAmountOut);
        } else {
            revert InvalidCallback(msg.sender, UNISWAP_V4_POOL_MANAGER);
        }

        _settleAndDistribute(flashToken, flashAmount, amountOut, minAmountOut, tipBps);
        return "";
    }

    // =============================================================================
    // SELF-FLASH V4-WRAPPED (callbackType == 6)
    // =============================================================================

    /// @notice Inside an active poolManager.unlock context, run the V3 self-flash flow.
    ///         Used when the circle has at least one V4 swap leg in the middle (which needs
    ///         the unlock context for sync/settle/take), but the closing leg is still V3 so
    ///         we can use the V3 swap-callback as the loan source instead of poolManager.take.
    function _unlockSelfFlashV4Wrapped(
        bytes calldata data,
        address flashToken,
        uint256 loanAmount,
        uint256 tipBps
    ) private {
        (address closingPool, uint256 exactOutputAmount, bytes memory intermediatePath) =
            abi.decode(data, (address, uint256, bytes));

        address closingTokenIn = _extractLastTokenMemory(intermediatePath);

        uint256 actualReceived = _runV3SelfFlashSwap(
            closingPool,
            flashToken,
            closingTokenIn,
            loanAmount,
            exactOutputAmount,
            intermediatePath
        );

        uint256 profit = actualReceived - loanAmount;
        _distributeProfitWeth(flashToken, profit, tipBps);
    }

    // =============================================================================
    // V2/SUSHI SELF-FLASH V4-WRAPPED (callbackType == 9)
    // =============================================================================

    /// @notice Inside an active poolManager.unlock context, run the V2/Sushi self-flash flow.
    ///         Used when the circle has at least one V4 swap leg in the intermediate path (which
    ///         needs the unlock context for sync/settle/take), but the closing leg is a V2/Sushi
    ///         pair so we use the V2 flash-swap interface as the loan source instead of
    ///         poolManager.take. Mirrors `_unlockSelfFlashV4Wrapped` (cbType 6) exactly but
    ///         triggers pair.swap (V2) instead of pool.swap (V3).
    function _unlockV2SelfFlashV4Wrapped(
        bytes calldata data,
        address flashToken,
        uint256 loanAmount,
        uint256 tipBps
    ) private {
        (address closingPair, uint256 exactOutputAmount, bytes memory intermediatePath) =
            abi.decode(data, (address, uint256, bytes));

        address closingTokenIn = _extractLastTokenMemory(intermediatePath);

        // Snapshot balance before the V2 flash-swap to measure profit exactly.
        uint256 balBefore = IERC20(flashToken).balanceOf(address(this));

        // V2/Sushi flash-swap: request exactOutputAmount of flashToken from closingPair.
        // Non-empty data triggers uniswapV2Call → _handleV2SelfFlashCallback (cbType 9).
        // Because we are inside poolManager.unlock, the V4 mid-hop in the intermediate
        // path can settle/take normally via _v4Settle/_v4Take.
        bool flashIsToken0 = flashToken < closingTokenIn;
        bytes memory cbData = abi.encodePacked(bytes1(0x01), closingTokenIn, intermediatePath);
        if (flashIsToken0) {
            IUniswapV2Pair(closingPair).swap(exactOutputAmount, 0, address(this), cbData);
        } else {
            IUniswapV2Pair(closingPair).swap(0, exactOutputAmount, address(this), cbData);
        }

        uint256 profit = IERC20(flashToken).balanceOf(address(this)) - balBefore;
        _distributeProfitWeth(flashToken, profit, tipBps);
    }

    /// @notice Memory variant of _extractLastTokenCalldata. Returns the trailing 20 bytes
    ///         of `path` as an address.
    function _extractLastTokenMemory(bytes memory path) private pure returns (address tokenAddress) {
        if (path.length < 20) revert PathTooShort(path.length);
        uint256 lastTokenOffset = path.length - 20;
        assembly {
            tokenAddress := shr(96, mload(add(add(path, 32), lastTokenOffset)))
        }
    }

    // =============================================================================
    // SELF-FLASH CALLBACK HANDLER (cbType 5 or 6 from V3 closing pool)
    // =============================================================================

    /// @dev Invoked from the V3/Pancake-V3 swap callback when data[0] == 0x01.
    ///      Authenticates msg.sender against TSLOT_CLOSING_POOL, runs the intermediate
    ///      path with `loanAmount` as the input, and pays the closing pool exactly `owed`.
    ///      Any residual closingTokenIn produced beyond `owed` stays in contract balance.
    function _handleSelfFlashCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) private {
        // Authenticate: only the stashed closing pool may invoke this branch.
        // Without this, a malicious in-path pool could re-enter uniswapV3SwapCallback
        // with a forged 0x01-prefix payload and run an attacker-controlled path.
        address expected;
        assembly { expected := tload(TSLOT_CLOSING_POOL) }
        if (msg.sender != expected) revert InvalidCallback(msg.sender, expected);

        // data layout: [0x01 1B][closingTokenIn 20B][intermediatePath ≥64B]
        if (data.length < 21 + 64) revert PathTooShort(data.length);

        address closingTokenIn;
        assembly { closingTokenIn := shr(96, calldataload(add(data.offset, 1))) }
        bytes calldata intermediatePath = data[21:];

        uint8 cbType;
        uint256 loanAmount;
        assembly {
            cbType := tload(TSLOT_CALLBACK_TYPE)
            loanAmount := tload(TSLOT_FLASH_AMOUNT)
        }
        if (cbType != 5 && cbType != 6) revert InvalidCallbackType(cbType);

        int256 owed = amount0Delta > 0 ? amount0Delta : amount1Delta;
        if (owed <= 0) revert InsufficientOutput(0, 0);

        // Execute intermediate path. cbType==5: no V4 hop allowed (would revert here for
        // lack of unlock context). cbType==6: V4 mid-leg works because we are nested
        // inside an active poolManager.unlock callback.
        bytes memory pathMem = intermediatePath;
        uint256 produced = _executeMultiDexPath(pathMem, loanAmount, 0);

        // State-divergence guard: closing pool moved (X up) or intermediate moved (Y down).
        if (produced < uint256(owed)) revert InsufficientOutput(produced, uint256(owed));

        // Pay exactly `owed`; any residual produced beyond owed stays in contract balance.
        // NOTE: It is structurally impossible for closingPool to also appear as a mid-hop
        // in intermediatePath — V3's own pool-level `locked` flag would revert the second
        // swap() with LOK regardless of any check here.
        _safeTransfer(closingTokenIn, msg.sender, uint256(owed));
    }

    // =============================================================================
    // V2/SUSHI SELF-FLASH CALLBACK HANDLER (cbType 8 from V2/Sushi closing pair)
    // =============================================================================

    /// @dev Invoked from `uniswapV2Call` when data[0] == 0x01 (cbType 8).
    ///      Authenticates msg.sender against TSLOT_CLOSING_POOL (consume-once), runs
    ///      the intermediate path with `loanAmount` WETH as input, and repays the pair
    ///      exactly `owed` of `closingTokenIn` (computed via _getAmountIn against the
    ///      pair's pre-swap reserves). Mirrors `_handleSelfFlashCallback` for V2 pairs.
    ///
    ///      Data layout (from uniswapV2Call): [0x01 1B][closingTokenIn 20B][intermediatePath ≥64B]
    ///      V2 delta convention: amount0/amount1 = amounts the pair SENT US (positive = received).
    function _handleV2SelfFlashCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) private {
        // Authenticate: only the stashed closing pair may invoke this branch.
        // Cleared immediately (consume-once) to prevent a malicious pair from calling
        // the callback a second time in the same transaction.
        address expected;
        assembly { expected := tload(TSLOT_CLOSING_POOL) }
        if (msg.sender != expected) revert InvalidCallback(msg.sender, expected);
        assembly { tstore(TSLOT_CLOSING_POOL, 0) } // consume-once

        // data layout: [0x01 1B][closingTokenIn 20B][intermediatePath ≥64B]
        if (data.length < 21 + 64) revert PathTooShort(data.length);

        address closingTokenIn;
        assembly { closingTokenIn := shr(96, calldataload(add(data.offset, 1))) }
        bytes calldata intermediatePath = data[21:];

        uint8 cbType;
        uint256 loanAmount;
        address flashToken;
        assembly {
            cbType     := tload(TSLOT_CALLBACK_TYPE)
            loanAmount := tload(TSLOT_FLASH_AMOUNT)
            flashToken := tload(TSLOT_FLASH_TOKEN)
        }
        if (cbType != 8 && cbType != 9) revert InvalidCallbackType(cbType);

        // amount0/amount1 are the tokens the pair sent us. Exactly one is non-zero:
        // it equals exactOutputAmount and should be flashToken.
        uint256 outAmt = amount0 > 0 ? amount0 : amount1;

        // Compute how much closingTokenIn we owe the pair, using pre-swap reserves.
        // V2 transfers tokens then calls callback before updating reserves, so
        // getReserves() still reflects the state before the swap — correct for _getAmountIn.
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(msg.sender).getReserves();
        // closingTokenIn is token0 when closingTokenIn < flashToken (pair stores token0 < token1)
        (uint256 reserveIn, uint256 reserveOut) = closingTokenIn < flashToken
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));
        uint256 owed = _getAmountIn(outAmt, reserveIn, reserveOut);

        // Run the intermediate path: flashToken (loanAmount) → closingTokenIn (produced).
        // Pass minAmountOut=0; we enforce solvency via the produced >= owed check below.
        bytes memory pathMem = intermediatePath;
        uint256 produced = _executeMultiDexPath(pathMem, loanAmount, 0);

        // Solvency: must always be able to repay the closing pair.
        if (produced < owed) revert InsufficientOutput(produced, owed);

        // Repay the closing pair exactly `owed`. Any produced beyond owed stays in the
        // contract and contributes to the profit picked up by the entry-point balance delta.
        _safeTransfer(closingTokenIn, msg.sender, owed);
    }

    // =============================================================================
    // V2/SUSHI OPENING SELF-FLASH CALLBACK HANDLER (cbType 10 from V2/Sushi opening pair)
    // =============================================================================

    /// @dev Invoked from `uniswapV2Call` when data[0] == 0x02 (cbType 10).
    ///      Authenticates msg.sender against TSLOT_OPENING_POOL (consume-once), determines
    ///      the intermediate amount the opening pair sent us (amount0 or amount1), computes
    ///      owed flashToken via _getAmountIn against pre-swap reserves, runs remainingPath
    ///      from the intermediate token balance back to flashToken, enforces solvency, and
    ///      repays the opening pair exactly `owedFlash`. Residual flashToken stays in the
    ///      contract and is picked up by the entry point's balBefore/balAfter delta.
    ///
    ///      Data layout (from uniswapV2Call): [0x02 1B][remainingPath ≥64B]
    ///      remainingPath[0:20] = intermediate token (what the pair sent us).
    ///      remainingPath[-20:] = flashToken (what we repay the pair with).
    ///
    ///      V2 delta convention: amount0/amount1 = amounts the pair SENT US (positive = received).
    function _handleV2OpeningSelfFlashCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) private {
        // Auth: only the stashed opening pair may invoke this branch.
        // Consume-once: cleared immediately to prevent replay by a malicious pair.
        address expected;
        assembly { expected := tload(TSLOT_OPENING_POOL) }
        if (msg.sender != expected) revert InvalidCallback(msg.sender, expected);
        assembly { tstore(TSLOT_OPENING_POOL, 0) } // consume-once

        // data layout: [0x02 1B][remainingPath ≥64B]
        if (data.length < 1 + 64) revert PathTooShort(data.length);
        bytes calldata remainingPath = data[1:];

        uint8 cbType;
        uint256 minAmountOut;
        address flashToken;
        assembly {
            cbType       := tload(TSLOT_CALLBACK_TYPE)
            minAmountOut := tload(TSLOT_MIN_AMOUNT_OUT)
            flashToken   := tload(TSLOT_FLASH_TOKEN)
        }
        if (cbType != 10) revert InvalidCallbackType(cbType);

        // The opening pair sent us intermediateOut tokens (amount0 or amount1, exactly one non-zero).
        uint256 intermediateOut = amount0 > 0 ? amount0 : amount1;

        // intermediateToken = first 20 B of remainingPath.
        address intermediateToken;
        assembly { intermediateToken := shr(96, calldataload(remainingPath.offset)) }

        // Compute how much flashToken we owe the pair, using pre-swap reserves.
        // V2 transfers tokens then calls callback before updating reserves, so
        // getReserves() still reflects the state before the swap — correct for _getAmountIn.
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(msg.sender).getReserves();
        // flashToken is token0 when flashToken < intermediateToken (pair stores token0 < token1)
        (uint256 reserveIn, uint256 reserveOut) = flashToken < intermediateToken
            ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        uint256 owedFlash = _getAmountIn(intermediateOut, reserveIn, reserveOut);

        // Read the intermediate balance delivered by the opening pair. Use balanceOf (not
        // delta) to mirror _handleOpeningSelfFlashCallback's exact approach: the pair has
        // already transferred intermediateToken to this contract before invoking us.
        uint256 receivedAmount = IERC20(intermediateToken).balanceOf(address(this));

        // Run the remaining circle: intermediateToken → ... → flashToken.
        // Pass minAmountOut=0; solvency is enforced below; profit floor is testMode-gated.
        bytes memory pathMem = remainingPath;
        uint256 produced = _executeMultiDexPath(pathMem, receivedAmount, 0);

        // Solvency: must always be able to repay the opening pair, regardless of testMode.
        if (produced < owedFlash) revert InsufficientOutput(produced, owedFlash);
        // Profit floor: testMode-gated so integration tests can run lossy paths end-to-end.
        if (!testMode && produced < minAmountOut) revert InsufficientOutput(produced, minAmountOut);

        // Repay the opening pair exactly `owedFlash`. Residual = produced - owedFlash stays
        // in the contract and is picked up by the entry point's balBefore/balAfter delta.
        _safeTransfer(flashToken, msg.sender, owedFlash);
    }

    /// @dev Invoked from the V3/Pancake-V3 swap callback when data[0] == 0x02 (cbType=7).
    ///      Authenticates msg.sender against TSLOT_OPENING_POOL, asserts the pool fully
    ///      consumed the exact-input amount, runs `remainingPath` against the actual amount
    ///      the opening pool delivered (read via `balanceOf` of the intermediate token), then
    ///      pays the opening pool exactly `owed` of `flashToken`. Residual stays in the
    ///      contract balance and is picked up by the entry point's balBefore/balAfter delta.
    ///
    ///      INVARIANT: the contract must hold zero pre-existing balance of the intermediate
    ///      token before the opening swap. Same invariant `_distributeProfitWeth` already
    ///      assumes for `flashToken`. The entry point's documentation enforces this contract-wide.
    function _handleOpeningSelfFlashCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) private {
        // Auth: only the stashed opening pool may invoke this branch.
        address expected;
        assembly { expected := tload(TSLOT_OPENING_POOL) }
        if (msg.sender != expected) revert InvalidCallback(msg.sender, expected);

        // Layout: [0x02 1B][remainingPath ≥64B]. remainingPath[0:20] = intermediate token.
        if (data.length < 1 + 64) revert PathTooShort(data.length);
        bytes calldata remainingPath = data[1:];

        uint8 cbType;
        uint256 loanAmount;
        uint256 minAmountOut;
        address flashToken;
        assembly {
            cbType        := tload(TSLOT_CALLBACK_TYPE)
            loanAmount    := tload(TSLOT_FLASH_AMOUNT)
            minAmountOut  := tload(TSLOT_MIN_AMOUNT_OUT)
            flashToken    := tload(TSLOT_FLASH_TOKEN)
        }
        if (cbType != 7) revert InvalidCallbackType(cbType);

        // Exact-input swap-callback delta convention:
        //   owed  > 0 = flashToken we must pay back to the pool.
        //   recvD < 0 = intermediate token the pool sent us.
        // For an exact-input swap at the price boundary the pool ALWAYS consumes the full
        // input — but if liquidity runs out at the limit, V3 may partial-fill. We assert
        // full consumption to keep the loan/repayment math exact.
        int256 owed   = amount0Delta > 0 ? amount0Delta : amount1Delta;
        int256 recvD  = amount0Delta < 0 ? amount0Delta : amount1Delta;
        if (owed <= 0 || recvD >= 0) revert InsufficientOutput(0, loanAmount);
        if (uint256(owed) != loanAmount) revert InsufficientOutput(uint256(owed), loanAmount);

        // Read what the opening pool actually delivered, by balance (not delta). The pool has
        // already transferred the intermediate token to this contract before invoking us.
        address intermediateToken;
        assembly { intermediateToken := shr(96, calldataload(remainingPath.offset)) }
        uint256 receivedAmount = IERC20(intermediateToken).balanceOf(address(this));

        // Run the remaining circle. Pass minAmountOut = 0 to _executeMultiDexPath; we enforce
        // the WETH floor here against the actual WETH produced (mirrors _handleSelfFlashCallback).
        bytes memory pathMem = remainingPath;
        uint256 wethProduced = _executeMultiDexPath(pathMem, receivedAmount, 0);

        // Solvency: must always be able to repay the opening pool, regardless of testMode.
        if (wethProduced < uint256(owed)) revert InsufficientOutput(wethProduced, uint256(owed));
        // Profit floor: testMode-gated so integration tests can run lossy paths end-to-end.
        if (!testMode && wethProduced < minAmountOut) revert InsufficientOutput(wethProduced, minAmountOut);

        // Repay the opening pool. Residual = wethProduced - owed stays in the contract and is
        // picked up by the entry point via the balBefore/balAfter delta on flashToken.
        _safeTransfer(flashToken, msg.sender, uint256(owed));
    }

    // =============================================================================
    // SEQUENTIAL ARBITRAGE (callbackType == 4)
    // =============================================================================

    function _unlockSequential(bytes calldata data) private {
        CircleSpec[] memory circles = abi.decode(data, (CircleSpec[]));

        // 1. Group by flashToken: find max per token, collect unique token list.
        //    N is expected to be small (<=5 typical), so O(N^2) is fine.
        address[] memory uniqueTokens = new address[](circles.length);
        uint256[] memory maxPerToken = new uint256[](circles.length);
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < circles.length; i++) {
            address tok = circles[i].flashToken;
            bool found = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (uniqueTokens[j] == tok) {
                    if (circles[i].flashAmount > maxPerToken[j]) maxPerToken[j] = circles[i].flashAmount;
                    found = true;
                    break;
                }
            }
            if (!found) {
                uniqueTokens[uniqueCount] = tok;
                maxPerToken[uniqueCount] = circles[i].flashAmount;
                uniqueCount++;
            }
        }

        // 2. Take max per unique token.
        for (uint256 j = 0; j < uniqueCount; j++) {
            poolManager.take(Currency.wrap(uniqueTokens[j]), address(this), maxPerToken[j]);
        }

        // 3. Execute each circle's path in order. Each path consumes flashAmount of its
        //    flashToken and returns flashAmount + profit. Contract's running balance in
        //    each token equals max(loaned) + cumulative_profits_in_that_token.
        for (uint256 i = 0; i < circles.length; i++) {
            uint256 amountOut = _executeMultiDexPath(
                circles[i].path,
                circles[i].flashAmount,
                circles[i].minAmountOut
            );
            if (!testMode) {
                if (amountOut < circles[i].flashAmount) revert InsufficientOutput(amountOut, circles[i].flashAmount);
                if (amountOut < circles[i].minAmountOut) revert InsufficientOutput(amountOut, circles[i].minAmountOut);
            }
        }

        // 4. Settle per unique token.
        for (uint256 j = 0; j < uniqueCount; j++) {
            Currency cur = Currency.wrap(uniqueTokens[j]);
            poolManager.sync(cur);
            _safeTransfer(uniqueTokens[j], address(poolManager), maxPerToken[j]);
            poolManager.settle();
        }

        // 5. Distribute profit: convert non-WETH profits to WETH, tip from WETH portion.
        _distributeSequentialProfit(uniqueTokens, uniqueCount);
    }

    /// @notice Distributes per-token profits after all flash loans have been settled.
    ///         For each unique flash token, reads the contract's current balance and
    ///         splits it between the builder (as ETH via WETH unwrap) and the owner.
    ///
    ///         INVARIANT: The contract must hold ZERO balance of every circle's
    ///         flashToken before the sequential bundle begins. Otherwise any
    ///         pre-existing residual is treated as profit and partially paid to the
    ///         builder via the tip. The owner should call withdrawToken() on any
    ///         flash-token residuals before enabling tipBps > 0 on sequential arbs.
    ///
    ///         The tipBps == 0 branch is safe against residuals (all tokens go to
    ///         the owner), but tipBps > 0 requires the invariant above.
    function _distributeSequentialProfit(address[] memory uniqueTokens, uint256 uniqueCount) private {
        uint256 tipBps;
        assembly { tipBps := tload(TSLOT_TIP_BPS) }
        if (tipBps == 0) {
            // No tip — transfer all profits directly to owner.
            for (uint256 j = 0; j < uniqueCount; j++) {
                uint256 bal = IERC20(uniqueTokens[j]).balanceOf(address(this));
                if (bal > 0) _safeTransfer(uniqueTokens[j], owner, bal);
            }
            return;
        }

        // Sum profit in WETH terms. Convert non-WETH profits via wethPools[].
        uint256 totalWeth = 0;
        for (uint256 j = 0; j < uniqueCount; j++) {
            address tok = uniqueTokens[j];
            uint256 bal = IERC20(tok).balanceOf(address(this));
            if (bal == 0) continue;
            if (tok == WETH) {
                totalWeth += bal;
            } else {
                address wethPool = wethPools[tok];
                if (wethPool == address(0)) {
                    // No conversion path — pay owner this token unchanged.
                    // Edge case: if ALL circles use non-WETH tokens with no wethPools
                    // entry, totalWeth stays 0 and the builder gets NO tip — inclusion
                    // is not incentivized. Caller should avoid this configuration.
                    _safeTransfer(tok, owner, bal);
                    continue;
                }
                try this._trySwapV3ToWeth(wethPool, tok, bal) returns (uint256 wethGained) {
                    totalWeth += wethGained;
                } catch {
                    // Swap failed — pool may be stale, drained, or manipulated.
                    // Pay owner in the token directly rather than bricking the whole bundle.
                    _safeTransfer(tok, owner, bal);
                }
            }
        }

        uint256 tipWeth = (totalWeth * tipBps) / BASIS_POINTS;
        uint256 ownerWeth = totalWeth - tipWeth;

        // Unwrap tipWeth WETH -> ETH via raw assembly (withdraw(uint256) selector 0x2e1a7d4d).
        if (tipWeth > 0) {
            assembly {
                let m := mload(0x40)
                mstore(m, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                mstore(add(m, 0x04), tipWeth)
                if iszero(call(gas(), WETH, 0, m, 0x24, 0, 0)) { revert(0, 0) }
            }
            (bool ok, ) = block.coinbase.call{value: tipWeth}("");
            if (!ok) revert CoinbasePaymentFailed(block.coinbase, tipWeth);
        }

        if (ownerWeth > 0) _safeTransfer(WETH, owner, ownerWeth);
    }

    /// @notice External wrapper for _swapV3Direct that allows try/catch in the tip
    ///         conversion path. Restricted to self-call so external callers can't
    ///         invoke it directly.
    function _trySwapV3ToWeth(address pool, address tokenIn, uint256 amountIn)
        external returns (uint256 wethGained)
    {
        if (msg.sender != address(this)) revert UnauthorizedAccess(msg.sender);
        return _swapV3Direct(pool, tokenIn, WETH, amountIn, 0);
    }

    // =============================================================================
    // SHARED SETTLE + PROFIT DISTRIBUTION
    // =============================================================================

    function _settleAndDistribute(
        address flashToken,
        uint256 flashAmount,
        uint256 amountOut,
        uint256 minAmountOut,
        uint256 tipBps
    ) private {
        if (!testMode) {
            if (amountOut < flashAmount) revert InsufficientOutput(amountOut, flashAmount);
            if (amountOut < minAmountOut) revert InsufficientOutput(amountOut, minAmountOut);
        }

        // Settle debt to V4 — use contract balance to cover any deficit in testMode
        Currency currency = Currency.wrap(flashToken);
        poolManager.sync(currency);
        _safeTransfer(flashToken, address(poolManager), flashAmount);
        poolManager.settle();

        // Distribute profit only when there is one
        if (amountOut > flashAmount) {
            _distributeProfitWeth(flashToken, amountOut - flashAmount, tipBps);
        }
    }

    /// @notice Splits `profit` (in flashToken) between builder coinbase tip and owner.
    ///         Reused by V4-flash and V3-self-flash paths.
    ///
    ///         INVARIANTS (caller's responsibility):
    ///         1. Contract holds zero pre-existing balance of flashToken; otherwise residuals
    ///            are tipped to the builder.
    ///         2. For non-WETH flashToken with tipBps > 0, wethPools[flashToken] must be set;
    ///            otherwise this function reverts inside any active V4 unlock context, taking
    ///            the whole bundle down.
    function _distributeProfitWeth(
        address flashToken,
        uint256 profit,
        uint256 tipBps
    ) private {
        if (profit == 0) return;

        // NET-PROFIT BASIS: reinterpret tipBps as bps of NET (gross - actual gas). WETH-flash only (D6).
        uint256 netBasis = profit; // default = gross (non-WETH flash, or start-gas unset -> D7 safe fallback)
        if (flashToken == WETH) {
            uint256 startGas;
            assembly { startGas := tload(TSLOT_START_GAS) }
            if (startGas != 0) {
                uint256 gasUsed = startGas - gasleft() + GAS_OVERHEAD;
                uint256 gasCostWei = gasUsed * tx.gasprice;
                if (profit <= gasCostWei) revert InsufficientProfit(profit, gasCostWei);
                netBasis = profit - gasCostWei;
            }
        }

        uint256 ownerProfit = profit;

        if (tipBps > 0) {
            uint256 tipAmount = (netBasis * tipBps) / BASIS_POINTS;
            ownerProfit = profit - tipAmount;

            uint256 ethTip;
            if (flashToken == WETH) {
                assembly {
                    let m := mload(0x40)
                    mstore(m, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                    mstore(add(m, 0x04), tipAmount)
                    if iszero(call(gas(), WETH, 0, m, 0x24, 0, 0)) { revert(0, 0) }
                }
                ethTip = tipAmount;
            } else {
                address wethPool = wethPools[flashToken];
                if (wethPool == address(0)) revert NoWethPoolConfigured(flashToken);
                uint256 wethReceived = _swapV3Direct(wethPool, flashToken, WETH, tipAmount, 0);
                assembly {
                    let m := mload(0x40)
                    mstore(m, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                    mstore(add(m, 0x04), wethReceived)
                    if iszero(call(gas(), WETH, 0, m, 0x24, 0, 0)) { revert(0, 0) }
                }
                ethTip = wethReceived;
            }

            (bool tipSuccess, ) = block.coinbase.call{value: ethTip}("");
            if (!tipSuccess) revert CoinbasePaymentFailed(block.coinbase, ethTip);
        }

        if (ownerProfit > 0) {
            _safeTransfer(flashToken, owner, ownerProfit);
        }
    }

    // =============================================================================
    // FORK EXECUTION
    // =============================================================================

    function _executeForkPoint(
        ForkPoint memory forkPoint,
        uint256 amountIn,
        uint256 /* forkIndex */
    ) private returns (uint256 totalOutput) {
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < forkPoint.branches.length; i++) {
            ForkBranch memory branch = forkPoint.branches[i];
            uint256 branchAmount;

            if (i == forkPoint.branches.length - 1) {
                branchAmount = amountIn - totalDistributed;
            } else {
                branchAmount = (amountIn * branch.proportionBps) / BASIS_POINTS;
                totalDistributed += branchAmount;
            }

            totalOutput += _executeMultiDexPath(branch.path, branchAmount, 0);
        }
    }

    // =============================================================================
    // SWAP EXECUTION
    // =============================================================================

    /// @notice Unified path executor with lazy V4 settle/take.
    ///         Consecutive V4 hops accumulate deltas without token transfers.
    ///         Settle/take only at boundaries: non-V4↔V4 transitions.
    ///         44-byte hop format: [tokenIn 20B][dexType 1B][fee 3B][pool 20B][tokenOut 20B]
    ///         Minimum path length: 20 + 44 = 64 bytes (one hop)
    function _executeMultiDexPath(
        bytes memory path,
        uint256 amountIn,
        uint256 minAmountOut
    ) private returns (uint256 amountOut) {
        if (path.length < 64) revert PathTooShort(path.length);
        if ((path.length - 20) % HOP_SIZE != 0) revert PathTooShort(path.length);

        uint256 currentAmount = amountIn;
        uint256 offset = 0;
        bool inV4Mode = false;

        while (offset + HOP_SIZE <= path.length - 20) {
            address tokenIn;
            uint8 dexType;
            address pool;
            address tokenOut;
            uint8 curveI;
            uint8 curveJ;
            assembly {
                let base := add(add(path, 32), offset)
                tokenIn  := shr(96, mload(base))
                dexType  := byte(0, mload(add(base, 20)))
                curveI   := byte(0, mload(add(base, 21)))
                curveJ   := byte(0, mload(add(base, 22)))
                // byte 23: unused fee byte for non-V4; used as fee byte 2 for V4
                pool     := shr(96, mload(add(base, 24)))
                tokenOut := shr(96, mload(add(base, 44)))
            }

            if (dexType == DEX_V4) {
                // Parse V4-specific fields from hop
                // fee: 3 bytes at positions 21-23 (same as curveI/curveJ/byte23)
                // tickSpacing: int16 at positions 24-25 (first 2 bytes of pool field)
                // hooks: hardcoded to address(0) — all tracked V4 pools are hookless.
                //        The remaining 18 bytes of the pool field (26-43) are ignored.
                //        NOTE: if hooks support is needed later, expand HOP_SIZE to 46
                //        to avoid reading into the next hop's tokenOut field.
                uint24 v4Fee;
                int24 v4TickSpacing;
                assembly {
                    let base := add(add(path, 32), offset)
                    v4Fee := or(or(shl(16, byte(0, mload(add(base, 21)))), shl(8, byte(0, mload(add(base, 22))))), byte(0, mload(add(base, 23))))
                    v4TickSpacing := signextend(1, shr(240, mload(add(base, 24))))
                }

                // Transition: entering V4 mode — settle input token into PoolManager
                if (!inV4Mode) {
                    _v4Settle(tokenIn, currentAmount);
                    inV4Mode = true;
                }

                // Execute V4 swap (deltas accumulate, no token movement)
                currentAmount = _swapV4Direct(tokenIn, tokenOut, currentAmount, v4Fee, v4TickSpacing);
            } else {
                // Transition: leaving V4 mode — take output from previous V4 hop
                if (inV4Mode) {
                    _v4Take(tokenIn, currentAmount);
                    inV4Mode = false;
                }

                // Only enforce minAmountOut on last hop
                uint256 hopMinOut = (offset + HOP_SIZE + HOP_SIZE >= path.length - 20 + HOP_SIZE) ? minAmountOut : 0;

                // Execute non-V4 swap normally
                if (dexType == DEX_V3) {
                    currentAmount = _swapV3Direct(pool, tokenIn, tokenOut, currentAmount, hopMinOut);
                } else if (dexType == DEX_CURVE) {
                    // fee[0]=i, fee[1]=j: Curve coin indices for exchange(i, j, ...)
                    currentAmount = _swapCurveDirect(pool, tokenIn, tokenOut, currentAmount, curveI, curveJ);
                } else if (dexType == DEX_PSM) {
                    // fee[0] byte contains the PSM operation type (curveI reused)
                    currentAmount = _swapPsmDirect(pool, tokenIn, tokenOut, currentAmount, curveI);
                } else if (dexType == DEX_CURVE_UNDERLYING) {
                    currentAmount = _swapCurveUnderlying(pool, tokenIn, tokenOut, currentAmount, curveI, curveJ);
                } else if (dexType == DEX_CURVE_CRYPTO) {
                    currentAmount = _swapCurveCrypto(pool, tokenIn, tokenOut, currentAmount, curveI, curveJ);
                } else {
                    // DEX_V2 and DEX_SUSHI both use V2-style pairs (identical swap interface)
                    currentAmount = _swapV2Direct(pool, tokenIn, tokenOut, currentAmount, hopMinOut);
                }
            }

            offset += HOP_SIZE;
        }

        // If path ended in V4 mode, take the final output
        if (inV4Mode) {
            // Extract final tokenOut from last hop
            address finalToken;
            assembly {
                finalToken := shr(96, mload(add(add(path, 32), sub(mload(path), 20))))
            }
            _v4Take(finalToken, currentAmount);
        }

        return currentAmount;
    }

    /// @notice Execute V3 swap via direct pool.swap() call.
    ///         The pool calls back uniswapV3SwapCallback to collect payment.
    /// @dev   C1 fix: stash the expected pool + tokenIn in TSLOTs around the swap so the
    ///        legacy `0x00` callback branch can authenticate both axes. Without this, a
    ///        malicious in-path pool could re-enter uniswapV3SwapCallback during another
    ///        active arb (reentrancy guard still ON) with `data[0] = 0x00` and a forged
    ///        `tokenIn`, turning the legacy branch into an attacker-controlled `_safeTransfer`
    ///        primitive while the arb is in flight.
    function _swapV3Direct(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 /* minAmountOut */
    ) private returns (uint256 amountOut) {
        // zeroForOne = (tokenIn < tokenOut) — matches Uniswap V3 token ordering
        bool zeroForOne = tokenIn < tokenOut;

        // sqrtPriceLimitX96: use boundary values to allow any price movement
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? uint160(4295128740)            // MIN_SQRT_RATIO + 1
            : uint160(1461446703485210103287273052203988822378723970341); // MAX_SQRT_RATIO - 1

        assembly {
            tstore(TSLOT_NESTED_V3_POOL,     pool)
            tstore(TSLOT_NESTED_V3_TOKEN_IN, tokenIn)
        }
        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            address(this),          // recipient
            zeroForOne,
            int256(amountIn),       // positive = exact input
            sqrtPriceLimitX96,
            // Magic-byte 0x00 = legacy nested-V3 callback (pay tokenIn from balance)
            // Self-flash entry encodes 0x01 explicitly via _runV3SelfFlashSwap.
            // Opening self-flash entry encodes 0x02 explicitly in its entry point.
            abi.encodePacked(bytes1(0x00), tokenIn)
        );
        assembly {
            tstore(TSLOT_NESTED_V3_POOL,     0)
            tstore(TSLOT_NESTED_V3_TOKEN_IN, 0)
        }

        // Output is the negative delta (tokens received by this contract)
        amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);
    }

    /// @dev Called by V3 pools during swap. Strict 3-way dispatch by data[0]:
    ///        0x01 → closing self-flash path: msg.sender authenticated against
    ///               TSLOT_CLOSING_POOL inside _handleSelfFlashCallback.
    ///        0x02 → opening self-flash path: msg.sender authenticated against
    ///               TSLOT_OPENING_POOL inside _handleOpeningSelfFlashCallback.
    ///        0x00 → legacy nested-V3 path: pay msg.sender the owed `tokenIn` from balance.
    ///               C1 fix: authenticate msg.sender == stashed pool AND tokenIn == stashed
    ///               tokenIn (both set by _swapV3Direct around the swap call). Without this,
    ///               a malicious in-path pool could re-enter during another arb with a
    ///               forged 0x00 payload and turn the legacy branch into an attacker-controlled
    ///               `_safeTransfer` primitive.
    ///       Any other discriminator reverts with InvalidCallbackType — the legacy branch is
    ///       NO LONGER the fall-through default (C5 cleanup).
    ///      Security: reentrancy guard at slot 0 prevents malicious pool callbacks from
    ///      re-entering when the contract is idle.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        assembly {
            if iszero(tload(0)) {
                mstore(0x00, 0xc5f2be51) // ReentrancyDetected()
                revert(0x1c, 0x04)
            }
        }
        if (data.length < 21) revert PathTooShort(data.length);

        if (data[0] == 0x01) {
            _handleSelfFlashCallback(amount0Delta, amount1Delta, data);
        } else if (data[0] == 0x02) {
            _handleOpeningSelfFlashCallback(amount0Delta, amount1Delta, data);
        } else if (data[0] == 0x00) {
            // C1: authenticate against the stash set by _swapV3Direct on BOTH axes.
            address expectedPool;
            address expectedTokenIn;
            assembly {
                expectedPool    := tload(TSLOT_NESTED_V3_POOL)
                expectedTokenIn := tload(TSLOT_NESTED_V3_TOKEN_IN)
            }
            if (msg.sender != expectedPool) revert InvalidCallback(msg.sender, expectedPool);
            address tokenIn;
            assembly { tokenIn := shr(96, calldataload(add(data.offset, 1))) }
            if (tokenIn != expectedTokenIn) revert InvalidCallback(tokenIn, expectedTokenIn);

            // CONSUME-ONCE: clear the auth slots before paying. Legitimate V3 pools call
            // the callback exactly once per swap(), so this is a no-op for honest flows. A
            // malicious pool re-entering with a second forged callback during the same swap()
            // hits the cleared slots and reverts (expectedPool == 0 != msg.sender).
            assembly {
                tstore(TSLOT_NESTED_V3_POOL, 0)
                tstore(TSLOT_NESTED_V3_TOKEN_IN, 0)
            }

            int256 owed = amount0Delta > 0 ? amount0Delta : amount1Delta;
            require(owed > 0);
            _safeTransfer(tokenIn, msg.sender, uint256(owed));
        } else {
            revert InvalidCallbackType(uint8(data[0]));
        }
    }

    /// @dev PancakeSwap V3 pools call this name instead of uniswapV3SwapCallback.
    ///      Same 3-way dispatch and same C1 / C5 treatment as the Uniswap variant.
    ///      Required because PCS-V3 pools are valid opening pools, valid closing pools,
    ///      and valid mid-hops — all three branches must work here too.
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        assembly {
            if iszero(tload(0)) {
                mstore(0x00, 0xc5f2be51) // ReentrancyDetected()
                revert(0x1c, 0x04)
            }
        }
        if (data.length < 21) revert PathTooShort(data.length);

        if (data[0] == 0x01) {
            _handleSelfFlashCallback(amount0Delta, amount1Delta, data);
        } else if (data[0] == 0x02) {
            _handleOpeningSelfFlashCallback(amount0Delta, amount1Delta, data);
        } else if (data[0] == 0x00) {
            address expectedPool;
            address expectedTokenIn;
            assembly {
                expectedPool    := tload(TSLOT_NESTED_V3_POOL)
                expectedTokenIn := tload(TSLOT_NESTED_V3_TOKEN_IN)
            }
            if (msg.sender != expectedPool) revert InvalidCallback(msg.sender, expectedPool);
            address tokenIn;
            assembly { tokenIn := shr(96, calldataload(add(data.offset, 1))) }
            if (tokenIn != expectedTokenIn) revert InvalidCallback(tokenIn, expectedTokenIn);

            // CONSUME-ONCE: clear the auth slots before paying. Legitimate V3 pools call
            // the callback exactly once per swap(), so this is a no-op for honest flows. A
            // malicious pool re-entering with a second forged callback during the same swap()
            // hits the cleared slots and reverts (expectedPool == 0 != msg.sender).
            assembly {
                tstore(TSLOT_NESTED_V3_POOL, 0)
                tstore(TSLOT_NESTED_V3_TOKEN_IN, 0)
            }

            int256 owed = amount0Delta > 0 ? amount0Delta : amount1Delta;
            require(owed > 0);
            _safeTransfer(tokenIn, msg.sender, uint256(owed));
        } else {
            revert InvalidCallbackType(uint8(data[0]));
        }
    }

    // =============================================================================
    // UNISWAP V2 / SUSHI SWAP CALLBACK
    // =============================================================================

    /// @notice V2/Sushi flash-swap callback. Called by the pair when it initiates a
    ///         flash swap (non-empty `data`). Dispatches on data[0]:
    ///           0x01 → closing self-flash (cbType 8): authenticate + run intermediate path
    ///                  + repay the pair. Set up by `executeFlashLoanArbitrageV2SelfFlash`.
    ///           0x02 → opening self-flash (cbType 10): authenticate + run remainingPath from
    ///                  intermediate token back to flashToken + repay the pair.
    ///                  Set up by `executeFlashLoanArbitrageV2OpeningSelfFlash`.
    ///         Any other discriminator reverts with InvalidCallbackType (C5 pattern).
    ///
    ///         Security: mirrors the reentrancy guard and sender-auth pattern of
    ///         `uniswapV3SwapCallback`/`pancakeV3SwapCallback`. The guard uses TSLOT 0 (same
    ///         slot as nonReentrant modifier) so an idle-contract call reverts immediately.
    ///         TSLOT_CLOSING_POOL is consumed once and cleared inside the handler to prevent
    ///         a malicious pair from calling the callback a second time.
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        // Reject any call that arrives outside an active entry-point execution.
        // TSLOT 0 is set to 1 by the nonReentrant modifier for the duration of every
        // entry-point call and cleared on return — identical guard as the V3 callbacks.
        assembly {
            if iszero(tload(0)) {
                mstore(0x00, 0xc5f2be51) // ReentrancyDetected()
                revert(0x1c, 0x04)
            }
        }
        // The V2 pair passes the original msg.sender (i.e. us) as `sender`.
        if (sender != address(this)) revert InvalidCallback(sender, address(this));
        if (data.length < 1) revert PathTooShort(data.length);

        if (data[0] == 0x01) {
            _handleV2SelfFlashCallback(amount0, amount1, data);
        } else if (data[0] == 0x02) {
            _handleV2OpeningSelfFlashCallback(amount0, amount1, data);
        } else {
            revert InvalidCallbackType(uint8(data[0]));
        }
    }

    /// @notice Execute V2/Sushi swap via direct pair.swap() call.
    ///         Transfer tokens to pair first, then call swap (standard V2 pattern).
    function _swapV2Direct(
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 /* minAmountOut */
    ) private returns (uint256 amountOut) {
        // Get reserves to calculate output amount
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();

        // zeroForOne = (tokenIn < tokenOut) — Uniswap V2 always stores token0 < token1
        bool zeroForOne = tokenIn < tokenOut;
        (uint256 reserveIn, uint256 reserveOut) = zeroForOne
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        // Standard V2 output formula with 0.3% fee (997/1000)
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);

        // Transfer input tokens to pair first (V2 pattern: send → swap)
        _safeTransfer(tokenIn, pair, amountIn);

        // Call swap: amount0Out and amount1Out, exactly one is 0
        if (zeroForOne) {
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), "");
        } else {
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
        }
    }

    /// @notice Uniswap V2 / Sushi inverse swap: minimum input to receive exactly `amountOut`.
    ///         Rounds UP (the +1) so the pair's K-check never fails from underpayment.
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal pure returns (uint256 amountIn)
    {
        require(amountOut < reserveOut, "V2: out>=reserve");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice Execute Curve pool swap via low-level call.
    ///         Uses low-level call (NOT a typed interface) because older Curve pools do not
    ///         return a value from exchange(), making a typed interface incompatible.
    ///         curveI/curveJ are the coin indices for exchange(i, j, amount, minOut).
    ///         Supports 2-coin pools (i,j ∈ {0,1}) and 3-coin pools (i,j ∈ {0,1,2}).
    function _swapCurveDirect(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint8 curveI,
        uint8 curveJ
    ) private returns (uint256 amountOut) {
        // Lazy approve: check allowance, approve max if insufficient
        (bool successAllowance, bytes memory allowanceData) = tokenIn.staticcall(
            abi.encodeWithSelector(0xdd62ed3e, address(this), pool)
        );
        if (successAllowance && allowanceData.length >= 32) {
            uint256 currentAllowance = abi.decode(allowanceData, (uint256));
            if (currentAllowance < amountIn) {
                (bool ok,) = tokenIn.call(
                    abi.encodeWithSelector(0x095ea7b3, pool, type(uint256).max)
                );
                require(ok, "Curve approve failed");
            }
        }

        // Record balance before
        uint256 balBefore = IERC20(tokenOut).balanceOf(address(this));

        // Try exchange(int128,int128,uint256,uint256) first (classic pools, selector 0x3df02124),
        // then fall back to exchange(uint256,uint256,uint256,uint256) (factory pools, selector 0x5b41b908).
        int128 i128 = int128(uint128(curveI));
        int128 j128 = int128(uint128(curveJ));
        (bool success,) = pool.call(
            abi.encodeWithSelector(0x3df02124, i128, j128, amountIn, uint256(0))
        );
        if (!success) {
            uint256 i256 = uint256(curveI);
            uint256 j256 = uint256(curveJ);
            (success,) = pool.call(
                abi.encodeWithSelector(0x5b41b908, i256, j256, amountIn, uint256(0))
            );
            require(success, "Curve exchange failed");
        }

        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balBefore;
    }

    /// @notice Execute Curve CryptoSwap (tricrypto) swap via exchange(uint256,uint256,uint256,uint256).
    ///         CryptoSwap pools use uint256 indices only — no int128 fallback needed.
    ///         Some old CryptoSwap pools have a default fallback that silently accepts int128 calls
    ///         without doing anything, so we must use uint256 directly.
    function _swapCurveCrypto(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint8 curveI,
        uint8 curveJ
    ) private returns (uint256 amountOut) {
        // Lazy approve
        (bool successAllowance, bytes memory allowanceData) = tokenIn.staticcall(
            abi.encodeWithSelector(0xdd62ed3e, address(this), pool)
        );
        if (successAllowance && allowanceData.length >= 32) {
            uint256 currentAllowance = abi.decode(allowanceData, (uint256));
            if (currentAllowance < amountIn) {
                (bool ok,) = tokenIn.call(
                    abi.encodeWithSelector(0x095ea7b3, pool, type(uint256).max)
                );
                require(ok, "CryptoCurve approve failed");
            }
        }

        uint256 balBefore = IERC20(tokenOut).balanceOf(address(this));

        // exchange(uint256,uint256,uint256,uint256) selector: 0x5b41b908
        uint256 i256 = uint256(curveI);
        uint256 j256 = uint256(curveJ);
        (bool success,) = pool.call(
            abi.encodeWithSelector(0x5b41b908, i256, j256, amountIn, uint256(0))
        );
        require(success, "CryptoCurve exchange failed");

        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balBefore;
    }

    /// @notice Execute V4 swap via PoolManager.swap() — DOES NOT settle/take.
    ///         Deltas accumulate in the PoolManager. Caller must settle input and take output
    ///         at V4 boundary transitions (entering/leaving V4 mode).
    ///         Hop encoding: fee (3B) = V4 fee, pool field bytes 0-1 = tickSpacing (int16),
    ///         bytes 2-19 = zeros (hooks = address(0) for all tracked pools).
    function _swapV4Direct(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee,
        int24 tickSpacing
    ) private returns (uint256 amountOut) {
        // Map WETH → address(0) for V4 PoolKey. V4 native ETH pools use address(0)
        // as currency, but our path encodes WETH address for non-V4 hop compatibility.
        address mappedIn = tokenIn == WETH ? address(0) : tokenIn;
        address mappedOut = tokenOut == WETH ? address(0) : tokenOut;

        // Build PoolKey — currency0 must be < currency1 per V4 convention
        bool zeroForOne = mappedIn < mappedOut;
        Currency currency0 = Currency.wrap(zeroForOne ? mappedIn : mappedOut);
        Currency currency1 = Currency.wrap(zeroForOne ? mappedOut : mappedIn);

        BalanceDelta delta = poolManager.swap(
            PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: IHooks(address(0))
            }),
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn), // negative = exact input in V4
                sqrtPriceLimitX96: zeroForOne
                    ? uint160(4295128740)
                    : uint160(1461446703485210103287273052203988822378723970341)
            }),
            ""  // empty hookData — no hooks on tracked pools
        );

        // BalanceDelta packing: amount0 in top 128 bits, amount1 in bottom 128 bits.
        // V4 convention: delta is from the locker's perspective, so for an exact-input
        // swap the OUTPUT token's delta is positive (pool owes us). Pre-fix code negated
        // a positive value, wrapping uint128 to ~uint128.max and triggering SafeCastOverflow
        // inside poolManager.take(amount.toInt128()). See replay of block 24988184.
        int128 delta0 = int128(BalanceDelta.unwrap(delta) >> 128);
        int128 delta1 = int128(BalanceDelta.unwrap(delta));
        int128 outDelta = zeroForOne ? delta1 : delta0;
        if (outDelta < 0) revert InsufficientOutput(0, uint256(amountIn));
        amountOut = uint256(uint128(outDelta));
    }

    /// @notice Settle a token into V4 PoolManager (transfer from contract → PM, clear positive delta).
    ///         Called when entering V4 mode from non-V4, or at start of V4-only path.
    ///         Handles WETH→ETH unwrap for native ETH pools: path uses WETH address,
    ///         but V4 pool expects native ETH settlement.
    function _v4Settle(address token, uint256 amount) private {
        if (token == WETH) {
            // Native ETH pool: unwrap WETH → ETH, settle as native ETH
            assembly {
                let m := mload(0x40)
                mstore(m, 0x2e1a7d4d00000000000000000000000000000000000000000000000000000000)
                mstore(add(m, 0x04), amount)
                if iszero(call(gas(), WETH, 0, m, 0x24, 0, 0)) { revert(0, 0) }
            }
            poolManager.settle{value: amount}();
        } else {
            Currency currency = Currency.wrap(token);
            poolManager.sync(currency);
            _safeTransfer(token, address(poolManager), amount);
            poolManager.settle();
        }
    }

    /// @notice Take a token from V4 PoolManager (PM → contract, clear negative delta).
    ///         Called when exiting V4 mode to non-V4, or at end of path.
    ///         Handles ETH→WETH wrap for native ETH pools: V4 sends native ETH,
    ///         but next non-V4 hop expects WETH (ERC20).
    function _v4Take(address token, uint256 amount) private {
        if (token == WETH) {
            // Native ETH pool: take as native ETH, wrap → WETH for next hop
            poolManager.take(Currency.wrap(address(0)), address(this), amount);
            // Wrap ETH → WETH via deposit
            assembly {
                let m := mload(0x40)
                mstore(m, 0xd0e30db000000000000000000000000000000000000000000000000000000000) // deposit()
                if iszero(call(gas(), WETH, amount, m, 0x04, 0, 0)) { revert(0, 0) }
            }
        } else {
            poolManager.take(Currency.wrap(token), address(this), amount);
        }
    }

    /// @notice Execute Curve metapool exchange_underlying swap.
    ///         curveI/curveJ are the UNDERLYING coin indices:
    ///         0 = metapool token, 1 = DAI, 2 = USDC, 3 = USDT
    function _swapCurveUnderlying(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint8 curveI,
        uint8 curveJ
    ) private returns (uint256 amountOut) {
        // Lazy approve
        (bool successAllowance, bytes memory allowanceData) = tokenIn.staticcall(
            abi.encodeWithSelector(0xdd62ed3e, address(this), pool)
        );
        if (successAllowance && allowanceData.length >= 32) {
            uint256 currentAllowance = abi.decode(allowanceData, (uint256));
            if (currentAllowance < amountIn) {
                (bool ok,) = tokenIn.call(
                    abi.encodeWithSelector(0x095ea7b3, pool, type(uint256).max)
                );
                require(ok, "Curve underlying approve failed");
            }
        }

        uint256 balBefore = IERC20(tokenOut).balanceOf(address(this));

        // exchange_underlying(int128,int128,uint256,uint256) selector: 0xa6417ed6
        int128 i128 = int128(uint128(curveI));
        int128 j128 = int128(uint128(curveJ));
        (bool success,) = pool.call(
            abi.encodeWithSelector(0xa6417ed6, i128, j128, amountIn, uint256(0))
        );
        if (!success) {
            // Try exchange_underlying(uint256,uint256,uint256,uint256) selector: 0x65b2489b
            uint256 i256 = uint256(curveI);
            uint256 j256 = uint256(curveJ);
            (success,) = pool.call(
                abi.encodeWithSelector(0x65b2489b, i256, j256, amountIn, uint256(0))
            );
            require(success, "Curve exchange_underlying failed");
        }

        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balBefore;
    }

    /// @notice Execute PSM swap (MakerDAO Peg Stability Module).
    ///         psmType encodes the operation:
    ///         0 = sellGem(address,uint256) — USDC → DAI
    ///         1 = buyGem(address,uint256) — DAI → USDC
    ///         2 = daiToUsds(address,uint256) — DAI → USDS
    ///         3 = usdsToDai(address,uint256) — USDS → DAI
    function _swapPsmDirect(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint8 psmType
    ) private returns (uint256 amountOut) {
        // All PSM/DaiUsds functions pull tokens from msg.sender via transferFrom,
        // so approval always goes to the pool contract itself.
        (bool successAllowance, bytes memory allowanceData) = tokenIn.staticcall(
            abi.encodeWithSelector(0xdd62ed3e, address(this), pool)
        );
        if (successAllowance && allowanceData.length >= 32) {
            uint256 currentAllowance = abi.decode(allowanceData, (uint256));
            if (currentAllowance < amountIn) {
                (bool ok,) = tokenIn.call(
                    abi.encodeWithSelector(0x095ea7b3, pool, type(uint256).max)
                );
                require(ok, "PSM approve failed");
            }
        }

        uint256 balBefore = IERC20(tokenOut).balanceOf(address(this));

        // buyGem(address,uint256) takes gemAmt in gem (USDC) units, not DAI units.
        // Convert: if amountIn is DAI (18 dec), divide by 1e12 to get USDC (6 dec).
        uint256 callAmount = amountIn;
        if (psmType == 1) {
            // buyGem: amountIn is DAI (18 dec), gemAmt needs USDC (6 dec)
            callAmount = amountIn / 1e12;
        }

        bytes4 selector;
        if (psmType == 0) selector = 0x95991276;       // sellGem(address,uint256)
        else if (psmType == 1) selector = 0x8d7ef9bb;  // buyGem(address,uint256)
        else if (psmType == 2) selector = 0xf2c07aae;  // daiToUsds(address,uint256)
        else selector = 0x68f30150;                     // usdsToDai(address,uint256)

        (bool success,) = pool.call(
            abi.encodeWithSelector(selector, address(this), callAmount)
        );
        require(success, "PSM swap failed");

        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balBefore;
    }

    /// @dev Transfer that works with non-standard ERC20s (USDT) that don't return bool
    function _safeTransfer(address token, address to, uint256 amount) private {
        assembly {
            let m := mload(0x40)
            mstore(m, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(m, 0x24), amount)
            if iszero(call(gas(), token, 0, m, 0x44, 0x00, 0x20)) {
                revert(0, 0)
            }
            if returndatasize() {
                if iszero(mload(0)) {
                    revert(0, 0)
                }
            }
        }
    }

    // =============================================================================
    // PATH EXTRACTION HELPERS
    // =============================================================================

    function _extractLastTokenCalldata(bytes calldata path) private pure returns (address tokenAddress) {
        if (path.length < 20) revert PathTooShort(path.length);
        uint256 lastTokenOffset = path.length - 20;
        assembly {
            tokenAddress := shr(96, calldataload(add(path.offset, lastTokenOffset)))
        }
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /// @notice Enable or disable test mode (skips profitability check).
    ///         Only for use in integration tests — never enable on mainnet.
    function setTestMode(bool _testMode) external onlyOwner {
        testMode = _testMode;
    }

    /// @notice Set the WETH pool address for a given token.
    ///         Required for non-WETH flash loans to convert builder tip to ETH.
    function setWethPool(address token, address pool) external onlyOwner {
        wethPools[token] = pool;
    }

    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoTokensToWithdraw(token);
        _safeTransfer(token, owner, balance);
        emit TokensWithdrawn(token, balance, owner);
    }

    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoTokensToWithdraw(address(0));

        (bool success, ) = owner.call{value: balance}("");
        if (!success) revert TransferFailed(address(0), owner, balance);

        emit TokensWithdrawn(address(0), balance, owner);
    }

    receive() external payable {}
}

// =============================================================================
// INTERFACES
// =============================================================================

type BalanceDelta is int256;

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function take(Currency currency, address to, uint256 amount) external;
    function sync(Currency currency) external;
    function settle() external payable returns (uint256);
    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external returns (BalanceDelta swapDelta);
}

interface IHooks {}

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

type Currency is address;

interface IUniswapV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}
