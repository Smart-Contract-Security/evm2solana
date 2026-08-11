// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Errors} from "./Errors.sol";

type Scale is uint256;

/// @title ScaleUtils
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Utilities for handling decimal conversion of unit price feeds.
library ScaleUtils {
    uint256 internal constant PRICE_SCALE_MASK = 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
    /// @notice The maximum allowed exponent for Scale components.
    /// @dev 38 is the largest integer exponent of 10 that fits in 128 bits.
    uint256 internal constant MAX_EXPONENT = 38;

    /// @notice Create a `Scale` by packing 2 powers of 10.
    /// @dev Upper 128 bits occupied by 10^feedExponent.
    /// Lower 128 bits occupied by 10^priceExponent.
    /// @param priceExponent The power for `priceScale = 10**priceExponent`.
    /// @param feedExponent The power for `feedScale = 10**feedExponent`.
    /// @return The two scale factors packed in `Scale`.
    function from(uint8 priceExponent, uint8 feedExponent) internal pure returns (Scale) {
        if (priceExponent > MAX_EXPONENT || feedExponent > MAX_EXPONENT) {
            revert Errors.PriceOracle_Overflow();
        }
        return Scale.wrap((10 ** feedExponent << 128) | 10 ** priceExponent);
    }

    /// @notice Calculate the direction of pricing, or revert if no match.
    /// @param givenBase The base asset supplied by the caller.
    /// @param base The base asset in the price oracle adapter.
    /// @param givenQuote The quote asset supplied by the caller.
    /// @param quote The quote asset in the price oracle adapter.
    /// @return False if base/quote, true if quote/base else revert.
    function getDirectionOrRevert(address givenBase, address base, address givenQuote, address quote)
        internal
        pure
        returns (bool)
    {
        if (givenBase == base && givenQuote == quote) return false;
        if (givenBase == quote && givenQuote == base) return true;
        revert Errors.PriceOracle_NotSupported(givenBase, givenQuote);
    }

    /// @notice Calculate the scale factors for converting a unit price.
    /// @param baseDecimals The decimals of the base asset.
    /// @param quoteDecimals The decimals of the quote asset.
    /// @param feedDecimals The decimals of the feed, already incorporated into the price.
    /// @return The scale factors used for price conversions.
    function calcScale(uint8 baseDecimals, uint8 quoteDecimals, uint8 feedDecimals) internal pure returns (Scale) {
        return from(quoteDecimals, feedDecimals + baseDecimals);
    }

    /// @notice Convert the price by applying scale factors.
    /// @param inAmount The amount of `base` to convert.
    /// @param unitPrice The unit price reported by the feed.
    /// @param scale The scale factors returned by `calcScale`.
    /// @param inverse Whether to price base/quote or quote/base.
    /// @return The resulting outAmount.
    function calcOutAmount(uint256 inAmount, uint256 unitPrice, Scale scale, bool inverse)
        internal
        pure
        returns (uint256)
    {
        uint256 priceScale = Scale.unwrap(scale) & PRICE_SCALE_MASK;
        uint256 feedScale = Scale.unwrap(scale) >> 128;
        if (inverse) {
            // (inAmount * feedScale) / (priceScale * unitPrice)
            return fullMulDiv(inAmount, feedScale, priceScale * unitPrice);
        } else {
            // (inAmount * priceScale * unitPrice) / feedScale
            return fullMulDiv(inAmount, priceScale * unitPrice, feedScale);
        }
    }

    /// @notice Full precision multiply-divide operation.
    /// @dev Replaces FixedPointMathLib.fullMulDiv to avoid external dependency.
    /// @param a The multiplicand.
    /// @param b The multiplier.
    /// @param denominator The divisor.
    /// @return result The result of (a * b) / denominator.
    function fullMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512-bit multiplication
        uint256 prod0; // Least significant 256 bits
        uint256 prod1; // Most significant 256 bits
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle division by zero
        if (denominator == 0) {
            revert Errors.PriceOracle_Overflow();
        }

        // Make sure the result is less than 2**256.
        if (prod1 >= denominator) {
            revert Errors.PriceOracle_Overflow();
        }

        // 512-bit by 256-bit division
        assembly {
            result := div(prod0, denominator)
            // prod1 * 2^256 / denominator
            let remainder := mulmod(a, b, denominator)
            if gt(remainder, 0) {
                // Check if rounding would overflow
                if gt(add(result, 1), 0) {
                    result := add(result, 1)
                }
            }
        }

        // Check for overflow in the final result
        if (result == 0 && a != 0 && b != 0) {
            revert Errors.PriceOracle_Overflow();
        }
    }
}