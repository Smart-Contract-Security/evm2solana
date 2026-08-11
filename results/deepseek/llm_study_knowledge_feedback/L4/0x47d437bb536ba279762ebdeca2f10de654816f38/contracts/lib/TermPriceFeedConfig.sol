//SPDX-License-Identifier: CC-BY-NC-ND-4.0

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint64);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint64 startedAt, uint64 updatedAt, uint80 answeredInRound);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint64 startedAt, uint64 updatedAt, uint80 answeredInRound);
}

/// @dev TermPriceFeedConfig represents the price feed contracts and the
struct TermPriceFeedConfig {
    /// @dev The price feed aggregator address
    address priceFeed;
    /// @dev Price Feed oracle refresh rate before determined to be stale
    uint64 refreshRateThreshold;
}