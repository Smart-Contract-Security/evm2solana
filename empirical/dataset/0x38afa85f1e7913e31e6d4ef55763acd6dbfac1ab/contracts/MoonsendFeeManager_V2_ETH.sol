// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MoonsendFeeManager_V2_ETH
 *
 * V2 fee manager. Adds a per-position FeeMode chosen at launch:
 *   - SPLIT_BOTH: classic behavior — distribute WETH and token portions to
 *                 creator + platform per the existing fee-tier split.
 *   - ALL_ETH:    auto-sell the token portion via the same V4 pool inside the
 *                 same claim tx, then split the resulting ETH. Skims a 6%
 *                 service fee out of the creator's ETH share into a counter
 *                 the contract owner can withdraw.
 *
 * The swap is atomic with the fee take. If slippage isn't met, the whole tx
 * reverts and fees stay claimable — caller retries with a fresher minWethOut.
 *
 * The pool reconstruction uses the WETH-paired pool the token was launched in:
 *   currency0/currency1 = sorted(WETH, token), fee = DYNAMIC_FEE_FLAG,
 *   tickSpacing + hook stored on this contract (set once by owner during deploy).
 */

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

type Currency is address;

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

interface IPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external returns (int256 swapDelta);
    function sync(address currency) external;
    function settle() external returns (uint256);
    function take(address currency, address to, uint256 amount) external;
}

library SafeTransfer {
    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(success && (ret.length == 0 || abi.decode(ret, (bool))), "!transfer");
    }
}

contract MoonsendFeeManager_V2_ETH is ReentrancyGuard {
    // ============ Constants (Ethereum) ============
    address constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant POOL_MANAGER     = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant WETH             = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ADMIN            = 0x45C4854c699db833eeF2bAe6cFB09EA2551E97CB;
    address constant PLATFORM         = 0x4C077f7D5c39514778b615D72c64097FFec32F64;

    uint24  constant DYNAMIC_FEE_FLAG = 0x800000;
    uint16  public constant SERVICE_FEE_BPS = 600; // 6% of creator's ETH share when ALL_ETH

    // V4 action opcodes
    uint8 constant DECREASE_LIQUIDITY = 0x01;
    uint8 constant TAKE_PAIR          = 0x11;

    // V4 swap price-limit sentinels (no limit)
    uint160 constant MIN_SQRT_PRICE_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    // ============ Pool config (set once by owner before factory wire-up) ============
    address public hookAddress;
    int24   public poolTickSpacing;

    // ============ State ============
    address public factory;
    address public owner;

    enum FeeMode { SPLIT_BOTH, ALL_ETH }
    enum SellOutcome { Never, Sold, SkippedDust, Fallback }

    struct Position {
        address  token;
        address  creator;
        uint16   feePips;
        bool     registered;
        FeeMode  mode;
    }

    mapping(uint256 => Position) public positions;
    mapping(address => uint256)  public tokenToPositionId;
    uint256[] public registeredPositionIds;

    mapping(uint256 => address[]) private _creatorHistory;

    // Service-fee accounting (ALL_ETH only)
    uint256 public retainedServiceFees;
    uint256 public minSellDust = 1e15; // 0.001 token units default; tunable

    struct FeeStats {
        uint256 totalETHCollected;
        uint256 totalTokensCollected;
        uint256 totalETHDistributed;
        uint256 totalTokensDistributed;
        uint256 creatorETHReceived;
        uint256 creatorTokensReceived;
        uint256 platformETHReceived;
        uint256 platformTokensReceived;
        uint256 serviceFeeRetained;
        uint256 totalTokensSold;     // ALL_ETH only: cumulative tokens that went through auto-sell
        uint256 totalWethFromSales;  // ALL_ETH only: cumulative WETH received from those auto-sells
        // ---- packed slot: lastCollected (6B) + lastDistributed (6B) + lastSellOutcome (1B) ----
        uint48  lastCollected;       // unix timestamp; uint48 valid until year ~8_900_000
        uint48  lastDistributed;
        uint8   lastSellOutcome;     // Most recent ALL_ETH claim outcome (see SellOutcome enum)
    }

    mapping(uint256 => FeeStats) public positionFeeStats;
    FeeStats public globalFeeStats;

    // ============ Events ============
    event Registered(uint256 indexed positionId, address indexed token, address creator, FeeMode mode);
    event FeeModeChanged(uint256 indexed positionId, FeeMode oldMode, FeeMode newMode);
    event FeesCollected(uint256 indexed positionId, uint256 ethAmount, uint256 tokenAmount, FeeMode mode);
    event AutoSold(uint256 indexed positionId, uint256 tokenIn, uint256 wethOut);
    event AutoSellFailed(uint256 indexed positionId, uint256 tokenAmount, bytes reason);
    event AutoSellSkippedDust(uint256 indexed positionId, uint256 tokenBalance, uint256 dustThreshold);
    event ETHDistributed(address indexed creator, uint256 creatorAmount, uint256 platformAmount);
    event TokenDistributed(address indexed token, address indexed creator, uint256 creatorAmount, uint256 platformAmount);
    event ServiceFeeAccrued(uint256 indexed positionId, uint256 amount);
    event ServiceFeesWithdrawn(address indexed to, uint256 amount);
    event CreatorChanged(uint256 indexed positionId, address indexed oldCreator, address indexed newCreator);
    event PositionTransferred(uint256 indexed positionId, address indexed to);
    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event PoolConfigSet(address hook, int24 tickSpacing);
    event MinSellDustSet(uint256 oldValue, uint256 newValue);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event EmergencyETHWithdrawn(address indexed to, uint256 amount);
    event EmergencyTokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    error ClaimableFeesResult(uint256 ethAmount, uint256 tokenAmount, uint8 mode);

    // ============ Modifiers ============
    modifier onlyOwner()   { require(msg.sender == owner,   "Not owner");   _; }
    modifier onlyFactory() { require(msg.sender == factory, "Not factory"); _; }
    modifier onlyAdmin()   { require(msg.sender == ADMIN,   "Not admin");   _; }
    modifier onlyAdminOrCreator(uint256 positionId) {
        require(msg.sender == ADMIN || msg.sender == positions[positionId].creator, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ============ Pool config (owner) ============

    /// @dev Single-shot: callable once before factory wires positions in. After that
    ///      hook + tickSpacing are immutable so the auto-sell PoolKey stays consistent
    ///      with what the factory used at registration.
    function setPoolConfig(address _hook, int24 _tickSpacing) external onlyOwner {
        require(hookAddress == address(0), "config locked");
        require(_hook != address(0) && _tickSpacing != 0, "bad config");
        hookAddress = _hook;
        poolTickSpacing = _tickSpacing;
        emit PoolConfigSet(_hook, _tickSpacing);
    }

    function setMinSellDust(uint256 newValue) external onlyOwner {
        uint256 old = minSellDust;
        minSellDust = newValue;
        emit MinSellDustSet(old, newValue);
    }

    // ============ Registration (onlyFactory) ============

    function registerTokenInfo(
        uint256 positionId,
        address token,
        address creator,
        address,             // legacy pool param, ignored
        bool,                // legacy autoLock param, ignored
        uint16  poolFeePips,
        uint8   feeMode      // 0 = SPLIT_BOTH, 1 = ALL_ETH
    ) external onlyFactory {
        require(!positions[positionId].registered, "Already registered");
        require(token != address(0),   "Invalid token");
        require(creator != address(0), "Invalid creator");
        require(feeMode <= uint8(FeeMode.ALL_ETH), "Bad mode");
        require(hookAddress != address(0), "Pool config not set");

        FeeMode mode = FeeMode(feeMode);
        positions[positionId] = Position({
            token:      token,
            creator:    creator,
            feePips:    poolFeePips,
            registered: true,
            mode:       mode
        });
        tokenToPositionId[token] = positionId;
        registeredPositionIds.push(positionId);
        _creatorHistory[positionId].push(creator);

        emit Registered(positionId, token, creator, mode);
    }

    // ============ Fee Collection ============

    /// @notice Permissionless: anyone can trigger a claim. Fees are always
    ///         distributed to pos.creator + PLATFORM per the fee-tier split,
    ///         regardless of msg.sender. The caller only pays gas.
    /// @param positionId The V4 NFT id.
    /// @param minWethOut For ALL_ETH positions: minimum WETH the auto-sell of token fees must yield.
    ///                   Required > 0 for ALL_ETH if tokenAmount >= minSellDust. Ignored for SPLIT_BOTH.
    function collectFees(uint256 positionId, uint128 minWethOut)
        external
        nonReentrant
    {
        Position memory pos = positions[positionId];
        require(pos.registered, "Not registered");
        _collectAndDistribute(positionId, pos, minWethOut);
    }

    /// @notice Permissionless: anyone can trigger a claim by token address.
    function collectFeesForToken(address token, uint128 minWethOut) external nonReentrant {
        uint256 positionId = tokenToPositionId[token];
        Position memory pos = positions[positionId];
        require(pos.registered, "Token not registered");
        _collectAndDistribute(positionId, pos, minWethOut);
    }

    /// @notice Permissionless: anyone can batch-claim. Caller pays gas for all.
    function batchCollectFees(uint256[] calldata positionIds, uint128[] calldata minWethOuts)
        external
        nonReentrant
    {
        require(positionIds.length == minWethOuts.length, "Len mismatch");
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 posId = positionIds[i];
            Position memory pos = positions[posId];
            if (!pos.registered || pos.creator == address(0)) continue;
            // Per-entry try/catch so one bad slippage doesn't kill the batch
            try this._collectExternal(posId, pos, minWethOuts[i]) {} catch {}
        }
    }

    /// @dev External shim so the batch loop can try/catch a single collect.
    function _collectExternal(uint256 positionId, Position calldata pos, uint128 minWethOut) external {
        require(msg.sender == address(this), "Internal only");
        _collectAndDistribute(positionId, pos, minWethOut);
    }

    // ============ Internal Collect ============

    function _collectAndDistribute(uint256 positionId, Position memory pos, uint128 minWethOut) internal {
        // 1. Pull fees from V4 (TAKE_PAIR -> WETH + token to this contract)
        (uint256 wethCollected, uint256 tokenCollected) = _takeFromV4(positionId, pos.token);

        uint256 wethTotal  = wethCollected;
        uint256 tokenFinal = tokenCollected;
        bool    skipPremium = false;

        if (pos.mode == FeeMode.ALL_ETH) {
            tokenFinal = 0;

            // Sell the FULL token balance held for this token. tokenCollected is just
            // this call's delta; balance also includes any prior dust we couldn't sell.
            uint256 fullBal = IERC20(pos.token).balanceOf(address(this));
            if (fullBal >= minSellDust) {
                require(minWethOut > 0, "ALL_ETH: minWethOut=0");
                (bool ok, uint256 swapped, bytes memory reason) = _autoSellToken(pos.token, fullBal, minWethOut);
                if (ok) {
                    wethTotal += swapped;
                    positionFeeStats[positionId].totalTokensSold     += fullBal;
                    positionFeeStats[positionId].totalWethFromSales  += swapped;
                    positionFeeStats[positionId].lastSellOutcome      = uint8(SellOutcome.Sold);
                    globalFeeStats.totalTokensSold    += fullBal;
                    globalFeeStats.totalWethFromSales += swapped;
                    emit AutoSold(positionId, fullBal, swapped);
                } else {
                    // Pool unhealthy / hook reverted / slippage too tight: fall back to
                    // SPLIT_BOTH-style distribution for THIS claim. No premium charged
                    // (no service rendered). Tokens leave the contract — no rollover.
                    tokenFinal  = fullBal;
                    skipPremium = true;
                    positionFeeStats[positionId].lastSellOutcome = uint8(SellOutcome.Fallback);
                    emit AutoSellFailed(positionId, fullBal, reason);
                }
            } else if (fullBal > 0) {
                // Below dust floor: skip the swap, roll over to next claim. WETH
                // side still distributes normally (no premium since no sell happened).
                skipPremium = true;
                positionFeeStats[positionId].lastSellOutcome = uint8(SellOutcome.SkippedDust);
                emit AutoSellSkippedDust(positionId, fullBal, minSellDust);
            }

            // Stats: track gross token fee that came in this claim, even if auto-sold
            if (tokenCollected > 0) {
                positionFeeStats[positionId].totalTokensCollected += tokenCollected;
                globalFeeStats.totalTokensCollected += tokenCollected;
            }
        }

        // 3. Unwrap to native ETH
        if (wethTotal > 0) IWETH(WETH).withdraw(wethTotal);

        // 4. Distribute
        if (wethTotal > 0 || tokenFinal > 0) {
            _distribute(positionId, pos, wethTotal, tokenFinal, skipPremium);
        }
    }

    function _takeFromV4(uint256 positionId, address token)
        internal
        returns (uint256 wethAmt, uint256 tokenAmt)
    {
        uint256 wethBefore  = IERC20(WETH).balanceOf(address(this));
        uint256 tokenBefore = IERC20(token).balanceOf(address(this));

        IPositionManager(POSITION_MANAGER).modifyLiquidities(
            _buildCollectPayload(positionId, token), block.timestamp
        );

        wethAmt  = IERC20(WETH).balanceOf(address(this)) - wethBefore;
        tokenAmt = IERC20(token).balanceOf(address(this)) - tokenBefore;
    }

    function _buildCollectPayload(uint256 positionId, address token) internal view returns (bytes memory) {
        bytes memory actions = abi.encodePacked(DECREASE_LIQUIDITY, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, uint256(0), uint128(0), uint128(0), bytes(""));

        (address c0, address c1) = WETH < token ? (WETH, token) : (token, WETH);
        params[1] = abi.encode(c0, c1, address(this));

        return abi.encode(actions, params);
    }

    // ============ Auto-sell (V4 PoolManager.unlock) ============

    /// @dev Returns (ok, wethOut, reason). On any swap revert (slippage, no liquidity,
    ///      hook revert) returns (false, 0, raw revert bytes) so the caller can fall
    ///      back instead of bubbling. `reason` is empty when ok is true.
    function _autoSellToken(address token, uint256 tokenAmt, uint128 minWethOut)
        internal
        returns (bool ok, uint256 wethOut, bytes memory reason)
    {
        try IPoolManager(POOL_MANAGER).unlock(abi.encode(token, tokenAmt, minWethOut))
            returns (bytes memory ret)
        {
            wethOut = abi.decode(ret, (uint256));
            ok = true;
        } catch (bytes memory r) {
            ok = false;
            wethOut = 0;
            reason = r;
        }
    }

    /// @notice V4 PoolManager calls this back during unlock(). Performs the token→WETH swap.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == POOL_MANAGER, "!pm");

        (address token, uint256 tokenAmt, uint128 minWethOut) =
            abi.decode(data, (address, uint256, uint128));

        bool wethIsToken0 = WETH < token;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(wethIsToken0 ? WETH : token),
            currency1: Currency.wrap(wethIsToken0 ? token : WETH),
            fee: DYNAMIC_FEE_FLAG,
            tickSpacing: poolTickSpacing,
            hooks: hookAddress
        });

        // We're selling token. zeroForOne = true if token is currency0.
        bool zeroForOne = !wethIsToken0;

        IPoolManager.SwapParams memory sp = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(tokenAmt), // exact-input
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_LIMIT : MAX_SQRT_PRICE_LIMIT
        });

        int256 swapDelta = IPoolManager(POOL_MANAGER).swap(key, sp, bytes(""));
        int128 delta0 = int128(swapDelta >> 128);
        int128 delta1 = int128(swapDelta);

        // Settle token side (we owe pool)
        int256 owedSigned = zeroForOne ? int256(delta0) : int256(delta1);
        require(owedSigned < 0, "delta sign");
        uint256 tokenOwed = uint256(-owedSigned);
        IPoolManager(POOL_MANAGER).sync(token);
        SafeTransfer.safeTransfer(token, POOL_MANAGER, tokenOwed);
        IPoolManager(POOL_MANAGER).settle();

        // Take WETH owed to us
        int256 outSigned = zeroForOne ? int256(delta1) : int256(delta0);
        require(outSigned > 0, "no out");
        uint256 wethOut = uint256(outSigned);
        require(wethOut >= minWethOut, "Slippage");
        IPoolManager(POOL_MANAGER).take(WETH, address(this), wethOut);

        return abi.encode(wethOut);
    }

    // ============ Distribute ============

    function _distribute(
        uint256 positionId,
        Position memory pos,
        uint256 ethAmount,
        uint256 tokenAmount,
        bool    skipPremium
    ) internal {
        if (ethAmount > 0) {
            (uint256 platformETH, uint256 creatorETH) = _calcSplit(ethAmount, positionId);

            uint256 svcFee = 0;
            if (pos.mode == FeeMode.ALL_ETH && !skipPremium && creatorETH > 0) {
                svcFee = (creatorETH * SERVICE_FEE_BPS) / 10000;
                creatorETH -= svcFee;
                retainedServiceFees += svcFee;
                positionFeeStats[positionId].serviceFeeRetained += svcFee;
                globalFeeStats.serviceFeeRetained += svcFee;
                emit ServiceFeeAccrued(positionId, svcFee);
            }

            if (creatorETH  > 0) _sendETH(pos.creator, creatorETH);
            if (platformETH > 0) _sendETH(PLATFORM,    platformETH);

            positionFeeStats[positionId].totalETHCollected   += ethAmount;
            positionFeeStats[positionId].totalETHDistributed += ethAmount - svcFee;
            positionFeeStats[positionId].creatorETHReceived  += creatorETH;
            positionFeeStats[positionId].platformETHReceived += platformETH;
            globalFeeStats.totalETHCollected   += ethAmount;
            globalFeeStats.totalETHDistributed += ethAmount - svcFee;
            globalFeeStats.creatorETHReceived  += creatorETH;
            globalFeeStats.platformETHReceived += platformETH;

            emit ETHDistributed(pos.creator, creatorETH, platformETH);
        }

        if (tokenAmount > 0) {
            // ALL_ETH never reaches here (tokenFinal forced to 0 after sell)
            (uint256 platformTokens, uint256 creatorTokens) = _calcSplit(tokenAmount, positionId);

            if (creatorTokens  > 0) _safeTransfer(pos.token, pos.creator, creatorTokens);
            if (platformTokens > 0) _safeTransfer(pos.token, PLATFORM,    platformTokens);

            positionFeeStats[positionId].totalTokensCollected   += tokenAmount;
            positionFeeStats[positionId].totalTokensDistributed += tokenAmount;
            positionFeeStats[positionId].creatorTokensReceived  += creatorTokens;
            positionFeeStats[positionId].platformTokensReceived += platformTokens;
            globalFeeStats.totalTokensCollected   += tokenAmount;
            globalFeeStats.totalTokensDistributed += tokenAmount;
            globalFeeStats.creatorTokensReceived  += creatorTokens;
            globalFeeStats.platformTokensReceived += platformTokens;

            emit TokenDistributed(pos.token, pos.creator, creatorTokens, platformTokens);
        }

        positionFeeStats[positionId].lastCollected   = uint48(block.timestamp);
        positionFeeStats[positionId].lastDistributed = uint48(block.timestamp);

        emit FeesCollected(positionId, ethAmount, tokenAmount, pos.mode);
    }

    function _getPlatformPips(uint16 totalBps) internal pure returns (uint16) {
        if (totalBps == 13300) return 3300;
        if (totalBps == 20000) return 5000;
        if (totalBps == 27500) return 7500;
        if (totalBps == 34000) return 9000;
        if (totalBps == 42000) return 12000;
        revert("Unknown fee tier");
    }

    function _calcSplit(uint256 amount, uint256 positionId)
        internal view
        returns (uint256 platformAmount, uint256 creatorAmount)
    {
        uint16 totalBps = positions[positionId].feePips;
        uint16 platBps  = _getPlatformPips(totalBps);
        platformAmount = (amount * platBps) / totalBps;
        creatorAmount  = amount - platformAmount;
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        SafeTransfer.safeTransfer(token, to, amount);
    }

    // ============ Service-fee withdrawal ============

    function withdrawServiceFees(address to) external onlyOwner nonReentrant {
        require(to != address(0), "to=0");
        uint256 amt = retainedServiceFees;
        require(amt > 0, "nothing");
        retainedServiceFees = 0;
        _sendETH(to, amt);
        emit ServiceFeesWithdrawn(to, amt);
    }

    // ============ Admin ============

    function setCreator(uint256 positionId, address newCreator) external onlyAdminOrCreator(positionId) {
        require(positions[positionId].registered, "Not registered");
        require(newCreator != address(0), "Invalid creator");
        address oldCreator = positions[positionId].creator;
        require(newCreator != oldCreator, "Same creator");
        positions[positionId].creator = newCreator;
        _creatorHistory[positionId].push(newCreator);
        emit CreatorChanged(positionId, oldCreator, newCreator);
    }

    function setFeeMode(uint256 positionId, uint8 newMode) external onlyAdmin {
        require(positions[positionId].registered, "Not registered");
        require(newMode <= uint8(FeeMode.ALL_ETH), "Bad mode");
        FeeMode oldMode = positions[positionId].mode;
        FeeMode m = FeeMode(newMode);
        require(oldMode != m, "Same mode");
        positions[positionId].mode = m;
        emit FeeModeChanged(positionId, oldMode, m);
    }

    function adminTransferPosition(uint256 positionId, address to) external onlyAdmin nonReentrant {
        require(positions[positionId].registered, "Not registered");
        require(to != address(0), "Invalid recipient");
        IPositionManager(POSITION_MANAGER).safeTransferFrom(address(this), to, positionId);
        positions[positionId].registered = false;
        emit PositionTransferred(positionId, to);
    }

    // ============ Owner ============

    function setFactory(address _factory) external onlyOwner {
        address oldFactory = factory;
        factory = _factory;
        emit FactoryUpdated(oldFactory, _factory);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > retainedServiceFees, "no excess"); // never raid the service-fee accrual via emergency path
        uint256 emergency = balance - retainedServiceFees;
        (bool sent, ) = owner.call{value: emergency}("");
        require(sent, "Transfer failed");
        emit EmergencyETHWithdrawn(owner, emergency);
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        SafeTransfer.safeTransfer(token, owner, amount);
        emit EmergencyTokenWithdrawn(token, owner, amount);
    }

    // ============ Views ============

    function getPositionInfo(uint256 positionId) external view returns (
        address token, address creator, uint16 feePips, bool registered, uint8 mode
    ) {
        Position memory pos = positions[positionId];
        return (pos.token, pos.creator, pos.feePips, pos.registered, uint8(pos.mode));
    }

    function getPositionFeeStats(uint256 positionId) external view returns (
        uint256 totalETHCollected, uint256 totalTokensCollected,
        uint256 totalETHDistributed, uint256 totalTokensDistributed,
        uint256 creatorETHReceived, uint256 creatorTokensReceived,
        uint256 serviceFeeRetained,
        uint256 totalTokensSold, uint256 totalWethFromSales,
        uint256 lastCollected, uint256 lastDistributed,
        uint8   lastSellOutcome
    ) {
        FeeStats memory s = positionFeeStats[positionId];
        return (
            s.totalETHCollected, s.totalTokensCollected,
            s.totalETHDistributed, s.totalTokensDistributed,
            s.creatorETHReceived, s.creatorTokensReceived,
            s.serviceFeeRetained,
            s.totalTokensSold, s.totalWethFromSales,
            s.lastCollected, s.lastDistributed,
            s.lastSellOutcome
        );
    }

    function getGlobalFeeStats() external view returns (
        uint256 totalETHCollected, uint256 totalTokensCollected,
        uint256 totalETHDistributed, uint256 totalTokensDistributed,
        uint256 creatorETHReceived, uint256 creatorTokensReceived,
        uint256 platformETHReceived, uint256 platformTokensReceived,
        uint256 serviceFeeRetainedTotal,
        uint256 totalTokensSold, uint256 totalWethFromSales
    ) {
        return (
            globalFeeStats.totalETHCollected, globalFeeStats.totalTokensCollected,
            globalFeeStats.totalETHDistributed, globalFeeStats.totalTokensDistributed,
            globalFeeStats.creatorETHReceived, globalFeeStats.creatorTokensReceived,
            globalFeeStats.platformETHReceived, globalFeeStats.platformTokensReceived,
            globalFeeStats.serviceFeeRetained,
            globalFeeStats.totalTokensSold, globalFeeStats.totalWethFromSales
        );
    }

    function getCreatorHistory(uint256 positionId) external view returns (address[] memory) {
        return _creatorHistory[positionId];
    }

    function getRegisteredPositions() external view returns (uint256[] memory) {
        return registeredPositionIds;
    }

    function getFeeSplit(uint16 totalFeePips_) external pure returns (uint16 platformBps, uint16 creatorBps) {
        platformBps = _getPlatformPips(totalFeePips_);
        creatorBps  = totalFeePips_ - platformBps;
    }

    function getPositionCount() external view returns (uint256) {
        return registeredPositionIds.length;
    }

    function getPositionByToken(address token) external view returns (
        uint256 positionId, address creator, uint16 feePips, bool registered, uint8 mode
    ) {
        positionId = tokenToPositionId[token];
        Position memory pos = positions[positionId];
        return (positionId, pos.creator, pos.feePips, pos.registered, uint8(pos.mode));
    }

    /// @notice Off-chain helper. Reverts with claimable amounts (and effective mode) without
    /// distributing. Catch the ClaimableFeesResult error to read values.
    function getClaimableFees(uint256 positionId) external {
        Position memory pos = positions[positionId];
        require(pos.registered, "Not registered");
        (uint256 wethAmt, uint256 tokenAmt) = _takeFromV4(positionId, pos.token);
        revert ClaimableFeesResult(wethAmt, tokenAmt, uint8(pos.mode));
    }

    // ============ Receive ============

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
