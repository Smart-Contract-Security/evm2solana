// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ProtocolPhase} from "./ProtocolPhase.sol";

/// @title IProtocolRegistry
/// @notice Read-side interface every other module imports.
interface IProtocolRegistry {
    function phase() external view returns (ProtocolPhase.Phase);
    function isAtOrAfter(ProtocolPhase.Phase p) external view returns (bool);
    function isBefore(ProtocolPhase.Phase p) external view returns (bool);

    // Canonical module addresses — set once by the registry owner during
    // deployment. Other modules read these to authorize cross-module calls
    // ("mint may only be called by PackSale", etc.).
    function packSale() external view returns (address);
    function entropy() external view returns (address);
    function hatCard() external view returns (address);
    function hatToken() external view returns (address);
    function hatTrickHook() external view returns (address);
    function prizeVault() external view returns (address);
    function matchOracle() external view returns (address);
    function scoringEngine() external view returns (address);
    function treasury() external view returns (address);
}