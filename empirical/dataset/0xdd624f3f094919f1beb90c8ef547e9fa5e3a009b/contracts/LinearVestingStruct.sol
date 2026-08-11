// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/** @title UserAllocation is used to claim the user's allocation
 * @param user is the address of the user
 * @param amount is the total amount of tokens to claim
 * @param startAmount is the amount of tokens available at TGE
 */
struct UserAllocation {
    address user;
    uint256 amount;
    uint256 startAmount;
}
