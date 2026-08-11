// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Per-wallet active room state.
struct Room {
    uint8 roomIndex;
    uint8 maxMiners;
    uint32 totalPowerOutput;
    uint8 currMiners;
    uint32 currPowerOutput;
    uint8 gridRows;
    uint8 gridCols;
}
