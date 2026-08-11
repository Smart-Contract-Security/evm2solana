// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDeFiAdapter} from "../interfaces/IDeFiAdapter.sol";

/// @title EventsLib
/// @notice Aave V3 Adapter event library
library EventsLib {
    /// @notice Adapter registered event
    event AdapterRegistered(address indexed adapter, string protocolName, IDeFiAdapter.ProtocolType protocolType);

    /// @notice Adapter removed event
    event AdapterRemoved(address indexed adapter);

    /// @notice Adapter enabled/disabled event
    event AdapterToggled(address indexed adapter, bool enabled);

    /// @notice Adapter updated event
    event AdapterUpdated(address indexed oldAdapter, address indexed newAdapter, string protocolName);

    /// @notice Pool added event
    /// @param poolId Pool unique identifier
    /// @param poolAddress Pool address
    /// @param poolType Pool type
    event PoolAdded(bytes32 indexed poolId, address indexed poolAddress, IDeFiAdapter.PoolType poolType);

    /// @notice Emitted when pool is removed
    /// @param poolId Pool unique identifier
    /// @param poolAddress Pool address
    /// @param poolType Pool type
    event PoolRemoved(bytes32 indexed poolId, address indexed poolAddress, IDeFiAdapter.PoolType poolType);

    /// @notice Emitted when pool is enabled or disabled
    /// @param poolId Pool unique identifier
    /// @param poolAddress Pool address
    /// @param enabled Whether enabled
    event PoolToggled(bytes32 indexed poolId, address indexed poolAddress, bool enabled);
}

