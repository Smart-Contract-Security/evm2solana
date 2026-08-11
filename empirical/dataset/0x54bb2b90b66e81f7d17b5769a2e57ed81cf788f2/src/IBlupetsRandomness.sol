// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlupetsRandomness {
    function requestRandomWords() external returns (uint256 requestId);
}
