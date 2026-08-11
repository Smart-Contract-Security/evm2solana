// !!! 注意：已经上生产的枚举，不要随意修改顺序
enum Dex {
    UNISWAP_V2,
    UNISWAP_V3,
    PANCAKESWAP_V3,
    PANCAKESWAP_V2,
    DODO_V2,
    UNISWAP_V4,
    PANCAKE_STABLE,
    PANCAKE_INF_CL,
    PANCAKE_INF_BIN,
    WOMBAT,
    ALGEBRA_V1,
    THENA_INTEGRAL,
    FLUID_DEX,
    SLIPSTREAM,
    AERODROME_VOLATILE,
    AERODROME_STABLE,
    CURVE_STABLE_NG,
    CURVE_STABLE_V1,
    QUICKSWAP_V4,
    EKUBO,
    CAMELOT_V2,
    ALGEBRA_V1_DIR_FEE,
    CAMELOT_V4,
    CURVE_CRYPTO,
    CURVE_CRYPTO_NG,
    BALANCER_WEIGHTED_V2,
    BALANCER_STABLE_V2,
    SQUAD_SWAP_V2,
    SQUAD_SWAP_V3,
    LIDO,
    LFJ_V2_LEGACY,
    LFJ_V2,
    RAMSES_V3,
    FLUID_DEX_LITE,
    EKUBO_V3,
    SHIBA_SWAP_V1,
    W_DEX,
    CYPHER_V4,
    INTEGRAL,
    HYDREX_V4,
    SOLIDLY_V3,
    SUPERNOVA_CL,
    TREBLE_SWAP,
    TREBLE_SWAP_V2
}

struct UniswapV2LikeRequest {
    address pool;
    Dex dex;
}

struct UniswapV3LikeRequest {
    address pool;
    Dex dex;
    int16 bitmapIndexLimit;
}

struct UniswapV3LikeTicksRequest {
    address pool;
    Dex dex;
    int16 bitmapOffsetStart;
    int16 bitmapOffsetEnd;
}

struct DoDoV2Request {
    address pool;
    Dex dex;
    address router;
}

struct PancakeStableRequest {
    address pool;
    Dex dex;
}

struct UniswapV4PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct UniswapV4LikeV3Request {
    address poolManager;
    bytes32 poolId;
    Dex dex;
    int16 bitmapIndexLimit;
    UniswapV4PoolKey poolKey;
}

struct UniswapV4LikeRequest {
    address poolManager;
    address positionManager;
    bytes32 poolId;
    Dex dex;
    int16 bitmapIndexLimit;
}

struct UniswapV4LikeTicksRequest {
    address poolManager;
    address positionManager;
    bytes32 poolId;
    Dex dex;
    int16 bitmapOffsetStart;
    int16 bitmapOffsetEnd;
}

struct PancakeInfBinRequest {
    address poolManager;
    bytes32 poolId;
    Dex dex;
    uint24 binRangeLimit;
}

struct PancakeInfBinBinsRequest {
    address poolManager;
    bytes32 poolId;
    Dex dex;
    int24 binOffsetStart;
    int24 binOffsetEnd;
}

struct WombatRequest {
    address pool;
    Dex dex;
}

struct AlgebraV1LikeRequest {
    address pool;
    Dex dex;
    int16 bitmapIndexLimit;
    uint32 timepointsSampleInterval;
}

struct AlgebraV1LikeRequestV2 {
    address pool;
    Dex dex;
    int16 bitmapIndexLimit;
    address quoter;
}

struct AlgebraV1LikeTicksRequest {
    address pool;
    Dex dex;
    int16 bitmapOffsetStart;
    int16 bitmapOffsetEnd;
}

struct AlgebraIntegralLikeRequest {
    address pool;
    Dex dex;
    uint24 tickCountLimit;
    uint32 timepointsSampleInterval;
}

struct SupernovaPoolInfoRequest {
    address pool;
    uint24 tickCountLimit;
    uint32 timepointsSampleInterval;
}

struct WDexRequest {
    address pool;
    uint24 tickCountLimit;
    uint32 timepointsSampleInterval;
}

struct FluidDexRequest {
    address pool;
    Dex dex;
    address dexReservesResolver;
}

enum ClankerHookType {
    STATIC_FEE_V2,
    DYNAMIC_FEE_V2,
    FEY_STATIC_FEE_V2,
    STATIC_FEE,
    DYNAMIC_FEE,
    LIQUID_STATIC_FEE_V2,
    LIQUID_DYNAMIC_FEE_V2
}

struct ClankerHookV2RequestV2 {
    bytes32 poolId;
    address hookAddress;
    ClankerHookType hookType;
    UniswapV4PoolKey poolKey;
}

struct SlipstreamRequest {
    address pool;
    Dex dex;
    int16 bitmapIndexLimit;
    uint32 observationSize;
    uint32 observationSecondsAgo;
}


struct CurveFactoryRequest {
    address metaRegistry;
    address pool;
    Dex dex;
}

struct BalancerV2WeightedRequest {
    address pool;
    address vault;
    Dex dex;
}

struct BalancerV1PoolRequest {
    address pool;
}

struct BalancerV2StableRequest {
    address pool;
    address vault;
    Dex dex;
}

struct BalancerV2PoolTypeRequest {
    address vault;
    address pool;
}

struct BalancerV2EclpRequest {
    address pool;
    address vault;
}


struct BalancerV3BasePoolRequest {
    address vault;
    address pool;
}

struct LidoRequest {
    address pool;
    Dex dex;
}

struct EkuboPoolKey {
    address token0;
    address token1;
    address extension;
    uint64 fee;
    uint32 tickSpacing;
}

struct EkuboPoolInfoRequest {
    address poolManager;
    bytes32 poolId;
    Dex dex;
    EkuboPoolKey poolKey;
    int16 bitmapIndexLimit;
    uint256 skipAhead;
}

/// @notice Request structure for Ekubo V3 pool information
/// @dev V3 uses PoolConfig (bytes32) instead of separate extension/fee/tickSpacing fields
struct EkuboPoolInfoRequestV3 {
    address core;
    bytes32 poolId;
    Dex dex;
    EkuboV3PoolKey poolKey;
    int16 bitmapIndexLimit;
    uint256 skipAhead;
}

/// @notice Pool key structure for Ekubo V3
/// @dev V3 uses a packed PoolConfig (bytes32) instead of separate fields
struct EkuboV3PoolKey {
    /// @notice Address of token0 (must be < token1)
    address token0;
    /// @notice Address of token1 (must be > token0)
    address token1;
    /// @notice Packed pool configuration (bytes32)
    /// @dev Contains: extension (20B) + fee (8B) + type config (4B)
    ///      Type config bit 31: 1 = Concentrated, 0 = Stableswap
    ///      For Concentrated: bits 30-0 = tick spacing
    ///      For Stableswap: bits 30-24 = amplification, bits 23-0 = center tick
    bytes32 config;
}

struct UniswapV4HookRequest {
    bytes32 poolId;
    address positionManager;
    address hookAddress;
    UniswapV4PoolKey poolKey;
}

struct BancorV2Request {
    address poolAddress; // Converter 地址（从事件 log.Address 获取）
    address converterRegistry; // ConverterRegistry 地址，用于验证 converter 是否有效
}

struct BancorV3Request {
    address poolCollection; // PoolCollection 合约地址
    address pool; // 池子地址（代币地址，TKN）
    address bancorNetworkInfo; // BancorNetworkInfo 合约地址
}

struct LfjV2Request {
    address pool;
    Dex dex;
    uint24 binCountLimit;
    address hooksManager;
}

struct NomiswapStableRequest {
    address pool;
}

struct TesseraVPoolInfoRequest {
    address pool;
    address manager;
}

struct FluidDexLiteDexIdRequest {
    bytes8 dexId;
    address fluidDexLiteResolver;
}

struct FluidDexLitePoolRequest {
    bytes8 dexId;
    address fluidDexLiteResolver;
    address fluidDexLite;
}


struct MaverickV2Request {
    address pool;
    address lens;
    int32 tickRadius;
}

struct MaverickV2ExtraTicksRequest {
    address pool;
    address lens;
    int32 tickRadiusStart;
    int32 tickRadiusEnd;
}

struct SolidlyV3PoolInfoRequest {
    address pool;
    int16 bitmapIndexLimit;
}

struct SolidlyV3TicksRequest {
    address pool;
    int16 bitmapOffsetStart;
    int16 bitmapOffsetEnd;
}

/// @notice Request for ElfomoFi pool orderbook data
struct ElfomoFiRequest {
    address helper;  // ElfomoFiHelper 合约地址（每链独立部署）
    address base;    // base token 地址
    address quote;   // quote token 地址
}

struct PancakeInfStableRequest {
    address pool;
    address factory;
}

struct FluidExtraLiquidityRequest {
    address liquidity;
    bytes32 slot;
}