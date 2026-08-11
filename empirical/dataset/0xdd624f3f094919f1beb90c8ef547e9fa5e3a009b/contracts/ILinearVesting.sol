// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {UserAllocation} from "contracts/LinearVestingStruct.sol";

interface ILinearVesting {
    /**
     * @notice Update the merkle root and vesting period.
     * @param merkleRoot_ New merkle root.
     * @param startTime_ New start time. Can be set in past as we need such purpose, e.g. contract is 
     *                   NOT deployed whereas the vesting period should have already started.
     * @param endTime_ New end time.
     * @param toClaim Amount of tokens to lock for claiming. If it's zero, tokens won't be transferred to the contract.
     */
    function update(
        bytes32 merkleRoot_,
        uint32 startTime_,
        uint32 endTime_,
        uint256 toClaim
    ) external returns (bool);

    /**
     * @notice Claim tokens for a user.
     * @param alloc User allocation.
     * @param proof Merkle proof.
     */
    function claim(
        UserAllocation calldata alloc,
        bytes32[] calldata proof
    ) external returns (bool);

    /**
     * @notice Get the claimable amount for a user.
     * @param alloc User allocation.
     */
    function getClaimableAmount(
        UserAllocation calldata alloc
    ) external view returns (uint256 claimableAmount);

    function totalVested() external view returns (uint256);

    function totalClaimed() external view returns (uint256);

    function merkleRoot() external view returns (bytes32);

    function startTime() external view returns (uint32);

    function endTime() external view returns (uint32);

    function userClaims(address) external view returns (uint256);
}
