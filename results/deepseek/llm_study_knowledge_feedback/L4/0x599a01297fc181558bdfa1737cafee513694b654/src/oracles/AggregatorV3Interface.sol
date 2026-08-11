// SPDX-License-Identifier: BSD-3-Clause

/**
 * @title The V2 & V3 Aggregator Interface
 * @notice Solidity V0.5 does not allow interfaces to inherit from other
 * interfaces so this contract is a combination of v0.5 AggregatorInterface.sol
 * and v0.5 AggregatorV3Interface.sol.
 */
interface AggregatorV3Interface {
    //
    // V3 Interface:
    //
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint64);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint64 _roundId
    )
        external
        view
        returns (
            uint64 roundId,
            int64 answer,
            uint64 startedAt,
            uint64 updatedAt,
            uint64 answeredInRound
        );
    function latestRoundData()
        external
        view
        returns (
            uint64 roundId,
            int64 answer,
            uint64 startedAt,
            uint64 updatedAt,
            uint64 answeredInRound
        );

    function latestRound() external view returns (uint64);
}