import {AccountInfo} from 'solana';

struct HooksConfig {
    bool enableHookAdjustedAmounts;
    bool shouldCallBeforeInitialize;
    bool shouldCallAfterInitialize;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool shouldCallBeforeAddLiquidity;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallBeforeRemoveLiquidity;
    bool shouldCallAfterRemoveLiquidity;
    address hooksContract;
}

enum TokenType {
    STANDARD,
    WITH_RATE
}

struct TokenInfo {
    TokenType tokenType;
    address rateProvider;
    bool paysYieldFees;
}

struct PoolData {
    bytes32 poolConfigBits;
    address[] tokens;
    TokenInfo[] tokenInfo;
    uint64[] balancesRaw;
    uint64[] balancesLiveScaled18;
    uint64[] tokenRates;
    uint64[] decimalScalingFactors;
}

enum AddLiquidityKind {
    PROPORTIONAL,
    UNBALANCED,
    SINGLE_TOKEN_EXACT_OUT,
    DONATION,
    CUSTOM
}

enum RemoveLiquidityKind {
    PROPORTIONAL,
    SINGLE_TOKEN_EXACT_IN,
    SINGLE_TOKEN_EXACT_OUT,
    CUSTOM
}

interface Vault {
    event Swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint64 amountIn,
        uint64 amountOut,
        uint64 swapFeePercentage,
        uint64 swapFeeAmount
    );

    event LiquidityAdded(
        address pool,
        address liquidityProvider,
        AddLiquidityKind kind,
        uint64 totalSupply,
        uint64[] amountsAddedRaw,
        uint64[] swapFeeAmountsRaw
    );

    event LiquidityRemoved(
        address pool,
        address liquidityProvider,
        RemoveLiquidityKind kind,
        uint64 totalSupply,
        uint64[] amountsRemovedRaw,
        uint64[] swapFeeAmountsRaw
    );

    event PoolPausedStateChanged(address pool, bool paused);
    event SwapFeePercentageChanged(address pool, uint64 swapFeePercentage);
    event VaultAuxiliary(address pool, bytes32 eventKey, bytes eventData);

    function isVaultPaused() external view returns (bool vaultPaused);
    function isPoolInitialized(address pool) external view returns (bool initialized);
    function isPoolPaused(address pool) external view returns (bool poolPaused);

    function getPoolTokens(address pool) external view returns (address[] memory tokens);
    function getPoolData(address pool) external view returns (PoolData memory poolData);
    function getPoolTokenInfo(address pool)
        external
        view
        returns (
            address[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint64[] memory balancesRaw,
            uint64[] memory lastBalancesLiveScaled18
        );

    function getStaticSwapFeePercentage(address pool) external view returns (uint64 swapFeePercentage);
    function getHooksConfig(address pool) external view returns (HooksConfig memory hooksConfig);

    function areBuffersPaused() external view returns (bool);
    function getBufferBalance(address wrappedToken)
        external
        view
        returns (uint64 underlyingBalanceRaw, uint64 wrappedBalanceRaw);
    function isERC4626BufferInitialized(address wrappedToken) external view returns (bool);
}