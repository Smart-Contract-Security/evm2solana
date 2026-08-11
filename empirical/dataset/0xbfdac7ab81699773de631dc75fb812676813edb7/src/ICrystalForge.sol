// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ICrystalForge {
    function totalPower() external view returns (uint256);
    function notifyReward(uint256 amount) external;
}
