// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.16;

/**
 * @dev Interface of Staking Amounts .
 */
interface IStakingAmounts {
    /**
     * @dev Returns the total staked amount for a user
     * @param _user Address of the user
     * @return uint256 Total staked amount for the user
     *
     */
    function stakedOf(address _user) external view returns (uint256);

    /**
     * @dev Returns the total staked amount for all users
     * @return uint256 Total staked amount for all users
     *
     */
    function totalStaked() external view returns (uint256);
}