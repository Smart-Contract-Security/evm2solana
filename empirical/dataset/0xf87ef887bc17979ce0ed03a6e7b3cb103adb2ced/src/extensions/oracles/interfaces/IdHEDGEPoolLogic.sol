// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IdHEDGEPoolLogic {
    function tokenPrice() external view returns (uint256 price);
}
