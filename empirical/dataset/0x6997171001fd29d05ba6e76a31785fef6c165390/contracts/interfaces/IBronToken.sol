// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

interface IBronToken {

    function loyaltyLock(address account, uint256 value) external;

    function loyaltyUnlock(address account, uint256 value) external;

    function availableBalanceOf(address account) external view returns (uint256);

    function loyaltyLockedBalanceOf(address account) external view returns (uint256);

}
