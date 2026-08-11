// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Solang for Solana does not support importing external files with complex paths.
// The structs from "../abis/balancer_v3_vault.sol" are defined inline below.
// Original import: import {TokenInfo, PoolData, HooksConfig} from "../abis/balancer_v3_vault.sol";

// Inline definitions for the imported types
struct TokenInfo {
    address token;
    uint8 tokenType;
    address rateProvider;
    bool paysYieldFees;
}

struct PoolData {
    // Minimal representation; actual struct may have more fields.
    // Adjust as needed for your use case.
    address pool;
}

struct HooksConfig {
    // Minimal representation; actual struct may have more fields.
    bool enableHookAdjustedAmounts;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
}

struct UniswapV1Response {
    uint blockNumber;
    address token;
    address factory;
    uint8 tokenDecimals;
    string tokenName;
    string tokenSymbol;
    uint256 ethReserve;
    uint256 tokenReserve;
    uint24 fee;
}

struct UniswapV2LikeResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
}

struct FraxSwapV2Response {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint256 fee;
    // TWAMM
    uint256 twammReserve0;
    uint256 twammReserve1;
    uint256 lastVirtualOrderTimestamp;
    uint256 token0SalesRate;
    uint256 token1SalesRate;
    uint256 orderTimeInterval;
    // 订单到期：从 lastVirtualOrderTimestamp 起未来 48 小时内各到期时间点的 sales rate ending
    uint256 salesRateEndingCount;
    uint256[] salesRateEndingTimestamps;
    uint256[] orderPool0SalesRateEnding;
    uint256[] orderPool1SalesRateEnding;
    bool newSwapsPaused ;
}

struct TickInfo {
    int24 tick;
    int128 liquidityNet;
}

struct EkuboTickInfo {
    int32 tick;
    int128 liquidityNet;
}

struct UniswapV3LikeResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
    uint256 liquidity;
    uint256 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    int24 tickSpacing;
}

struct UniswapV3LikeTicksResponse {
    uint blockNumber;
    TickInfo[] ticks;
}

struct UniswapV4LikeResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    int24 tickSpacing;
    address hooks;
    uint24 protocolFee;
    uint128 liquidity;
    uint160 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
}

struct UniswapV4LikeResponseV2 {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    int24 tickSpacing;
    address hooks;
    uint24 protocolFee;
    uint128 liquidity;
    uint160 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    uint24 fee;
}

struct PancakeInfClResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    int24 tickSpacing;
    address hooks;
    uint24 protocolFee;
    uint128 liquidity;
    uint160 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    bytes32 parameters;
}

struct PancakeInfClResponseV2 {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    int24 tickSpacing;
    address hooks;
    uint24 protocolFee;
    uint128 liquidity;
    uint160 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    bytes32 parameters;
    uint24 fee;
}

struct UniswapV4LikeTicksResponse {
    uint blockNumber;
    TickInfo[] ticks;
}

struct PancakeStableResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 balance0;
    uint256 balance1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint256 fee;
    uint256[2] rates;
    uint256 nCoins;
    uint256 futureATime;
    uint256 futureA;
    uint256 initialATime;
    uint256 initialA;
    uint256 precision;
    uint256 feeDenominator;
    bool isKilled;
}

struct BinInfo {
    uint24 binId;
    uint128 binReserveX;
    uint128 binReserveY;
}

struct PancakeInfBinResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    bytes32 parameters;
    uint16 binStep;
    address hooks;
    uint24 protocolFee;
    uint24 activeId;
    uint24 activeBinIndex;
    BinInfo[] bins;
}

struct PancakeInfBinResponseV2 {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    bytes32 parameters;
    uint16 binStep;
    address hooks;
    uint24 protocolFee;
    uint24 activeId;
    uint24 activeBinIndex;
    BinInfo[] bins;
    uint24 fee;
}

struct PancakeInfBinBinsResponse {
    uint blockNumber;
    BinInfo[] bins;
}

struct DoDoV2ResponseV2 {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    uint24 mtFee;
    uint256 i;
    uint256 K;
    uint256 B;
    uint256 Q;
    uint256 B0;
    uint256 Q0;
    uint256 R;
}

struct MaverickV2Tick {
    int32 tick;
    uint256 reserveA;
    uint256 reserveB;
}

struct MaverickV2Response {
    uint blockNumber;
    address tokenA;
    address tokenB;
    uint8 decimalsA;
    uint8 decimalsB;
    string nameA;
    string nameB;
    string symbolA;
    string symbolB;
    uint256 feeAIn;
    uint256 feeBIn;
    uint256 tickSpacing;
    int32 activeTick;
    MaverickV2Tick[] ticks;
    uint256 reserveA; // 池子内 tokenA 余额（与 UniswapV3Like reserve 一致）
    uint256 reserveB; // 池子内 tokenB 余额
}

/// @notice 扩展 tick 数据（仅 ticks，用于与主池合并）
struct MaverickV2ExtraTicksResponse {
    uint blockNumber;
    uint256 tickSpacing;
    MaverickV2Tick[] ticks;
}

struct WombatResponse {
    uint blockNumber;
    uint256 nCoins;
    address[] tokens;
    bool[] isPaused;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint256[] cash;
    uint256[] liability;
    uint256[] relativePrices;
    uint256 ampFactor;
    uint256 haircutRate;
    uint128 startCovRatio;
    uint128 endCovRatio;
}

struct AlgebraV1LikeResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
    uint256 liquidity;
    uint256 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;

    uint16 feeConfigAlpha1; // max value of the first sigmoid
    uint16 feeConfigAlpha2; // max value of the second sigmoid
    uint32 feeConfigBeta1; // shift along the x-axis for the first sigmoid
    uint32 feeConfigBeta2; // shift along the x-axis for the second sigmoid
    uint16 feeConfigGamma1; // horizontal stretch factor for the first sigmoid
    uint16 feeConfigGamma2; // horizontal stretch factor for the second sigmoid
    uint32 feeConfigVolumeBeta; // shift along the x-axis for the outer volume-sigmoid
    uint16 feeConfigVolumeGamma; // horizontal stretch factor the outer volume-sigmoid
    uint16 feeConfigBaseFee; // minimum possible fee

    // 以下是新增字段
    uint16 timepointIndex;

    uint32[] timepointBlockTimestamps;
    uint112[] timepointVolatilityCumulatives;
    uint256[] timepointVolumePerAvgLiquiditys;
}

struct AlgebraV1LikeResponseV2 {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 feeZto;
    uint24 feeOtz;
    uint256 liquidity;
    uint256 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
}

struct AlgebraV1LikeTicksResponse {
    uint blockNumber;
    TickInfo[] ticks;
}

struct AlgebraIntegralBasePool {
    address token0;
    address token1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint8 decimals0;
    uint8 decimals1;
    uint256 reserve0;
    uint256 reserve1;
    uint24 fee;
    uint256 liquidity;
    uint256 sqrtPrice;
    address plugin;
    uint8 pluginConfig;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
}

struct DynamicFeeConfig {
    uint16 alpha1;
    uint16 alpha2;
    uint32 beta1;
    uint32 beta2;
    uint16 gamma1;
    uint16 gamma2;
    uint16 baseFee;
}

struct SlidingFeeConfig {
    uint128 zeroToOneFeeFactor;
    uint128 oneToZeroFeeFactor;
    uint16 priceChangeFactor;
    uint16 baseFee;
}

struct ThenaIntegralResponse {
    uint blockNumber;
    AlgebraIntegralBasePool basePoolInfo;
    bool pluginPaused;
    bool feeType;
    DynamicFeeConfig dynamicFeeConfig;
    SlidingFeeConfig slidingFeeConfig;
    bool discountIsActive;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint88[] timepointVolatilityCumulatives;
}

struct QuickswapV4Response {
    uint blockNumber;
    AlgebraIntegralBasePool basePoolInfo;
    DynamicFeeConfig dynamicFeeConfig;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint88[] timepointVolatilityCumulatives;
}

struct CypherV4Response {
    uint blockNumber;
    AlgebraIntegralBasePool basePoolInfo;
    bool dynamicFeeEnabled;
    bool slidingFeeEnabled;
    DynamicFeeConfig dynamicFeeConfig;
    SlidingFeeConfig slidingFeeConfig;
    uint16 timepointIndex;
    int24 lastTick;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint88[] timepointVolatilityCumulatives;
}

struct CamelotV4Response {
    uint blockNumber;
    AlgebraIntegralBasePool basePoolInfo;
    bool dynamicFeeEnabled;
    bool slidingFeeEnabled;
    DynamicFeeConfig dynamicFeeConfig;
    SlidingFeeConfig slidingFeeConfig;
    uint16 timepointIndex;
    int24 lastTick;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint88[] timepointVolatilityCumulatives;
}

struct WDexResponse {
    uint blockNumber;
    AlgebraIntegralBasePool basePoolInfo;
    bool dynamicFeeEnabled;
    DynamicFeeConfig dynamicFeeConfig;
    uint16 timepointIndex;
    int24 lastTick;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint88[] timepointVolatilityCumulatives;
    uint16 discountBps;
}

struct FluidDexResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint256 collateralTokenInRealReserves;
    uint256 collateralTokenOutRealReserves;
    uint256 debtTokenInRealReserves;
    uint256 debtTokenOutRealReserves;
    uint256 collateralTokenInImaginaryReserves;
    uint256 collateralTokenOutImaginaryReserves;
    uint256 debtTokenInImaginaryReserves;
    uint256 debtTokenOutImaginaryReserves;
    uint256 lastStoredPrice;
    uint256 centerPrice;
    uint256 upperRange;
    uint256 lowerRange;
    uint256 geometricMean;
    uint256 supplyToken0ExchangePrice;
    uint256 borrowToken0ExchangePrice;
    uint256 supplyToken1ExchangePrice;
    uint256 borrowToken1ExchangePrice;
    uint256 fee;
    uint256 withdrawableToken0Available;
    uint256 withdrawableToken0ExpandsTo;
    uint256 withdrawableToken0ExpandDuration;
    uint256 withdrawableToken1Available;
    uint256 withdrawableToken1ExpandsTo;
    uint256 withdrawableToken1ExpandDuration;
    uint256 borrowableToken0Available;
    uint256 borrowableToken0ExpandsTo;
    uint256 borrowableToken0ExpandDuration;
    uint256 borrowableToken1Available;
    uint256 borrowableToken1ExpandsTo;
    uint256 borrowableToken1ExpandDuration;
    uint256 token0UtilizationLimit;
    uint256 token1UtilizationLimit;
    uint256 token0LiquidityLayerUtilization;
    uint256 token1LiquidityLayerUtilization;
    bool token0Paused;
    bool token1Paused;
    bool isSwapAndArbitragePaused;
    uint256 token0LiquidityBalance;
    uint256 token1LiquidityBalance;
    uint256 token0TotalAmounts;
    uint256 token0ExchangePricesAndConfig;
    uint256 token0Configs2;
    uint256 token1TotalAmounts;
    uint256 token1ExchangePricesAndConfig;
    uint256 token1Configs2;
    // token precision immutables from constantsView2 (used for GetCollateralReserves/GetDebtReserves)
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
    uint256 token0SupplyTokenData;
    uint256 token0BorrowTokenData;
    uint256 token1SupplyTokenData;
    uint256 token1BorrowTokenData;
}

struct PositionFeesInfo {
    uint256 amount0;
    uint256 amount1;
}

enum FeeInPreference {
    Both,
    Paired,
    Clanker
}

struct PoolDynamicConfigVars {
    uint24 baseFee;
    uint24 maxLpFee;
    uint256 referenceTickFilterPeriod;
    uint256 resetPeriod;
    int24 resetTickFilter;
    uint256 feeControlNumerator;
    uint24 decayFilterBps;
}

struct PoolDynamicFeeVars {
    int24 referenceTick;
    int24 resetTick;
    uint256 resetTickTimestamp;
    uint256 lastSwapTimestamp;
    uint24 appliedVR;
    uint24 prevVA;
}

struct ClankerHookV2Response {
    bool clankerIsToken0;
    uint256 poolCreationTimestamp;
    bool mevModuleEnabled;
    uint256 maxMevModuleDelay;
    address lockerAddress;
    bool hasLocker;
    uint256 positionId;
    uint256 numPositions;
    uint16[] rewardBps;
    FeeInPreference[] feePreferences;
    PositionFeesInfo[] positionFees;
    uint24 clankerFee;
    uint24 pairedFee;
    PoolDynamicConfigVars configVars;
    PoolDynamicFeeVars feeVars;
}

struct ClankerHookResponse {
    bool clankerIsToken0;
    uint256 poolCreationTimestamp;
    bool mevModuleEnabled;
    uint256 maxMevModuleDelay;
    address lockerAddress;
    bool hasLocker;
    uint256 positionId;
    uint256 numPositions;
    uint16[] rewardBps;
    FeeInPreference[] feePreferences;
    PositionFeesInfo[] positionFees;
    uint24 clankerFee;
    uint24 pairedFee;
    PoolDynamicConfigVars configVars;
    PoolDynamicFeeVars feeVars;
    address mevModuleAddress;
    uint256 mevNextAuctionBlock;  // V1/V2: nextAuctionBlock (auction 阶段)
    uint256 mevDecayStartTime;    // V2 only: poolDecayStartTime (0 表示未开始 decay)
    uint24 mevStartingFee;        // V2 only: feeConfig.startingFee
    uint24 mevEndingFee;          // V2 only: feeConfig.endingFee
    uint256 mevSecondsToDecay;    // V2 only: feeConfig.secondsToDecay
    uint256 mevRound;             // V2 only: 当前 auction 轮次
    uint256 mevBlocksBetweenAuction; // V2 only: 两轮 auction 之间的区块间距
    uint256 mevPoolUnlockTime;      // V2 only: pool unlock time
}

struct SlipstreamBasePool {
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
    uint128 liquidity;
    uint160 sqrtPrice;
    int24 tick;
    int24 tickSpacing;
    address factory;
    uint16 observationIndex;
    uint16 observationCardinality;
    uint24 tickIndex;
    TickInfo[] ticks;
    uint256 reserve0;  // 添加到末尾以保持向后兼容性
    uint256 reserve1;  // 添加到末尾以保持向后兼容性
}

struct SlipstreamResponse {
    uint blockNumber;
    SlipstreamBasePool basePoolInfo;
    bool hasDynamicFee;
    address feeModuleAddr;
    uint24 baseFee;
    uint24 feeCap;
    uint64 scalingFactor;
    uint256 defaultScalingFactor;
    uint256 defaultFeeCap;
    uint32 secondsAgo;
    uint32[] observationTimestamps;
    int56[] observationTickCumulatives;
}

struct SlipstreamFactoriesOutput {
    bool isPool;
    address factory;
}

struct CurveStableResponseV3 {
    uint256 nCoins;
    uint blockNumber;
    address[] tokens;
    uint256[] decimals;
    uint256[] balances;
    string[] names;
    string[] symbols;
    uint256 [] assetTypes;
    uint256 [] storeRates;
    uint256 fee;
    uint256 adminFee;
    uint256 offPegFeeMultiplier;
    uint256 futureATime;
    uint256 futureA;
    uint256 initialATime;
    uint256 initialA;
    uint256 aPrecision;
    bool isMeta;
    CurveMetaPool metaPool;
    uint256[] actualBalances;
}

struct CurveMetaPool{
    uint256 nCoins;
    uint256 a;
    uint256 fee;
    uint256[] balances;
    uint256[] decimals;
    address[] tokens;
    string[] names;
    string[] symbols;
    address basePoolAddr;
    address lpToken;
    uint256 totalSupply;
    bool ng;
    uint256 futureATime;
    uint256 futureA;
    uint256 initialATime;
    uint256 initialA;
    uint256[] StoredRates;
    uint256 OffPegFeeMultiplier;
}

struct CurveBaseInfoResponse{
    bool isRegistered;
    bool isMeta;
    uint256 nCoins;
    uint256 baseNCoins;
}

struct CurveFilterResponseV2{
    bool isRegistered;
    bool isMeta;
    bool isLeading;
    address factory;
    uint256 nCoins;
    uint256 baseNCoins;
    uint256 [] assetTypes;
    address oracle;
    uint256 [] storeRates;
}

struct CamelotV2Response {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint112 reserve0;
    uint112 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    bool stableSwap;
    uint precisionMultiplier0;
    uint precisionMultiplier1;
    uint16 token0FeePercent;
    uint16 token1FeePercent;
}


struct AlgebraV1FeeConfiguration {
    uint16 alpha1;
    uint16 alpha2;
    uint32 beta1;
    uint32 beta2;
    uint16 gamma1;
    uint16 gamma2;
    uint32 volumeBeta;
    uint16 volumeGamma;
    uint16 baseFee;
}

struct AlgebraV1DirFeeLikeResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 feeZto;
    uint24 feeOtz;
    uint256 liquidity;
    uint256 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    AlgebraV1FeeConfiguration feeConfigZto;
    AlgebraV1FeeConfiguration feeConfigOtz;
    uint16 timepointIndex;
    uint32[] timepointBlockTimestamps;
    uint112[] timepointVolatilityCumulatives;
    uint256[] timepointVolumePerAvgLiquiditys;
}

struct AlgebraV1DirFeeLikeResponseV2 {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 feeZto;
    uint24 feeOtz;
    uint256 liquidity;
    uint256 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    AlgebraV1FeeConfiguration feeConfigZto;
    AlgebraV1FeeConfiguration feeConfigOtz;
    uint16 timepointIndex;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint112[] timepointVolatilityCumulatives;
    uint256[] timepointVolumePerAvgLiquiditys;
}

struct CurveCryptoResponseV2 {
    uint256 nCoins;                // 代币数量
    uint256 blockNumber;           // 区块号
    address[] tokens;              // 代币地址数组
    uint256[] decimals;            // 精度数组
    uint256[] balances;            // 余额数组
    string[] names;                // 名称数组
    string[] symbols;              // 符号数组
    uint256 futureAGamma;        //打包的[A,gamma]
    uint256 initialAGamma;       //打包的[A,gamma]
    uint256 futureAGammaTime;   //未来A和gamma的时间戳
    uint256 initialAGammaTime;  //未来A和gamma的时间戳
    uint256[] priceScales;         // 内部价格比例2币种1个，3币种2个
    uint256 D;                     //缓存的D
    uint256 feeGamma;             // 手续费gamma
    uint256 midFee;               // 中间手续费
    uint256 outFee;               // 外部手续费
    bool isKilled;
    uint256[] actualBalances;     // 真实余额数组
    bool isStableMath;     // 是否stable的池子
}

struct BalancerV2WeightedResponse {
    uint blockNumber;
    bytes32 poolId;
    address poolAddress;
    address vault;
    address[] tokens;
    uint256[] balances;
    uint256[] weights;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint256 swapFeePercentage;
    bool paused;
}

struct BalancerV1PoolResponse {
    uint blockNumber;
    address poolAddress;
    address[] tokens;
    uint256[] balances;
    uint256[] denormWeights;
    uint256 totalWeight;
    uint256 swapFee;
    bool finalized;
    bool publicSwap;
    uint8[] decimals;
    string[] names;
    string[] symbols;
}

struct BalancerV2StableResponse {
    uint blockNumber;
    bytes32 poolId;
    address poolAddress;
    address vault;
    address[] tokens;
    uint256[] balances;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint256 swapFeePercentage;
    uint256 amplificationParameter;  // 当前 Amp 值（实时计算，已包含线性插值）
    bool isAmpUpdating;              // Amp 是否正在调整中
    uint256 bptIndex;
    address[] rateProviders;         // Rate Provider 列表（地址为 0 表示无 rate provider）
    bool hasRateProvider;            // 是否有任何 rate provider（快速判断标志）
    bool paused;
}

struct BalancerV2PoolTypeResponse {
    bool isValid;                    // 是否是有效的 Balancer 池子
    uint8 poolType;                  // 池子类型编码
    string poolTypeName;             // 池子类型名称
}

struct BalancerV2EclpPoolTypeResponse {
    bool isValid;                    // 是否是有效的 ECLP 池子
}

struct BalancerV2EclpResponse {
    uint blockNumber;
    bytes32 poolId;
    address[] tokens;
    uint256[] balances;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint256 swapFeePercentage;
    // ECLP 参数
    int256 alpha;
    int256 beta;
    int256 c;
    int256 s;
    int256 lambda;
    // ECLP 派生参数
    int256 tauAlphaX;
    int256 tauAlphaY;
    int256 tauBetaX;
    int256 tauBetaY;
    int256 u;
    int256 v;
    int256 w;
    int256 z;
    int256 dSq;
    bool paused;
}


enum BalancerV3PoolType {
    UNKNOWN,
    WEIGHTED,
    STABLE,
    GYRO_ECLP,
    RECLAMM,
    QUANTAMM_WEIGHTED
}

struct BalancerV3PoolFeatures {
    BalancerV3PoolType poolType;
    address hooksContract;
}

struct BalancerV3BasePoolResponse {
    uint blockNumber;
    address[] tokens;
    TokenInfo[] tokenInfo;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint256[] balancesRaw;
    uint256[] tokenRates;
    uint256[] decimalScalingFactors;
    uint256 swapFeePercentage;
    address hooksContract;
    bool enableHookAdjustedAmounts;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool isVaultPaused;
    bool isPoolPaused;
}

struct RateProviderInfo {
    uint8 tokenIndex;
    address erc4626;
    address underlyingAsset;
    uint8 erc4626Decimals;
    uint8 underlyingDecimals;
    string underlyingName;
    string underlyingSymbol;
    bool isValid;
    address vaultAssetFeed; // non-zero for composite RPs (e.g. AaveMarketRateTransformer)
}

struct BalancerV3BasePoolResponseV2 {
    uint blockNumber;
    address[] tokens;
    TokenInfo[] tokenInfo;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint256[] balancesRaw;
    uint256[] tokenRates;
    uint256[] decimalScalingFactors;
    uint256 swapFeePercentage;
    address hooksContract;
    bool enableHookAdjustedAmounts;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool isVaultPaused;
    bool isPoolPaused;
    RateProviderInfo[] rateProviders;
}

struct LidoResponse {
    uint blockNumber;
    uint256 TotalPooledEther;
    uint256 TotalShares;
    uint256 StakeLimit;
}


struct EkuboPoolInfoResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint64 Fee;
    uint32 tickSpacing;
    address hooks;
    uint128 liquidity;
    uint96 sqrtPriceX96;
    int32 tick;
    uint256 tickIndex;
    EkuboTickInfo[] ticks;
}

struct NftStrategyHookResponse {
    uint256 deploymentBlock;
}

struct BancorV2PoolInfoResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address reserveToken0;
    address reserveToken1;
    uint256 reserveBalance0;
    uint256 reserveBalance1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint32 fee;
    address anchor;
}

struct BancorV2IsValidResponse {
    bool isValid; // 是否是有效的 Converter（50/50 权重）
}

struct RingSwapV2Response {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;              // fwToken0 地址
    address token1;              // fwToken1 地址
    uint256 reserve0;
    uint256 reserve1;
    string name0;                // fwToken0 的 name
    string name1;                // fwToken1 的 name
    string symbol0;              // fwToken0 的 symbol
    string symbol1;              // fwToken1 的 symbol
    address originalToken0;        // 原始 token0 地址（通过 fwToken0.token() 获取）
    address originalToken1;        // 原始 token1 地址（通过 fwToken1.token() 获取）
    uint8 originalDecimals0;      
    uint8 originalDecimals1;
    string originalName0;
    string originalName1;        
    string originalSymbol0;
    string originalSymbol1;
    uint256 originalToken0Balance;
    uint256 originalToken1Balance;
}

struct FwTokenInfo {
    address originalToken;      // 原始 token 地址
    uint8 originalDecimals;     // 原始 token 的 decimals
    string originalName;        // 原始 token 的 name
    string originalSymbol;      // 原始 token 的 symbol
    uint256 originalTokenBalance; // 原始 token 的余额
}

struct BancorV3PoolInfoResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address reserveToken0;
    address reserveToken1;
    uint256 reserveBalance0;
    uint256 reserveBalance1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint32 fee;
    bool tradingEnabled;
}

struct BancorV3IsValidResponse {
    bool isValid;
}

struct LfjV2PoolInfoResponse {
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint16 binStep;
    uint24 activeId;
    uint24 activeBinIndex;
    BinInfo[] bins;
    bytes32 hooksParameters;
    address hooks;
    uint8 hooksType;
    uint16 baseFactor;
    uint16 filterPeriod;
    uint16 decayPeriod;
    uint16 reductionFactor;
    uint24 variableFeeControl;
    uint16 protocolShare;
    uint24 maxVolatilityAccumulated;
    uint24 volatilityAccumulated;
    uint24 volatilityReference;
    uint24 indexRef;
    uint40 time;
}

struct NomiswapStableResponse {
    uint blockNumber;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    uint32 swapFee;
    uint256 A;
    uint8 token0Decimals;
    uint8 token1Decimals;
    string token0Name;
    string token1Name;
    string token0Symbol;
    string token1Symbol;
}

struct FlaunchHookResponse {
    uint24 swapFee;
    uint256 claimableFeesAmount0;
    uint256 claimableFeesAmount1;
}

struct LitePsmResponse {
    uint256 blockNumber;
    address gem;
    address dai;
    uint8 decimalsGem;
    uint8 decimalsDai;
    uint256 gemReserve;
    uint256 daiReserve;
    string gemName;
    string daiName;
    string gemSymbol;
    string daiSymbol;
    address pocket;
    uint256 to18ConversionFactor;
    uint256 tin;
    uint256 tout;
    uint256 HALTED;
    bool buyGemHalted;
    bool sellGemHalted;
}

struct SparkPsmResponse {
    uint256 blockNumber;
    // token0 = USDC
    address usdc;
    uint8   usdcDecimals;
    string  usdcName;
    string  usdcSymbol;
    // token1 = USDS
    address usds;
    uint8   usdsDecimals;
    string  usdsName;
    string  usdsSymbol;
    // token2 = sUSDS (yield-bearing)
    address susds;
    uint8   susdsDecimals;
    string  susdsName;
    string  susdsSymbol;
    address pocket;
    uint256 usdcReserve;   // USDC balance of pocket
    uint256 usdsReserve;   // USDS balance of PSM contract
    uint256 susdsReserve;  // sUSDS balance of PSM contract
}

struct DaiUsdsResponse {
    uint256 blockNumber;
    address dai;
    address usds;
    uint8 decimalsDai;
    uint8 decimalsUsds;
    uint256 daiReserve;
    uint256 usdsReserve;
    string daiName;
    string usdsName;
    string daiSymbol;
    string usdsSymbol;
}

struct UsddPsmResponse {
    uint256 blockNumber;
    address gem;
    address usdd;
    uint8 decimalsGem;
    uint8 decimalsUsdd;
    uint256 gemReserve;
    uint256 usddReserve;
    string gemName;
    string usddName;
    string gemSymbol;
    string usddSymbol;
    uint256 to18ConversionFactor;
    uint256 tin;
    uint256 tout;
    bool buyGemHalted;
    bool sellGemHalted;
}

struct FluidDexLiteDexIdExistResponse {
    bool isExist;
}

struct FluidDexLiteResponse{
    uint blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint256 fee;
    uint256 revenueCut;
    bytes32 salt;
    uint256 token0ImaginaryReserves;
    uint256 token1ImaginaryReserves;
    uint256 token0AdjustedSupply;
    uint256 token1AdjustedSupply;
    uint256 centerPrice;
    string dexId;
}

struct MooniswapResponse {
    uint blockNumber;
    address token0;
    address token1;
    uint256 reserve0;   
    uint256 reserve1;   
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint8 decimals0;
    uint8 decimals1;
    uint256 fee;       
    uint256 decayPeriod;
    uint216 vbAddition0Balance;
    uint40  vbAddition0Time;
    uint216 vbRemoval0Balance;
    uint40  vbRemoval0Time;
    uint216 vbAddition1Balance;
    uint40  vbAddition1Time;
    uint216 vbRemoval1Balance;
    uint40  vbRemoval1Time;
    uint256 slippageFee;
    uint104 virtualFeeOldResult;
    uint104 virtualFeeResult;
    uint48 virtualFeeTime;
    uint104 virtualSlippageFeeOldResult;
    uint104 virtualSlippageFeeResult;
    uint48 virtualSlippageFeeTime;
    uint104 virtualDecayPeriodOldResult;
    uint104 virtualDecayPeriodResult;
    uint48 virtualDecayPeriodTime;
}

// WooFi V2 Reader response types
struct WooFiV2TokenInfoResponse {
    uint256 reserve;
    uint16 feeRate;
    uint256 maxGamma;
    uint256 maxNotionalSwap;
    uint256 capBal;
}

struct WooFiV2StateResponse {
    uint256 price;
    uint256 spread;
    uint256 coeff;
    bool woFeasible;
}

struct WooFiV2DecimalInfoResponse {
    uint64 priceDec;
    uint64 quoteDec;
    uint64 baseDec;
}

struct WooFiV2BaseTokenDataResponse {
    WooFiV2StateResponse state;
    WooFiV2TokenInfoResponse tokenInfo;
    WooFiV2DecimalInfoResponse decimalInfo;
    string name;
    string symbol;
}

struct WooFiV2PoolsResponse {
    uint256 blockNumber;
    address poolAddress;
    address quoteToken;
    address wooracle;
    WooFiV2TokenInfoResponse quoteTokenInfo;
    string quoteTokenName;
    string quoteTokenSymbol;
    address[] baseTokenAddresses;
    WooFiV2BaseTokenDataResponse[] baseTokensData;
}

struct WooFiV2PoolsResponseV2 {
    uint256 blockNumber;
    address poolAddress;
    address quoteToken;
    address wooracle;
    WooFiV2TokenInfoResponse quoteTokenInfo;
    string quoteTokenName;
    string quoteTokenSymbol;
    address[] baseTokenAddresses;
    WooFiV2BaseTokenDataResponse[] baseTokensData;
    bool paused;
}


struct TesseraVOrderInfo {
    uint160 amount;
    uint64 priceMultiplierPpm;
    bool isDead;
}

struct TesseraVCurveState {
    TesseraVOrderInfo[20] baseToQuoteOrders;
    TesseraVOrderInfo[20] quoteToBaseOrders;
}

struct TesseraVStalenessWidenParams {
    uint64 cutoffBlock;
    uint64 widenStartBlock;
    uint32 widenCoeff;
    uint32 maxWidenPpm;
}

struct TesseraVPoolStateInfo {
    uint256 cumulativeQuoteAmountInSinceUpd;
    uint256 cumulativeBaseAmountInSinceUpd;
    uint32 widenPpm;
    uint32 cumulativeSwapAmountMultiplierPpm;
    uint8 fastPullLevel;
    bool reduceAccumulator;
    TesseraVStalenessWidenParams stalenessWidenParams;
    uint32 widenlistedPpm;
    bool enforceWhitelist;
    uint32 prioFeeThrehsoldFactor;
    uint32 widenPrioFeePpm;
    TesseraVCurveState curveState;
}

struct TesseraVSeqBlockPrice {
    uint8 seqNo;
    uint40 blockNumber;
    uint128 price;
}

struct TesseraVPoolInfoV2 {
    address token0;
    address token1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint8 decimals0;
    uint8 decimals1;
    uint256 reserve0;
    uint256 reserve1;
    TesseraVPoolStateInfo poolState;
    TesseraVSeqBlockPrice seqBlockPrice;
    uint256 vaultBalance0;
    uint256 vaultBalance1;
}

struct TesseraVAllPoolsInfoResponseV2 {
    uint256 blockNumber;
    uint256 globalPrioFeeThreshold;
    uint256 fastPullBlock;
    address[] pools;
    TesseraVPoolInfoV2[] poolInfos;
}

struct DopplerHookInitializerResponse {
    address dopplerHook;
    uint256 isDopplerHookEnabled;
    uint24 hookCustomFee;
}

struct ZoraV4HookResponse {
    address coin;
    uint256 creationTimestamp;
    bool isDeploying;
    bool hasCreationInfo;
    uint8 coinType;
}

struct AlphixHookResponse {
    bool paused;
    int24 tickLower;
    int24 tickUpper;
    address yieldSource0;
    address yieldSource1;
    uint256 amount0InYieldSource;
    uint256 amount1InYieldSource;
    uint256 maxDeposit0;
    uint256 maxDeposit1;
    uint256 maxWithdraw0;
    uint256 maxWithdraw1;
}

struct ExtraPollingERC4626Response {
    uint256 blockNumber;
    uint256[] rates;
}

struct ExtraPollingRateProviderResponse {
    uint256 blockNumber;
    uint256[] rates;
}

struct ExtraPollingChainlinkResponse {
    uint256 blockNumber;
    int256[] answers;
    uint8[]  decimals;
}

/// @notice 单个探针档位：(amountIn, amountOut)
struct ElfomoFiCumulativeLevel {
    uint256 amountIn;
    uint256 amountOut;
}

/// @notice ElfomoFi 交易对 orderbook 数据 + token 元数据
struct ElfomoFiResponse {
    uint256 blockNumber;
    // token 信息
    address base;
    address quote;
    uint8   baseDecimals;
    uint8   quoteDecimals;
    string  baseName;
    string  quoteName;
    string  baseSymbol;
    string  quoteSymbol;
    // 探针数据
    ElfomoFiCumulativeLevel[] askCumulativeLevels; // quote→base（用户买 base）
    ElfomoFiCumulativeLevel[] bidCumulativeLevels; // base→quote（用户卖 base）
    // Vault 余额
    uint256 balanceBase;
    uint256 balanceQuote;
}

struct OracleQuery {
    address oracle;
    bytes4  selector;
}

struct ExtraPollingOracleResponse {
    uint256 blockNumber;
    uint256[] rates;
    bool[] successes;
}

struct RebasingQuery {
    address token;
    address pool;
}

struct ExtraPollingRebasingResponse {
    uint256 blockNumber;
    uint256[] balances;
    bool[] successes;
}

struct AaveV3ReserveResponse {
    address underlying;
    address aToken;
    uint8 decimals;
    string name;
    string symbol;
    uint256 availableLiquidity;
    uint256 supplyCap;
    uint256 totalAToken;
    uint256 totalVariableDebt;
    uint128 liquidityIndex;
    uint256 ltv;
    uint256 liquidationThreshold;
    bool isActive;
    bool isFrozen;
    bool isPaused;
    bool borrowingEnabled;
    uint8 aTokenDecimals;
    string aTokenName;
    string aTokenSymbol;
}

struct AaveV3PoolsResponse {
    uint256 blockNumber;
    address pool;
    address oracle;
    address dataProvider;
    AaveV3ReserveResponse reserve;
}

struct PancakeInfStableResponse {
    uint256 blockNumber;
    uint256 nCoins;
    address[] tokens;
    uint256[] decimals;
    uint256[] balances;
    string[] names;
    string[] symbols;
    uint256 fee;
    uint256 offpegFeeMultiplier;
    uint256[] storedRates;
    uint256 futureATime;
    uint256 futureA;
    uint256 initialATime;
    uint256 initialA;
}

struct PancakeInfStableIsPoolResponse {
    bool isPool;
    uint256 nCoins;
}

struct BalancerV3Erc4626BalanceItem {
    address wrappedToken;           // ERC4626 地址
    bool    isBufferInitialized;    // vault 是否已初始化该 token 的 buffer
    uint256 maxDeposit;             // IERC4626(wrappedToken).maxDeposit(vault)
    uint256 maxRedeem;              // IERC4626(wrappedToken).maxRedeem(vault)
    uint256 bufferUnderlyingRaw;    // vault buffer 中 underlying 数量
    uint256 bufferWrappedRaw;       // vault buffer 中 wrapped 数量
}

struct BalancerV3Erc4626BalanceResponse {
    uint256 blockNumber;
    address vault;
    bool    areBuffersPaused;       // vault 级别，任一为 true 则整批拒绝
    BalancerV3Erc4626BalanceItem[] items;
}

struct FluidExtraLiquidityResponse {
    uint256 tokenData;
    uint256 blockNumber;
}
struct Erc4626Response {
    uint256 blockNumber;
    address vault;
    uint8   vaultDecimals;
    string  vaultName;
    string  vaultSymbol;
    address underlying;
    uint8   underlyingDecimals;
    string  underlyingName;
    string  underlyingSymbol;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 maxDeposit;
    uint256 maxMint;
}

struct ExtraPollingLlamaOracleResponse {
    uint256 blockNumber;
    uint256[] oraclePrices;
    uint256[] basePrices;
    bool[] successes;
}

// ─── Curve LlamaLend (LLAMMA AMM) ─────────────────────────────────────────────

struct CurveLlamaLendBand {
    int256  n;
    uint256 x;
    uint256 y;
}

struct CurveLlamaLendResponse {
    uint256 blockNumber;
    address token0;
    address token1;
    uint8   decimals0;
    uint8   decimals1;
    string  name0;
    string  name1;
    string  symbol0;
    string  symbol1;
    int256  minBand;
    int256  maxBand;
    int256  activeBand;
    uint256 A;
    uint256 fee1e18;
    uint256 basePrice;
    uint256 oraclePrice;
    uint256 pOracleUpActive;
    CurveLlamaLendBand[] bands;
}

struct ObricV2Response {
    uint256 blockNumber;
    address token0;
    address token1;
    uint8   decimals0;
    string  name0;
    string  symbol0;
    uint8   decimals1;
    string  name1;
    string  symbol1;
    uint256 reserveX;
    uint256 reserveY;
    uint256 currentXK;
    uint256 preK;
    uint256 multYBase;
    uint64  feeMillionth;
    uint256 priceMaxAge;
    uint256 priceUpdateTime;
    bool    isLocked;
}