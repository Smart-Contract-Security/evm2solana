// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title EventsLib
/// @notice Events for LSD Router
library EventsLib {
    event AdapterRegistered(address indexed lsd, address indexed adapter);
    event AdapterRemoved(address indexed lsd, address indexed adapter);
    event AdapterToggled(address indexed lsd, bool enabled);
    event AdapterPaused(address indexed adapter);
    event AdapterUnpaused(address indexed adapter);
}
