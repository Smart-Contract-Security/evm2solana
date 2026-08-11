// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Return type of the beforeSwap hook.
// Upper 128 bits is the delta in specified tokens. Lower 128 bits is delta in unspecified tokens (to match the afterSwap hook)
type BeforeSwapDelta is int256;

// Creates a BeforeSwapDelta from specified and unspecified
function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified)
    pure
    returns (BeforeSwapDelta beforeSwapDelta)
{
    // Solang does not support inline assembly, so we use pure Solidity bitwise operations.
    // Upper 128 bits: deltaSpecified, Lower 128 bits: deltaUnspecified.
    // We need to cast to int256 and shift.
    int256 upper = int256(deltaSpecified) << 128;
    // Mask to clear upper 128 bits of deltaUnspecified, then sign extend to int256.
    // Since int128 is already sign-extended when cast to int256, we just need to clear upper bits.
    int256 lower = int256(deltaUnspecified) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    beforeSwapDelta = BeforeSwapDelta.wrap(upper | lower);
}

/// @notice Library for getting the specified and unspecified deltas from the BeforeSwapDelta type
library BeforeSwapDeltaLibrary {
    /// @notice A BeforeSwapDelta of 0
    BeforeSwapDelta public constant ZERO_DELTA = BeforeSwapDelta.wrap(0);

    /// extracts int128 from the upper 128 bits of the BeforeSwapDelta
    /// returned by beforeSwap
    function getSpecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaSpecified) {
        // Arithmetic shift right by 128 bits to preserve sign.
        int256 val = BeforeSwapDelta.unwrap(delta);
        deltaSpecified = int128(val >> 128);
    }

    /// extracts int128 from the lower 128 bits of the BeforeSwapDelta
    /// returned by beforeSwap and afterSwap
    function getUnspecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaUnspecified) {
        // Mask lower 128 bits and sign extend.
        int256 val = BeforeSwapDelta.unwrap(delta);
        // Clear upper 128 bits
        int256 lower = val & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        // Sign extend from 128 bits to 256 bits
        // If the 128th bit (sign bit of int128) is set, we need to set all upper bits.
        if (lower & 0x80000000000000000000000000000000 != 0) {
            lower = lower | int256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000);
        }
        deltaUnspecified = int128(lower);
    }
}