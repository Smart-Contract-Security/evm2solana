// SPDX-License-Identifier: MIT

// Return type of the beforeSwap hook.
// Upper 128 bits is the delta in specified tokens. Lower 128 bits is delta in unspecified tokens (to match the afterSwap hook)
type BeforeSwapDelta is int256;

// Creates a BeforeSwapDelta from specified and unspecified
function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified)
    pure
    returns (BeforeSwapDelta beforeSwapDelta)
{
    // On Solana, we use explicit bitwise operations instead of Yul assembly
    int256 specifiedPart = int256(deltaSpecified) << 128;
    int256 unspecifiedPart = int256(deltaUnspecified) & int256(type(int128).max);
    beforeSwapDelta = BeforeSwapDelta.wrap(specifiedPart | unspecifiedPart);
}

/// @notice Library for getting the specified and unspecified deltas from the BeforeSwapDelta type
library BeforeSwapDeltaLibrary {
    /// @notice A BeforeSwapDelta of 0
    BeforeSwapDelta public constant ZERO_DELTA = BeforeSwapDelta.wrap(0);

    /// extracts int128 from the upper 128 bits of the BeforeSwapDelta
    /// returned by beforeSwap
    function getSpecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaSpecified) {
        // On Solana, use explicit shift instead of Yul assembly
        deltaSpecified = int128(int256(BeforeSwapDelta.unwrap(delta)) >> 128);
    }

    /// extracts int128 from the lower 128 bits of the BeforeSwapDelta
    /// returned by beforeSwap and afterSwap
    function getUnspecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaUnspecified) {
        // On Solana, use explicit masking instead of Yul assembly signextend
        int256 value = BeforeSwapDelta.unwrap(delta);
        // Mask to get lower 128 bits and sign-extend manually
        int128 masked = int128(value & int256(type(int128).max));
        // Check if the 128th bit is set (negative in int128)
        if (value & (int256(1) << 127) != 0) {
            deltaUnspecified = masked | int128(type(int128).min);
        } else {
            deltaUnspecified = masked;
        }
    }
}