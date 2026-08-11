// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

interface IBronToken {
    // Add any required interface functions here if needed
    // For now, leaving it empty as the original interface is not provided
}

abstract contract BronTokenStorage is IBronToken {
    // ------------------------------
    // Constants
    // ------------------------------

    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 ether;

    // ------------------------------
    // State variables
    // ------------------------------

    mapping(address => uint256) public lockedTokens;

    address public multisig;
    address public bronDao;

    address public oftContract;

    mapping(address => uint256) public loyaltyLockedTokens;
    address public loyaltyProgramContract;

    // Checkpoints.Trace208 replaced with manual storage
    mapping(address => mapping(uint32 => uint208)) internal votesCheckpoints;
    mapping(address => uint32) internal votesCheckpointLengths;

    mapping(uint32 => uint208) internal totalCheckpoints;
    uint32 internal totalCheckpointsLength;

    mapping(address => bool) public votesSynced;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;

    // Helper functions to replace Checkpoints.Trace208 functionality
    function _pushVotesCheckpoint(address account, uint32 key, uint208 value) internal {
        uint32 len = votesCheckpointLengths[account];
        votesCheckpoints[account][len] = value;
        votesCheckpointLengths[account] = len + 1;
    }

    function _latestVotesCheckpoint(address account) internal view returns (uint208) {
        uint32 len = votesCheckpointLengths[account];
        if (len == 0) return 0;
        return votesCheckpoints[account][len - 1];
    }

    function _pushTotalCheckpoint(uint32 key, uint208 value) internal {
        totalCheckpoints[totalCheckpointsLength] = value;
        totalCheckpointsLength++;
    }

    function _latestTotalCheckpoint() internal view returns (uint208) {
        if (totalCheckpointsLength == 0) return 0;
        return totalCheckpoints[totalCheckpointsLength - 1];
    }
}