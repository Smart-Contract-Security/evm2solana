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
    // We need to cast to int256 and shift/combine.
    int256 specifiedPart = int256(deltaSpecified) << 128;
    // Mask to clear upper 128 bits of unspecified, then sign extend to int256
    int256 unspecifiedPart = int256(deltaUnspecified) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    beforeSwapDelta = BeforeSwapDelta.wrap(specifiedPart | unspecifiedPart);
}

/// @notice Library for getting the specified and unspecified deltas from the BeforeSwapDelta type
library BeforeSwapDeltaLibrary {
    /// @notice A BeforeSwapDelta of 0
    BeforeSwapDelta public constant ZERO_DELTA = BeforeSwapDelta.wrap(0);

    /// extracts int128 from the upper 128 bits of the BeforeSwapDelta
    /// returned by beforeSwap
    function getSpecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaSpecified) {
        // Arithmetic shift right by 128 bits to preserve sign of upper 128 bits
        int256 full = BeforeSwapDelta.unwrap(delta);
        deltaSpecified = int128(full >> 128);
    }

    /// extracts int128 from the lower 128 bits of the BeforeSwapDelta
    /// returned by beforeSwap and afterSwap
    function getUnspecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaUnspecified) {
        // Mask lower 128 bits and sign extend to int128
        int256 full = BeforeSwapDelta.unwrap(delta);
        int256 masked = full & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        // Sign extend from 128 bits to 256 bits, then cast to int128
        // If the 128th bit (bit 127) is set, we need to set all upper bits.
        // We can do this by shifting left to the top, then arithmetic shift right.
        int256 signExtended = (masked << 128) >> 128;
        deltaUnspecified = int128(signExtended);
    }
}