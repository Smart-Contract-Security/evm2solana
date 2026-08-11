// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface that escrow clones use to verify their factory's
///         compliance officer allowlist. The factory implements this.
interface IComplianceRegistry {
    function isCompliance(address officer) external view returns (bool);
}
