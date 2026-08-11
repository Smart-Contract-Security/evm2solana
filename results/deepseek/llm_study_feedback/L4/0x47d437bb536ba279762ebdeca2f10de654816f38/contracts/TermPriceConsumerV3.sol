//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {ITermEventEmitter} from "./interfaces/ITermEventEmitter.sol";
import {Collateral} from "./lib/Collateral.sol";
import {ExponentialNoError} from "./lib/ExponentialNoError.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// ========================================================================
// = Interfaces (inlined from missing imports) ============================
// ========================================================================

interface ITermPriceOracle {
    function usdValueOfTokens(address token, uint256 amount) external view returns (uint256 mantissa);
}

interface ITermPriceOracleErrors {
    // Custom errors are not supported on Solana, replaced with string-based reverts
}

interface ITermPriceOracleEvents {
    event SubscribePriceFeed(address indexed token, address indexed priceFeed);
    event UnsubscribePriceFeed(address indexed token);
    event SubscribeFallbackPriceFeed(address indexed token, address indexed priceFeed);
    event UnsubscribeFallbackPriceFeed(address indexed token);
}

// ========================================================================
// = Structs (inlined from missing imports) ===============================
// ========================================================================

struct TermPriceFeedConfig {
    address priceFeed;
    uint256 refreshRateThreshold;
}

// ========================================================================
// = Versionable (inlined from missing import) ============================
// ========================================================================

contract Versionable {
    string public constant VERSION = "3.0.0";
}

/// @author TermLabs
/// @title Term Price Consumer V3
/// @notice This contract is a centralized price oracle contract that feeds pricing data to all Term Repos
/// @dev This contract operates at the protocol level and governs all instances of a Term Repo
contract TermPriceConsumerV3 is
    ITermPriceOracle,
    ITermPriceOracleErrors,
    ITermPriceOracleEvents,
    ExponentialNoError,
    Versionable
{
    // ========================================================================
    // = Access Roles  ========================================================
    // ========================================================================

    bytes32 public constant DEVOPS_ROLE = keccak256("DEVOPS_ROLE");

    uint256 public constant DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS = 60;

    // ========================================================================
    // = State Variables  =====================================================
    // ========================================================================

    mapping(address => TermPriceFeedConfig) internal priceFeeds;
    mapping(address => TermPriceFeedConfig) internal fallbackPriceFeeds;

    address private _owner;

    // ========================================================================
    // = Modifiers ============================================================
    // ========================================================================

    modifier onlyRole(bytes32 role) {
        require(role == DEVOPS_ROLE, "Invalid role");
        require(tx.origin == _owner, "Caller is not the owner");
        _;
    }

    modifier initializer() {
        require(_owner == address(0), "Already initialized");
        _;
    }

    // ========================================================================
    // = Deploy  ==============================================================
    // ========================================================================

    /// @notice Intializes with an array of token addresses, followed with an array of Chainlink aggregator addresses
    /// @notice https://docs.chain.link/docs/ethereum-addresses/
    function initialize(address devopsWallet_) external initializer {
        _owner = devopsWallet_;
    }

    // ========================================================================
    // = Interface/API ========================================================
    // ========================================================================

    /// @notice A function to return current market value given a token address and an amount
    /// @param token The address of the token to query
    /// @param amount The amount tokens to value
    /// @return The current market value of tokens at the specified amount, in USD
    function usdValueOfTokens(
        address token,
        uint256 amount
    ) external view returns (uint256 mantissa) {
        if (priceFeeds[token].priceFeed == address(0)) {
            revert("NoPriceFeed");
        }
        int256 latestPriceInt;
        uint8 priceDecimals;
        (latestPriceInt, priceDecimals) = _getLatestPrice(token);
        uint256 latestPrice = uint256(latestPriceInt);

        IERC20Metadata tokenInstance = IERC20Metadata(token);
        uint8 tokenDecimals = tokenInstance.decimals();

        return
            mul_(
                Exp({mantissa: (amount * expScale) / 10 ** tokenDecimals}),
                Exp({mantissa: (latestPrice * expScale) / 10 ** priceDecimals})
            ).mantissa;
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
        uint256 tokenPriceAggregatorRefreshRateThreshold,
        address fallbackPriceAggregator,
        uint256 fallbackPriceAggregatorRefreshRateThreshold
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
        uint256 refreshRateThreshold
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
        uint256 refreshRateThreshold
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
        uint256 refreshRateThreshold
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
        uint256 refreshRateThreshold
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
        uint256 refreshRateThreshold
    ) internal {
        require(
            tokenPriceAggregator != address(0),
            "Primary Price feed cannot be zero address"
        );
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            tokenPriceAggregator
        );

        // (uint80 roundID, int256 price, uint startedAt, uint timeStamp, uint80 answeredInRound)
        (, int256 price, , , ) = priceFeed.latestRoundData();

        if (price <= 0) {
            revert("InvalidPrice");
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
        uint256 refreshRateThreshold
    ) internal {
        require(
            tokenPriceAggregator != address(0),
            "Fallback Price feed cannot be zero address"
        );
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            tokenPriceAggregator
        );

        // (uint80 roundID, int256 price, uint startedAt, uint timeStamp, uint80 answeredInRound)
        (, int256 price, , , ) = priceFeed.latestRoundData();

        if (price <= 0) {
            revert("InvalidPrice");
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
    ) internal view returns (int256 latestPrice, uint8 decimals) {
        AggregatorV3Interface primaryFeed = AggregatorV3Interface(priceFeeds[token].priceFeed);
        (
            ,
            // uint80 roundID
            int256 price, // uint startedAt // //uint timeStamp// //uint80 answeredInRound//
            ,
            uint256 lastUpdatedTimestamp,

        ) = primaryFeed.latestRoundData();

        address fallbackPriceFeedAddr = fallbackPriceFeeds[token]
            .priceFeed;

        if (fallbackPriceFeedAddr == address(0)) {
            if (price <= 0) {
                revert("InvalidPrice");
            } else if (lastUpdatedTimestamp > block.timestamp + DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS) {
                revert("InvalidUpdateTimestamp");
            } else if (
                priceFeeds[token].refreshRateThreshold == 0 ||
                (lastUpdatedTimestamp > block.timestamp) ||
                (block.timestamp - lastUpdatedTimestamp) <= priceFeeds[token].refreshRateThreshold
            ) {
                return (price, primaryFeed.decimals()); // Use primary price feed if there is no fallback price feed and update within refresh rate.
            } else {
                revert("PricesStale"); // Price is stale if outside of refresh rate.
            }
        }
        if (fallbackPriceFeedAddr != address(0)) {
            if (
                price > 0 && lastUpdatedTimestamp <= block.timestamp + DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS &&
                ((lastUpdatedTimestamp > block.timestamp) ||
                 (block.timestamp - lastUpdatedTimestamp) <= priceFeeds[token].refreshRateThreshold)
            ) {
                return (price, primaryFeed.decimals()); // Return primary price feed if it is not stale
            }

            AggregatorV3Interface fallbackFeed = AggregatorV3Interface(fallbackPriceFeedAddr);
            (
                ,
                int256 fallbackPrice,
                ,
                uint256 fallbackLastUpdatedTimestamp,

            ) = fallbackFeed.latestRoundData();

            if (fallbackPrice <= 0) {
                revert("InvalidPrice");
            } else if (fallbackLastUpdatedTimestamp > block.timestamp + DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS) {
                revert("InvalidUpdateTimestamp");
            } else if (
                fallbackPriceFeeds[token].refreshRateThreshold == 0 ||
                (fallbackLastUpdatedTimestamp > block.timestamp) ||
                (block.timestamp - fallbackLastUpdatedTimestamp) <= fallbackPriceFeeds[token].refreshRateThreshold
            ) {
                return (fallbackPrice, fallbackFeed.decimals()); // Use fallback price feed if primary price feed unavailable
            } else {
                revert("PricesStale");
            }
        }
    }
}