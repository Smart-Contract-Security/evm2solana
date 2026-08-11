// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ErrorsLib
/// @notice Aave V3 Adapter error message library
library ErrorsLib {
    /// @notice Invalid address
    string internal constant INVALID_ADDRESS = "Invalid address";

    /// @notice Already registered
    string internal constant ALREADY_REGISTERED = "Already registered";

    /// @notice Already set
    string internal constant ALREADY_SET = "Already set";

    /// @notice Array length mismatch
    string internal constant LENGTH_MISMATCH = "Length mismatch";

    /// @notice Pool not found
    string internal constant POOL_NOT_FOUND = "Pool not found";

    /// @notice Pool already exists
    string internal constant POOL_ALREADY_EXISTS = "Pool already exists";

    string internal constant INVALID_POOL_TYPE = "Invalid pool type";

    string internal constant LENGTH_EXCEEDS_LIMIT = "Length exceeds limit";

    /// @notice Invalid protocol name
    string internal constant INVALID_PROTOCOL_NAME = "Invalid protocol name";

    /// @notice Protocol exists
    string internal constant PROTOCOL_EXISTS = "Protocol exists";

    /// @notice Protocol not found
    string internal constant PROTOCOL_NOT_FOUND = "Protocol not found";

    /// @notice Adapter disabled
    string internal constant ADAPTER_DISABLED = "Adapter disabled";

    /// @notice Protocol name mismatch between old and new adapter
    string internal constant PROTOCOL_NAME_MISMATCH = "Protocol name mismatch";

    string internal constant TOKEN_NOT_OWNED_BY_USER = "Token not owned by user";

    /// @notice Deposit token already exists
    string internal constant TOKEN_ALREADY_EXISTS = "Token already exists";

    /// @notice Deposit token not found
    string internal constant TOKEN_NOT_FOUND = "Token not found";
}

