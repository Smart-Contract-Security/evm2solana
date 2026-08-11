// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IUserManager {
    struct UserOneTimeFee {
        uint256 feeAmount; // The one-time fee for the user
        bool completeStatus; // Status whether the one-time fee has been completed
    }

    function userOneTimeFee(
        address userAddress
    ) external view returns (UserOneTimeFee memory);

    function oneTimeFee() external view returns (uint256);
}
