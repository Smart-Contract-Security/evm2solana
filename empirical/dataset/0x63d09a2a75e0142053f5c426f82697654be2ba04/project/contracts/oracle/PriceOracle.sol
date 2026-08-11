// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title PriceOracle
 * @notice Converts a fixed USD amount ($0.20) to ETH wei using Chainlink ETH/USD feed.
 *
 * @dev The stamp fee is always $0.20 USD regardless of ETH price.
 *      Uses Chainlink's AggregatorV3Interface to get the latest ETH/USD price.
 *
 *      Staleness protection: if the Chainlink price is older than 1 hour,
 *      falls back to a hardcoded max fee (0.0005 ETH ≈ $1 at ETH=$2000).
 *      This prevents stamps from halting during network congestion.
 *
 *      The oracle is immutable after deployment — no admin can change the
 *      price feed address or fee amount.
 */
contract PriceOracle {
    /// @notice Chainlink ETH/USD price feed
    IAggregatorV3 public immutable priceFeed;

    /// @notice Target fee in USD cents (20 = $0.20)
    uint256 public constant TARGET_USD_CENTS = 20;

    /// @notice Maximum staleness for Chainlink data (1 hour)
    uint256 public constant MAX_STALENESS = 1 hours;

    /// @notice Fallback fee if Chainlink is stale or unavailable
    uint256 public constant FALLBACK_FEE = 0.0005 ether;

    error StalePrice();

    constructor(address _priceFeed) {
        priceFeed = IAggregatorV3(_priceFeed);
    }

    /**
     * @notice Get the stamp fee in wei for $0.20 USD.
     * @dev Chainlink ETH/USD returns price with 8 decimals.
     *      Example: ETH=$2000 → price=200000000000
     *
     *      Formula: fee = (TARGET_USD_CENTS * 1e24) / uint256(price)
     *
     *      Derivation:
     *        $0.20 / $2000 = 0.0001 ETH = 1e14 wei
     *        (20 * 1e24) / 200000000000 = 2e25 / 2e11 = 1e14 ✓
     *
     *      At ETH=$4000: (20 * 1e24) / 400000000000 = 5e13 = 0.00005 ETH ✓
     *
     * @return fee The stamp fee in wei.
     */
    function getStampFee() external view returns (uint256 fee) {
        try priceFeed.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (block.timestamp - updatedAt > MAX_STALENESS) {
                return FALLBACK_FEE;
            }
            if (price <= 0) {
                return FALLBACK_FEE;
            }

            fee = (TARGET_USD_CENTS * 1e24) / uint256(price);
        } catch {
            fee = FALLBACK_FEE;
        }
    }
}

/**
 * Minimal Chainlink AggregatorV3 interface.
 * Defined inline to avoid adding chainlink/contracts as a dependency.
 */
interface IAggregatorV3 {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
