// SPDX-License-Identifier: MIT

import {TokenInfo, PoolData, HooksConfig} from "../abis/balancer_v3_vault.sol";

struct UniswapV1Response {
    uint64 blockNumber;
    address token;
    address factory;
    uint8 tokenDecimals;
    string tokenName;
    string tokenSymbol;
    uint64 ethReserve;
    uint64 tokenReserve;
    uint24 fee;
}

struct UniswapV2LikeResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
}

struct FraxSwapV2Response {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint64 fee;
    uint64 twammReserve0;
    uint64 twammReserve1;
    uint64 lastVirtualOrderTimestamp;
    uint64 token0SalesRate;
    uint64 token1SalesRate;
    uint64 orderTimeInterval;
    uint64 salesRateEndingCount;
    uint64[] salesRateEndingTimestamps;
    uint64[] orderPool0SalesRateEnding;
    uint64[] orderPool1SalesRateEnding;
    bool newSwapsPaused;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
    uint64 liquidity;
    uint64 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    int24 tickSpacing;
}

struct UniswapV3LikeTicksResponse {
    uint64 blockNumber;
    TickInfo[] ticks;
}

struct UniswapV4LikeResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    TickInfo[] ticks;
}

struct PancakeStableResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 balance0;
    uint64 balance1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint64 fee;
    uint64[2] rates;
    uint64 nCoins;
    uint64 futureATime;
    uint64 futureA;
    uint64 initialATime;
    uint64 initialA;
    uint64 precision;
    uint64 feeDenominator;
    bool isKilled;
}

struct BinInfo {
    uint24 binId;
    uint128 binReserveX;
    uint128 binReserveY;
}

struct PancakeInfBinResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    BinInfo[] bins;
}

struct DoDoV2ResponseV2 {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 lpFee;
    uint24 mtFee;
    uint64 i;
    uint64 K;
    uint64 B;
    uint64 Q;
    uint64 B0;
    uint64 Q0;
    uint64 R;
}

struct MaverickV2Tick {
    int32 tick;
    uint64 reserveA;
    uint64 reserveB;
}

struct MaverickV2Response {
    uint64 blockNumber;
    address tokenA;
    address tokenB;
    uint8 decimalsA;
    uint8 decimalsB;
    string nameA;
    string nameB;
    string symbolA;
    string symbolB;
    uint64 feeAIn;
    uint64 feeBIn;
    uint64 tickSpacing;
    int32 activeTick;
    MaverickV2Tick[] ticks;
    uint64 reserveA;
    uint64 reserveB;
}

struct MaverickV2ExtraTicksResponse {
    uint64 blockNumber;
    uint64 tickSpacing;
    MaverickV2Tick[] ticks;
}

struct WombatResponse {
    uint64 blockNumber;
    uint64 nCoins;
    address[] tokens;
    bool[] isPaused;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint64[] cash;
    uint64[] liability;
    uint64[] relativePrices;
    uint64 ampFactor;
    uint64 haircutRate;
    uint128 startCovRatio;
    uint128 endCovRatio;
}

struct AlgebraV1LikeResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 fee;
    uint64 liquidity;
    uint64 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    uint16 feeConfigAlpha1;
    uint16 feeConfigAlpha2;
    uint32 feeConfigBeta1;
    uint32 feeConfigBeta2;
    uint16 feeConfigGamma1;
    uint16 feeConfigGamma2;
    uint32 feeConfigVolumeBeta;
    uint16 feeConfigVolumeGamma;
    uint16 feeConfigBaseFee;
    uint16 timepointIndex;
    uint32[] timepointBlockTimestamps;
    uint112[] timepointVolatilityCumulatives;
    uint64[] timepointVolumePerAvgLiquiditys;
}

struct AlgebraV1LikeResponseV2 {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 feeZto;
    uint24 feeOtz;
    uint64 liquidity;
    uint64 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
}

struct AlgebraV1LikeTicksResponse {
    uint64 blockNumber;
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
    uint64 reserve0;
    uint64 reserve1;
    uint24 fee;
    uint64 liquidity;
    uint64 sqrtPrice;
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
    uint64 blockNumber;
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
    uint64 blockNumber;
    AlgebraIntegralBasePool basePoolInfo;
    DynamicFeeConfig dynamicFeeConfig;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint88[] timepointVolatilityCumulatives;
}

struct CypherV4Response {
    uint64 blockNumber;
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
    uint64 blockNumber;
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
    uint64 blockNumber;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint64 collateralTokenInRealReserves;
    uint64 collateralTokenOutRealReserves;
    uint64 debtTokenInRealReserves;
    uint64 debtTokenOutRealReserves;
    uint64 collateralTokenInImaginaryReserves;
    uint64 collateralTokenOutImaginaryReserves;
    uint64 debtTokenInImaginaryReserves;
    uint64 debtTokenOutImaginaryReserves;
    uint64 lastStoredPrice;
    uint64 centerPrice;
    uint64 upperRange;
    uint64 lowerRange;
    uint64 geometricMean;
    uint64 supplyToken0ExchangePrice;
    uint64 borrowToken0ExchangePrice;
    uint64 supplyToken1ExchangePrice;
    uint64 borrowToken1ExchangePrice;
    uint64 fee;
    uint64 withdrawableToken0Available;
    uint64 withdrawableToken0ExpandsTo;
    uint64 withdrawableToken0ExpandDuration;
    uint64 withdrawableToken1Available;
    uint64 withdrawableToken1ExpandsTo;
    uint64 withdrawableToken1ExpandDuration;
    uint64 borrowableToken0Available;
    uint64 borrowableToken0ExpandsTo;
    uint64 borrowableToken0ExpandDuration;
    uint64 borrowableToken1Available;
    uint64 borrowableToken1ExpandsTo;
    uint64 borrowableToken1ExpandDuration;
    uint64 token0UtilizationLimit;
    uint64 token1UtilizationLimit;
    uint64 token0LiquidityLayerUtilization;
    uint64 token1LiquidityLayerUtilization;
    bool token0Paused;
    bool token1Paused;
    bool isSwapAndArbitragePaused;
    uint64 token0LiquidityBalance;
    uint64 token1LiquidityBalance;
    uint64 token0TotalAmounts;
    uint64 token0ExchangePricesAndConfig;
    uint64 token0Configs2;
    uint64 token1TotalAmounts;
    uint64 token1ExchangePricesAndConfig;
    uint64 token1Configs2;
    uint64 token0NumeratorPrecision;
    uint64 token0DenominatorPrecision;
    uint64 token1NumeratorPrecision;
    uint64 token1DenominatorPrecision;
    uint64 token0SupplyTokenData;
    uint64 token0BorrowTokenData;
    uint64 token1SupplyTokenData;
    uint64 token1BorrowTokenData;
}

struct PositionFeesInfo {
    uint64 amount0;
    uint64 amount1;
}

enum FeeInPreference {
    Both,
    Paired,
    Clanker
}

struct PoolDynamicConfigVars {
    uint24 baseFee;
    uint24 maxLpFee;
    uint64 referenceTickFilterPeriod;
    uint64 resetPeriod;
    int24 resetTickFilter;
    uint64 feeControlNumerator;
    uint24 decayFilterBps;
}

struct PoolDynamicFeeVars {
    int24 referenceTick;
    int24 resetTick;
    uint64 resetTickTimestamp;
    uint64 lastSwapTimestamp;
    uint24 appliedVR;
    uint24 prevVA;
}

struct ClankerHookV2Response {
    bool clankerIsToken0;
    uint64 poolCreationTimestamp;
    bool mevModuleEnabled;
    uint64 maxMevModuleDelay;
    address lockerAddress;
    bool hasLocker;
    uint64 positionId;
    uint64 numPositions;
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
    uint64 poolCreationTimestamp;
    bool mevModuleEnabled;
    uint64 maxMevModuleDelay;
    address lockerAddress;
    bool hasLocker;
    uint64 positionId;
    uint64 numPositions;
    uint16[] rewardBps;
    FeeInPreference[] feePreferences;
    PositionFeesInfo[] positionFees;
    uint24 clankerFee;
    uint24 pairedFee;
    PoolDynamicConfigVars configVars;
    PoolDynamicFeeVars feeVars;
    address mevModuleAddress;
    uint64 mevNextAuctionBlock;
    uint64 mevDecayStartTime;
    uint24 mevStartingFee;
    uint24 mevEndingFee;
    uint64 mevSecondsToDecay;
    uint64 mevRound;
    uint64 mevBlocksBetweenAuction;
    uint64 mevPoolUnlockTime;
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
    uint64 reserve0;
    uint64 reserve1;
}

struct SlipstreamResponse {
    uint64 blockNumber;
    SlipstreamBasePool basePoolInfo;
    bool hasDynamicFee;
    address feeModuleAddr;
    uint24 baseFee;
    uint24 feeCap;
    uint64 scalingFactor;
    uint64 defaultScalingFactor;
    uint64 defaultFeeCap;
    uint32 secondsAgo;
    uint32[] observationTimestamps;
    int56[] observationTickCumulatives;
}

struct SlipstreamFactoriesOutput {
    bool isPool;
    address factory;
}

struct CurveStableResponseV3 {
    uint64 nCoins;
    uint64 blockNumber;
    address[] tokens;
    uint64[] decimals;
    uint64[] balances;
    string[] names;
    string[] symbols;
    uint64[] assetTypes;
    uint64[] storeRates;
    uint64 fee;
    uint64 adminFee;
    uint64 offPegFeeMultiplier;
    uint64 futureATime;
    uint64 futureA;
    uint64 initialATime;
    uint64 initialA;
    uint64 aPrecision;
    bool isMeta;
    CurveMetaPool metaPool;
    uint64[] actualBalances;
}

struct CurveMetaPool {
    uint64 nCoins;
    uint64 a;
    uint64 fee;
    uint64[] balances;
    uint64[] decimals;
    address[] tokens;
    string[] names;
    string[] symbols;
    address basePoolAddr;
    address lpToken;
    uint64 totalSupply;
    bool ng;
    uint64 futureATime;
    uint64 futureA;
    uint64 initialATime;
    uint64 initialA;
    uint64[] StoredRates;
    uint64 OffPegFeeMultiplier;
}

struct CurveBaseInfoResponse {
    bool isRegistered;
    bool isMeta;
    uint64 nCoins;
    uint64 baseNCoins;
}

struct CurveFilterResponseV2 {
    bool isRegistered;
    bool isMeta;
    bool isLeading;
    address factory;
    uint64 nCoins;
    uint64 baseNCoins;
    uint64[] assetTypes;
    address oracle;
    uint64[] storeRates;
}

struct CamelotV2Response {
    uint64 blockNumber;
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
    uint64 precisionMultiplier0;
    uint64 precisionMultiplier1;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 feeZto;
    uint24 feeOtz;
    uint64 liquidity;
    uint64 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    AlgebraV1FeeConfiguration feeConfigZto;
    AlgebraV1FeeConfiguration feeConfigOtz;
    uint16 timepointIndex;
    uint32[] timepointBlockTimestamps;
    uint112[] timepointVolatilityCumulatives;
    uint64[] timepointVolumePerAvgLiquiditys;
}

struct AlgebraV1DirFeeLikeResponseV2 {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint24 feeZto;
    uint24 feeOtz;
    uint64 liquidity;
    uint64 sqrtPriceX96;
    int24 tick;
    uint24 tickIndex;
    TickInfo[] ticks;
    AlgebraV1FeeConfiguration feeConfigZto;
    AlgebraV1FeeConfiguration feeConfigOtz;
    uint16 timepointIndex;
    uint32[] timepointBlockTimestamps;
    int56[] timepointTickCumulatives;
    uint112[] timepointVolatilityCumulatives;
    uint64[] timepointVolumePerAvgLiquiditys;
}

struct CurveCryptoResponseV2 {
    uint64 nCoins;
    uint64 blockNumber;
    address[] tokens;
    uint64[] decimals;
    uint64[] balances;
    string[] names;
    string[] symbols;
    uint64 futureAGamma;
    uint64 initialAGamma;
    uint64 futureAGammaTime;
    uint64 initialAGammaTime;
    uint64[] priceScales;
    uint64 D;
    uint64 feeGamma;
    uint64 midFee;
    uint64 outFee;
    bool isKilled;
    uint64[] actualBalances;
    bool isStableMath;
}

struct BalancerV2WeightedResponse {
    uint64 blockNumber;
    bytes32 poolId;
    address poolAddress;
    address vault;
    address[] tokens;
    uint64[] balances;
    uint64[] weights;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint64 swapFeePercentage;
    bool paused;
}

struct BalancerV1PoolResponse {
    uint64 blockNumber;
    address poolAddress;
    address[] tokens;
    uint64[] balances;
    uint64[] denormWeights;
    uint64 totalWeight;
    uint64 swapFee;
    bool finalized;
    bool publicSwap;
    uint8[] decimals;
    string[] names;
    string[] symbols;
}

struct BalancerV2StableResponse {
    uint64 blockNumber;
    bytes32 poolId;
    address poolAddress;
    address vault;
    address[] tokens;
    uint64[] balances;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint64 swapFeePercentage;
    uint64 amplificationParameter;
    bool isAmpUpdating;
    uint64 bptIndex;
    address[] rateProviders;
    bool hasRateProvider;
    bool paused;
}

struct BalancerV2PoolTypeResponse {
    bool isValid;
    uint8 poolType;
    string poolTypeName;
}

struct BalancerV2EclpPoolTypeResponse {
    bool isValid;
}

struct BalancerV2EclpResponse {
    uint64 blockNumber;
    bytes32 poolId;
    address[] tokens;
    uint64[] balances;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint64 swapFeePercentage;
    int64 alpha;
    int64 beta;
    int64 c;
    int64 s;
    int64 lambda;
    int64 tauAlphaX;
    int64 tauAlphaY;
    int64 tauBetaX;
    int64 tauBetaY;
    int64 u;
    int64 v;
    int64 w;
    int64 z;
    int64 dSq;
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
    uint64 blockNumber;
    address[] tokens;
    TokenInfo[] tokenInfo;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint64[] balancesRaw;
    uint64[] tokenRates;
    uint64[] decimalScalingFactors;
    uint64 swapFeePercentage;
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
    address vaultAssetFeed;
}

struct BalancerV3BasePoolResponseV2 {
    uint64 blockNumber;
    address[] tokens;
    TokenInfo[] tokenInfo;
    uint8[] decimals;
    string[] names;
    string[] symbols;
    uint64[] balancesRaw;
    uint64[] tokenRates;
    uint64[] decimalScalingFactors;
    uint64 swapFeePercentage;
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
    uint64 blockNumber;
    uint64 TotalPooledEther;
    uint64 TotalShares;
    uint64 StakeLimit;
}

struct EkuboPoolInfoResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 tickIndex;
    EkuboTickInfo[] ticks;
}

struct NftStrategyHookResponse {
    uint64 deploymentBlock;
}

struct BancorV2PoolInfoResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address reserveToken0;
    address reserveToken1;
    uint64 reserveBalance0;
    uint64 reserveBalance1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint32 fee;
    address anchor;
}

struct BancorV2IsValidResponse {
    bool isValid;
}

struct RingSwapV2Response {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    address originalToken0;
    address originalToken1;
    uint8 originalDecimals0;
    uint8 originalDecimals1;
    string originalName0;
    string originalName1;
    string originalSymbol0;
    string originalSymbol1;
    uint64 originalToken0Balance;
    uint64 originalToken1Balance;
}

struct FwTokenInfo {
    address originalToken;
    uint8 originalDecimals;
    string originalName;
    string originalSymbol;
    uint64 originalTokenBalance;
}

struct BancorV3PoolInfoResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address reserveToken0;
    address reserveToken1;
    uint64 reserveBalance0;
    uint64 reserveBalance1;
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
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
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
    uint64 blockNumber;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    uint32 swapFee;
    uint64 A;
    uint8 token0Decimals;
    uint8 token1Decimals;
    string token0Name;
    string token1Name;
    string token0Symbol;
    string token1Symbol;
}

struct FlaunchHookResponse {
    uint24 swapFee;
    uint64 claimableFeesAmount0;
    uint64 claimableFeesAmount1;
}

struct LitePsmResponse {
    uint64 blockNumber;
    address gem;
    address dai;
    uint8 decimalsGem;
    uint8 decimalsDai;
    uint64 gemReserve;
    uint64 daiReserve;
    string gemName;
    string daiName;
    string gemSymbol;
    string daiSymbol;
    address pocket;
    uint64 to18ConversionFactor;
    uint64 tin;
    uint64 tout;
    uint64 HALTED;
    bool buyGemHalted;
    bool sellGemHalted;
}

struct SparkPsmResponse {
    uint64 blockNumber;
    address usdc;
    uint8 usdcDecimals;
    string usdcName;
    string usdcSymbol;
    address usds;
    uint8 usdsDecimals;
    string usdsName;
    string usdsSymbol;
    address susds;
    uint8 susdsDecimals;
    string susdsName;
    string susdsSymbol;
    address pocket;
    uint64 usdcReserve;
    uint64 usdsReserve;
    uint64 susdsReserve;
}

struct DaiUsdsResponse {
    uint64 blockNumber;
    address dai;
    address usds;
    uint8 decimalsDai;
    uint8 decimalsUsds;
    uint64 daiReserve;
    uint64 usdsReserve;
    string daiName;
    string usdsName;
    string daiSymbol;
    string usdsSymbol;
}

struct UsddPsmResponse {
    uint64 blockNumber;
    address gem;
    address usdd;
    uint8 decimalsGem;
    uint8 decimalsUsdd;
    uint64 gemReserve;
    uint64 usddReserve;
    string gemName;
    string usddName;
    string gemSymbol;
    string usddSymbol;
    uint64 to18ConversionFactor;
    uint64 tin;
    uint64 tout;
    bool buyGemHalted;
    bool sellGemHalted;
}

struct FluidDexLiteDexIdExistResponse {
    bool isExist;
}

struct FluidDexLiteResponse {
    uint64 blockNumber;
    uint8 decimals0;
    uint8 decimals1;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint64 fee;
    uint64 revenueCut;
    bytes32 salt;
    uint64 token0ImaginaryReserves;
    uint64 token1ImaginaryReserves;
    uint64 token0AdjustedSupply;
    uint64 token1AdjustedSupply;
    uint64 centerPrice;
    string dexId;
}

struct MooniswapResponse {
    uint64 blockNumber;
    address token0;
    address token1;
    uint64 reserve0;
    uint64 reserve1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    uint8 decimals0;
    uint8 decimals1;
    uint64 fee;
    uint64 decayPeriod;
    uint216 vbAddition0Balance;
    uint40 vbAddition0Time;
    uint216 vbRemoval0Balance;
    uint40 vbRemoval0Time;
    uint216 vbAddition1Balance;
    uint40 vbAddition1Time;
    uint216 vbRemoval1Balance;
    uint40 vbRemoval1Time;
    uint64 slippageFee;
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

struct WooFiV2TokenInfoResponse {
    uint64 reserve;
    uint16 feeRate;
    uint64 maxGamma;
    uint64 maxNotionalSwap;
    uint64 capBal;
}

struct WooFiV2StateResponse {
    uint64 price;
    uint64 spread;
    uint64 coeff;
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
    uint64 blockNumber;
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
    uint64 blockNumber;
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
    uint64 cumulativeQuoteAmountInSinceUpd;
    uint64 cumulativeBaseAmountInSinceUpd;
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
    uint64 reserve0;
    uint64 reserve1;
    TesseraVPoolStateInfo poolState;
    TesseraVSeqBlockPrice seqBlockPrice;
    uint64 vaultBalance0;
    uint64 vaultBalance1;
}

struct TesseraVAllPoolsInfoResponseV2 {
    uint64 blockNumber;
    uint64 globalPrioFeeThreshold;
    uint64 fastPullBlock;
    address[] pools;
    TesseraVPoolInfoV2[] poolInfos;
}

struct DopplerHookInitializerResponse {
    address dopplerHook;
    uint64 isDopplerHookEnabled;
    uint24 hookCustomFee;
}

struct ZoraV4HookResponse {
    address coin;
    uint64 creationTimestamp;
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
    uint64 amount0InYieldSource;
    uint64 amount1InYieldSource;
    uint64 maxDeposit0;
    uint64 maxDeposit1;
    uint64 maxWithdraw0;
    uint64 maxWithdraw1;
}

struct ExtraPollingERC4626Response {
    uint64 blockNumber;
    uint64[] rates;
}

struct ExtraPollingRateProviderResponse {
    uint64 blockNumber;
    uint64[] rates;
}

struct ExtraPollingChainlinkResponse {
    uint64 blockNumber;
    int64[] answers;
    uint8[] decimals;
}

struct ElfomoFiCumulativeLevel {
    uint64 amountIn;
    uint64 amountOut;
}

struct ElfomoFiResponse {
    uint64 blockNumber;
    address base;
    address quote;
    uint8 baseDecimals;
    uint8 quoteDecimals;
    string baseName;
    string quoteName;
    string baseSymbol;
    string quoteSymbol;
    ElfomoFiCumulativeLevel[] askCumulativeLevels;
    ElfomoFiCumulativeLevel[] bidCumulativeLevels;
    uint64 balanceBase;
    uint64 balanceQuote;
}

struct OracleQuery {
    address oracle;
    bytes4 selector;
}

struct ExtraPollingOracleResponse {
    uint64 blockNumber;
    uint64[] rates;
    bool[] successes;
}

struct RebasingQuery {
    address token;
    address pool;
}

struct ExtraPollingRebasingResponse {
    uint64 blockNumber;
    uint64[] balances;
    bool[] successes;
}

struct AaveV3ReserveResponse {
    address underlying;
    address aToken;
    uint8 decimals;
    string name;
    string symbol;
    uint64 availableLiquidity;
    uint64 supplyCap;
    uint64 totalAToken;
    uint64 totalVariableDebt;
    uint128 liquidityIndex;
    uint64 ltv;
    uint64 liquidationThreshold;
    bool isActive;
    bool isFrozen;
    bool isPaused;
    bool borrowingEnabled;
    uint8 aTokenDecimals;
    string aTokenName;
    string aTokenSymbol;
}

struct AaveV3PoolsResponse {
    uint64 blockNumber;
    address pool;
    address oracle;
    address dataProvider;
    AaveV3ReserveResponse reserve;
}

struct PancakeInfStableResponse {
    uint64 blockNumber;
    uint64 nCoins;
    address[] tokens;
    uint64[] decimals;
    uint64[] balances;
    string[] names;
    string[] symbols;
    uint64 fee;
    uint64 offpegFeeMultiplier;
    uint64[] storedRates;
    uint64 futureATime;
    uint64 futureA;
    uint64 initialATime;
    uint64 initialA;
}

struct PancakeInfStableIsPoolResponse {
    bool isPool;
    uint64 nCoins;
}

struct BalancerV3Erc4626BalanceItem {
    address wrappedToken;
    bool isBufferInitialized;
    uint64 maxDeposit;
    uint64 maxRedeem;
    uint64 bufferUnderlyingRaw;
    uint64 bufferWrappedRaw;
}

struct BalancerV3Erc4626BalanceResponse {
    uint64 blockNumber;
    address vault;
    bool areBuffersPaused;
    BalancerV3Erc4626BalanceItem[] items;
}

struct FluidExtraLiquidityResponse {
    uint64 tokenData;
    uint64 blockNumber;
}

struct Erc4626Response {
    uint64 blockNumber;
    address vault;
    uint8 vaultDecimals;
    string vaultName;
    string vaultSymbol;
    address underlying;
    uint8 underlyingDecimals;
    string underlyingName;
    string underlyingSymbol;
    uint64 totalSupply;
    uint64 totalAssets;
    uint64 maxDeposit;
    uint64 maxMint;
}

struct ExtraPollingLlamaOracleResponse {
    uint64 blockNumber;
    uint64[] oraclePrices;
    uint64[] basePrices;
    bool[] successes;
}

struct CurveLlamaLendBand {
    int64 n;
    uint64 x;
    uint64 y;
}

struct CurveLlamaLendResponse {
    uint64 blockNumber;
    address token0;
    address token1;
    uint8 decimals0;
    uint8 decimals1;
    string name0;
    string name1;
    string symbol0;
    string symbol1;
    int64 minBand;
    int64 maxBand;
    int64 activeBand;
    uint64 A;
    uint64 fee1e18;
    uint64 basePrice;
    uint64 oraclePrice;
    uint64 pOracleUpActive;
    CurveLlamaLendBand[] bands;
}

struct ObricV2Response {
    uint64 blockNumber;
    address token0;
    address token1;
    uint8 decimals0;
    string name0;
    string symbol0;
    uint8 decimals1;
    string name1;
    string symbol1;
    uint64 reserveX;
    uint64 reserveY;
    uint64 currentXK;
    uint64 preK;
    uint64 multYBase;
    uint64 feeMillionth;
    uint64 priceMaxAge;
    uint64 priceUpdateTime;
    bool isLocked;
}