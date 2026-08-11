// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Read-only holder-accounting surface used when reserving holder reward WETH.
interface IHolderAccounting {
    enum HolderContextStatus {
        Invalid,
        Potential,
        Candidate,
        Closed,
        Discarded
    }

    struct HolderContext {
        HolderContextStatus status;
        uint64 epochId;
        uint48 snapshotBlock;
        uint64 snapshotTimestamp;
        uint48 openBlock;
        uint256 openSeq;
        uint64 expiresAtEpochId;
        uint64 confirmationEpochId;
        uint64 cutoffTimestamp;
        uint256 processingSeq;
        uint256 finalDisqualifiedWeight;
    }

    function firstHeldBlock(address account) external view returns (uint64);
    function holderContext(uint256 contextId) external view returns (HolderContext memory);
    function accountWeightAtSnapshot(address account, uint48 snapshotBlock, uint64 snapshotTimestamp)
        external
        view
        returns (uint256);
    function globalWeightAtSnapshot(uint48 snapshotBlock, uint64 snapshotTimestamp) external view returns (uint256);
    function isAccountDisqualifiedForConfirmation(address account, uint256 contextId, uint256 confirmationEpochId)
        external
        view
        returns (bool);
}
