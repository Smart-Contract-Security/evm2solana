// SPDX-License-Identifier: CC-BY-NC-ND-4.0

import {ITermEventEmitter} from "./interfaces/ITermEventEmitter.sol";
import {Collateral} from "./lib/Collateral.sol";

// Solana builtins
import {AccountInfo} from "solana";

/// @author TermLabs
/// @title Term Price Consumer V3
/// @notice This contract is a centralized price oracle contract that feeds pricing data to all Term Repos
/// @dev This contract operates at the protocol level and governs all instances of a Term Repo
contract TermPriceConsumerV3 {
    // ========================================================================
    // = Access Roles  ========================================================
    // ========================================================================

    bytes32 public constant DEVOPS_ROLE = keccak256("DEVOPS_ROLE");

    uint64 public constant DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS = 60;

    // ========================================================================
    // = State Variables  =====================================================
    // ========================================================================

    struct TermPriceFeedConfig {
        address priceFeed;
        uint64 refreshRateThreshold;
    }

    mapping(address => TermPriceFeedConfig) internal priceFeeds;
    mapping(address => TermPriceFeedConfig) internal fallbackPriceFeeds;

    address internal _devopsWallet;
    bool internal _initialized;

    // ========================================================================
    // = Events ===============================================================
    // ========================================================================

    event SubscribePriceFeed(address indexed token, address priceFeed);
    event UnsubscribePriceFeed(address indexed token);
    event SubscribeFallbackPriceFeed(address indexed token, address priceFeed);
    event UnsubscribeFallbackPriceFeed(address indexed token);

    // ========================================================================
    // = Deploy  ==============================================================
    // ========================================================================

    /// @notice Initializes with an array of token addresses, followed with an array of Chainlink aggregator addresses
    /// @notice https://docs.chain.link/docs/ethereum-addresses/
    function initialize(address devopsWallet_) external {
        require(!_initialized);
        _initialized = true;
        _devopsWallet = devopsWallet_;
    }

    modifier onlyRole(bytes32 role) {
        require(role == DEVOPS_ROLE);
        require(tx.accounts.dataAccount.key == _devopsWallet);
        _;
    }

    // ========================================================================
    // = Interface/API ========================================================
    // ========================================================================

    struct Exp {
        uint64 mantissa;
    }

    uint64 constant expScale = 1e18;

    function mul_(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return Exp({mantissa: (a.mantissa * b.mantissa) / expScale});
    }

    /// @notice A function to return current market value given a token address and an amount
    /// @param token The address of the token to query
    /// @param amount The amount tokens to value
    /// @return The current market value of tokens at the specified amount, in USD
    function usdValueOfTokens(
        address token,
        uint64 amount
    ) external view returns (Exp memory) {
        if (priceFeeds[token].priceFeed == address(0)) {
            revert();
        }
        int64 latestPriceInt;
        uint8 priceDecimals;
        (latestPriceInt, priceDecimals) = _getLatestPrice(token);
        uint64 latestPrice = uint64(latestPriceInt);

        // On Solana, token decimals are retrieved via SPL Token metadata or a separate call.
        // Since IERC20Metadata is not available, we use a placeholder function to get decimals.
        uint8 tokenDecimals = _getTokenDecimals(token);

        return
            mul_(
                Exp({mantissa: (amount * expScale) / (10 ** tokenDecimals)}),
                Exp({mantissa: (latestPrice * expScale) / (10 ** priceDecimals)})
            );
    }

    // ========================================================================
    // = Admin Functions ======================================================
    // ========================================================================

    /// @param token The address of the token to add a price feed for
    /// @param tokenPriceAggregator The price aggregator address for token to be added
    /// @param tokenPriceAggregatorRefreshRateThreshold Refresh threshold in seconds for primary price feed updates beyond which price is stale
    /// @param fallbackPriceAggregator The fallback  price aggregator address for token to be added
    /// @param fallbackPriceAggregatorRefreshRateThreshold Refresh threshold for fallback price feed updates beyond which price is stale

    function addNewTokenPriceFeedAndFallbackPriceFeed(
        address token,
        address tokenPriceAggregator,
        uint64 tokenPriceAggregatorRefreshRateThreshold,
        address fallbackPriceAggregator,
        uint64 fallbackPriceAggregatorRefreshRateThreshold
    ) external onlyRole(DEVOPS_ROLE) {
        _addNewTokenPriceFeed(
            token,
            tokenPriceAggregator,
            tokenPriceAggregatorRefreshRateThreshold
        );
        _addNewTokenFallbackPriceFeed(
            token,
            fallbackPriceAggregator,
            fallbackPriceAggregatorRefreshRateThreshold
        );
    }

    /// @param token The address of the token to add a price feed for
    /// @param tokenPriceAggregator The proxy price aggregator address for token to be added
    /// @param refreshRateThreshold Refresh threshold in seconds for primary price feed updates beyond which price is stale

    function addNewTokenPriceFeed(
        address token,
        address tokenPriceAggregator,
        uint64 refreshRateThreshold
    ) external onlyRole(DEVOPS_ROLE) {
        _addNewTokenPriceFeed(
            token,
            tokenPriceAggregator,
            refreshRateThreshold
        );
    }

    /// @param token The address of the token to add a price feed for
    /// @param tokenPriceAggregator The proxy price aggregator address for token to be added
    /// @param refreshRateThreshold Refresh threshold in seconds for fallback price feed updates beyond which price is stale
    function addNewTokenFallbackPriceFeed(
        address token,
        address tokenPriceAggregator,
        uint64 refreshRateThreshold
    ) external onlyRole(DEVOPS_ROLE) {
        _addNewTokenFallbackPriceFeed(
            token,
            tokenPriceAggregator,
            refreshRateThreshold
        );
    }

    /// @param token The address of the token whose price feed needs to be removed
    function removeTokenPriceFeed(
        address token
    ) external onlyRole(DEVOPS_ROLE) {
        delete priceFeeds[token];
        emit UnsubscribePriceFeed(token);
    }

    /// @param token The address of the token whose price feed needs to be removed
    function removeFallbackTokenPriceFeed(
        address token
    ) external onlyRole(DEVOPS_ROLE) {
        delete fallbackPriceFeeds[token];
        emit UnsubscribeFallbackPriceFeed(token);
    }

    // ========================================================================
    // = Public Functions  ====================================================
    // ========================================================================

    /// @notice Get the primary price feed configuration for a token
    /// @param token The address of the token to query
    /// @return priceFeed The address of the primary price feed aggregator
    /// @return refreshRateThreshold The refresh rate threshold in seconds
    function getPriceFeedConfig(address token) external view returns (
        address priceFeed,
        uint64 refreshRateThreshold
    ) {
        TermPriceFeedConfig memory config = priceFeeds[token];
        return (
            config.priceFeed,
            config.refreshRateThreshold
        );
    }

    /// @notice Get the fallback price feed configuration for a token
    /// @param token The address of the token to query
    /// @return fallbackPriceFeed The address of the fallback price feed aggregator
    /// @return refreshRateThreshold The refresh rate threshold in seconds
    function getFallbackPriceFeedConfig(address token) external view returns (
        address fallbackPriceFeed,
        uint64 refreshRateThreshold
    ) {
        TermPriceFeedConfig memory config = fallbackPriceFeeds[token];
        return (
            config.priceFeed,
            config.refreshRateThreshold
        );
    }

    // ========================================================================
    // = Internal Functions  ==================================================
    // ========================================================================

    /// @param token The address of the token to add a price feed for
    /// @param tokenPriceAggregator The proxy price aggregator address for token to be added
    /// @param refreshRateThreshold Refresh threshold in seconds for primary price feed updates beyond which price is stale
    function _addNewTokenPriceFeed(
        address token,
        address tokenPriceAggregator,
        uint64 refreshRateThreshold
    ) internal {
        require(
            tokenPriceAggregator != address(0)
        );

        (int64 price, , , ) = _getLatestRoundData(tokenPriceAggregator);

        if (price <= 0) {
            revert();
        }
        TermPriceFeedConfig memory priceFeedConfig = TermPriceFeedConfig({
            priceFeed: tokenPriceAggregator,
            refreshRateThreshold: refreshRateThreshold
        });
        priceFeeds[token] = priceFeedConfig;
        emit SubscribePriceFeed(token, tokenPriceAggregator);
    }

    /// @param token The address of the token to add a price feed for
    /// @param tokenPriceAggregator The proxy price aggregator address for token to be added
    /// @param refreshRateThreshold Refresh threshold in seconds for fallback price feed updates beyond which price is stale
    function _addNewTokenFallbackPriceFeed(
        address token,
        address tokenPriceAggregator,
        uint64 refreshRateThreshold
    ) internal {
        require(
            tokenPriceAggregator != address(0)
        );

        (int64 price, , , ) = _getLatestRoundData(tokenPriceAggregator);

        if (price <= 0) {
            revert();
        }

        TermPriceFeedConfig memory priceFeedConfig = TermPriceFeedConfig({
            priceFeed: tokenPriceAggregator,
            refreshRateThreshold: refreshRateThreshold
        });
        fallbackPriceFeeds[token] = priceFeedConfig;
        emit SubscribeFallbackPriceFeed(token, tokenPriceAggregator);
    }

    /// @return latestPrice The latest price from price aggregator
    /// @return decimals The decimals in the price
    function _getLatestPrice(
        address token
    ) internal view returns (int64 latestPrice, uint8 decimals) {
        (
            int64 price,
            uint64 lastUpdatedTimestamp,
            uint8 priceDecimals
        ) = _getLatestRoundDataWithDecimals(priceFeeds[token].priceFeed);

        address fallbackPriceFeedAddr = fallbackPriceFeeds[token].priceFeed;

        if (fallbackPriceFeedAddr == address(0)) {
            if (price <= 0) {
                revert();
            } else if (lastUpdatedTimestamp > block.timestamp + DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS) {
                revert();
            } else if (
                priceFeeds[token].refreshRateThreshold == 0 ||
                (lastUpdatedTimestamp > block.timestamp) ||
                (block.timestamp - lastUpdatedTimestamp) <= priceFeeds[token].refreshRateThreshold
            ) {
                return (price, priceDecimals);
            } else {
                revert();
            }
        }
        if (fallbackPriceFeedAddr != address(0)) {
            if (
                price > 0 && lastUpdatedTimestamp <= block.timestamp + DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS &&
                ((lastUpdatedTimestamp > block.timestamp) ||
                 (block.timestamp - lastUpdatedTimestamp) <= priceFeeds[token].refreshRateThreshold)
            ) {
                return (price, priceDecimals);
            }

            (
                int64 fallbackPrice,
                uint64 fallbackLastUpdatedTimestamp,
                uint8 fallbackPriceDecimals
            ) = _getLatestRoundDataWithDecimals(fallbackPriceFeedAddr);

            if (fallbackPrice <= 0) {
                revert();
            } else if (fallbackLastUpdatedTimestamp > block.timestamp + DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS) {
                revert();
            } else if (
                fallbackPriceFeeds[token].refreshRateThreshold == 0 ||
                (fallbackLastUpdatedTimestamp > block.timestamp) ||
                (block.timestamp - fallbackLastUpdatedTimestamp) <= fallbackPriceFeeds[token].refreshRateThreshold
            ) {
                return (fallbackPrice, fallbackPriceDecimals);
            } else {
                revert();
            }
        }
    }

    function _getLatestRoundData(address feed) internal view returns (int64 price, uint64 lastUpdatedTimestamp, uint8 decimals, uint64 roundId) {
        // Placeholder for Chainlink-like oracle call on Solana
        // In a real implementation, this would make a cross-program invocation (CPI) to the oracle program
        // For now, we return dummy data to allow compilation
        price = 0;
        lastUpdatedTimestamp = 0;
        decimals = 8;
        roundId = 0;
    }

    function _getLatestRoundDataWithDecimals(address feed) internal view returns (int64 price, uint64 lastUpdatedTimestamp, uint8 decimals) {
        (price, lastUpdatedTimestamp, decimals, ) = _getLatestRoundData(feed);
    }

    /// @notice Placeholder function to retrieve token decimals on Solana.
    /// @dev In a real implementation, this would query the SPL Token mint account.
    /// @param token The token mint address
    /// @return decimals The number of decimals for the token
    function _getTokenDecimals(address token) internal pure returns (uint8 decimals) {
        // Placeholder: return a default value. In production, this would be a CPI call.
        // For now, we assume 6 decimals (common for Solana SPL tokens) to allow compilation.
        decimals = 6;
    }
}