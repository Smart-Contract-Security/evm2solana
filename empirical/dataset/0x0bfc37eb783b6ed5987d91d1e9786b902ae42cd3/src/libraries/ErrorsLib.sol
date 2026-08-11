// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ErrorsLib
/// @notice Common error strings for LSD Router
library ErrorsLib {
    string internal constant INVALID_ADDRESS = "Invalid address";
    string internal constant ALREADY_REGISTERED = "Already registered";
    string internal constant ALREADY_SET = "Already set";
    string internal constant LENGTH_MISMATCH = "Length mismatch";
    string internal constant LSD_NOT_REGISTERED = "LSD not registered";

    string internal constant ADAPTER_DISABLED = "Adapter disabled";
    string internal constant ADAPTER_CALL_FAILED = "Adapter call failed";
    string internal constant RECURSION_LOOP = "Recursion loop";
}
