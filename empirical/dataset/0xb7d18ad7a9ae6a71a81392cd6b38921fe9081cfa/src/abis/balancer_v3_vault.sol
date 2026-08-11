// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
    uint256[] balancesRaw;
    uint256[] balancesLiveScaled18;
    uint256[] tokenRates;
    uint256[] decimalScalingFactors;
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
        address indexed pool,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 swapFeePercentage,
        uint256 swapFeeAmount
    );

    event LiquidityAdded(
        address indexed pool,
        address indexed liquidityProvider,
        AddLiquidityKind indexed kind,
        uint256 totalSupply,
        uint256[] amountsAddedRaw,
        uint256[] swapFeeAmountsRaw
    );

    event LiquidityRemoved(
        address indexed pool,
        address indexed liquidityProvider,
        RemoveLiquidityKind indexed kind,
        uint256 totalSupply,
        uint256[] amountsRemovedRaw,
        uint256[] swapFeeAmountsRaw
    );

    event PoolPausedStateChanged(address indexed pool, bool paused);
    event SwapFeePercentageChanged(address indexed pool, uint256 swapFeePercentage);
    event VaultAuxiliary(address indexed pool, bytes32 indexed eventKey, bytes eventData);

    /// @notice The user tried to swap zero tokens.
    error AmountGivenZero();

    /// @notice The user attempted to swap a token for itself.
    error CannotSwapSameToken();

    /**
     * @notice The user attempted to operate with a token that is not in the pool.
     * @param token The unregistered token
     */
    error TokenNotRegistered(address token);

    /**
     * @notice An amount in or out has exceeded the limit specified in the swap request.
     * @param amount The total amount in or out
     * @param limit The amount of the limit that has been exceeded
     */
    error SwapLimit(uint256 amount, uint256 limit);

    /**
     * @notice A hook adjusted amount in or out has exceeded the limit specified in the swap request.
     * @param amount The total amount in or out
     * @param limit The amount of the limit that has been exceeded
     */
    error HookAdjustedSwapLimit(uint256 amount, uint256 limit);

    /// @notice The amount given or calculated for an operation is below the minimum limit.
    error TradeAmountTooSmall();

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
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        );

    function getStaticSwapFeePercentage(address pool) external view returns (uint256 swapFeePercentage);
    function getHooksConfig(address pool) external view returns (HooksConfig memory hooksConfig);

    function areBuffersPaused() external view returns (bool);
    function getBufferBalance(address wrappedToken)
        external
        view
        returns (uint256 underlyingBalanceRaw, uint256 wrappedBalanceRaw);
    function isERC4626BufferInitialized(address wrappedToken) external view returns (bool);
}