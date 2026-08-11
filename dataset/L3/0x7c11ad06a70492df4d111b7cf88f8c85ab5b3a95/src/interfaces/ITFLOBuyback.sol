// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITFLOBuyback {
    function buyAndBurn(uint128 minOut) external payable;
}
