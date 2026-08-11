// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Counter {
    function vulnerable(uint256 x) external {
        require(0 <= x, "hehe");
    }
}
