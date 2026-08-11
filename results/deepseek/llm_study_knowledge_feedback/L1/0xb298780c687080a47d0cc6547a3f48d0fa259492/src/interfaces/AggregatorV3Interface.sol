// SPDX-License-Identifier: MIT

import 'solana';

/// @dev From
/// https://github.com/smartcontractkit/chainlink/blob/master/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint64);

    function getRoundData(uint64 _roundId)
        external
        view
        returns (uint64 roundId, int64 answer, uint64 startedAt, uint64 updatedAt, uint64 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint64 roundId, int64 answer, uint64 startedAt, uint64 updatedAt, uint64 answeredInRound);
}