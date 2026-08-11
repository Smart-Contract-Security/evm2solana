// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Thin wrapper over OZ TimelockController used as the ParamManager
///         and Admin of the Stablehouse protocol.
///
/// V1 timelock durations (per PRD §16):
///   - Parameter changes: 24h
///   - Asset adds / contract upgrades: 48h
///   - (Guardian pause is immediate and bypasses this timelock entirely)
contract StablehouseTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,  // multisig address(es)
        address[] memory executors,  // typically [address(0)] for permissionless execution
        address admin                // address(0) to renounce admin after setup
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
