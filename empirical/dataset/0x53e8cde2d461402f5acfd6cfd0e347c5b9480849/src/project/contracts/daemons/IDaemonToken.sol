// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDaemonToken {
    function UNIT_PER_DMN() external view returns (uint256);
    function activePoolId() external view returns (bytes32);
    function objectSeed(uint256 objectId) external view returns (uint256);
    function objectTraitWord(uint256 objectId) external view returns (uint256);
    function objectOriginSwapBlock(uint256 objectId) external view returns (uint256);
    function suspendedObjectCount(address account) external view returns (uint256);
    function currentCorruptionSnapshot() external view returns (bytes32 poolId, bytes32 state, uint64 epoch);
    function transferDmnFrom(address from, address to, uint256 objectId) external;
    function redeemWrappedObject(address to, uint256 objectId)
        external
        returns (uint256 payoutAmount, uint256 feeAmount, uint256 spawnedObjectId);
    function registerMintContext(
        address recipient,
        uint256 daemonAmount,
        uint256 maxObjects,
        bytes32 poolId,
        bytes32 state
    ) external;
    function setActivePoolId(bytes32 poolId) external;
    function sealTraitEntropy(bytes32 poolId, bytes32 state) external;
    function sacrificeObjectsForUpgrade(address from, uint256[] calldata objectIds) external;
}
