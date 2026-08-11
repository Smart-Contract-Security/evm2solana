// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Miner {
    uint8 minerIndex;
    uint8 x;
    uint8 y;
    uint32 id;
    uint32 hashrate;
    uint32 powerConsumption;
    uint256 cost;
    bool inProduction;
} 