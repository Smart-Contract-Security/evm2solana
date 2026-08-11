// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IVToken {
    function underlying() external view returns (address);
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
}

interface ICTokenAdapter {}
