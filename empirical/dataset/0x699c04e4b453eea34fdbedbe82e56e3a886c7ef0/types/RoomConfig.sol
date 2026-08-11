// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Room archetype / template. Stored by index in MiningEthSystem.
struct RoomConfig {
    uint8 maxMiners;
    uint32 totalPowerOutput;
    uint256 cost;        // dMETH cost. Room 1 is purchased in ETH via initialRoomPrice; its cost field is 0.
    bool inProduction;
    uint8 gridRows;
    uint8 gridCols;
    uint64 cooldown;     // seconds; enforced before upgrading INTO this room
}
