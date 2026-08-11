// SPDX-License-Identifier: GPL-2.0-or-later

/// @title Errors
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Collects common errors in PriceOracles.
library Errors {
    /// @notice The external feed returned an invalid answer.
    uint64 constant PriceOracle_InvalidAnswer = 1;
    /// @notice The configuration parameters for the PriceOracle are invalid.
    uint64 constant PriceOracle_InvalidConfiguration = 2;
    /// @notice The base/quote path is not supported.
    uint64 constant PriceOracle_NotSupported = 3;
    /// @notice The quote cannot be completed due to overflow.
    uint64 constant PriceOracle_Overflow = 4;
    /// @notice The price is too stale.
    uint64 constant PriceOracle_TooStale = 5;
    /// @notice The method can only be called by the governor.
    uint64 constant Governance_CallerNotGovernor = 6;
}