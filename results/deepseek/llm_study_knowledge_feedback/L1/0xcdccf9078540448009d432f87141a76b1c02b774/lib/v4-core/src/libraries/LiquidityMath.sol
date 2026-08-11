// SPDX-License-Identifier: MIT

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        // Manual implementation without assembly since Yul builtins are unavailable on Solana
        // signextend is not available, so we manually handle the sign extension
        int256 extendedY = int256(y);
        int256 result = int256(uint256(x)) + extendedY;
        
        // Check for overflow/underflow
        if (result < 0 || result > int256(type(uint128).max)) {
            // revert SafeCastOverflow()
            revert();
        }
        
        z = uint128(uint256(result));
    }
}