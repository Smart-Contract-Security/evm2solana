// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MatchTypes} from "./MatchTypes.sol";

interface IMatchOracle {
    function phaseOf(uint256 matchId) external view returns (MatchTypes.Phase);
    function statOf(uint256 matchId, uint16 playerId, MatchTypes.Stat stat) external view returns (uint32);
    function playersInMatch(uint256 matchId) external view returns (uint16[] memory);
    function disputeDeadline(uint256 matchId) external view returns (uint64);
}
