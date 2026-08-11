// SPDX-License-Identifier: GPL-2.0-or-later

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
            revert("PriceOracle_Overflow");
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
        revert("PriceOracle_NotSupported");
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
    /// @dev Calculates floor(a * b / denominator) with full precision.
    /// @param a The multiplicand.
    /// @param b The multiplier.
    /// @param denominator The divisor.
    /// @return result The 256-bit result.
    function fullMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // Handle division by zero
        if (denominator == 0) {
            return 0;
        }

        // 512-bit multiply [prod1 prod0] = a * b
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            return prod0 / denominator;
        }

        // Make sure the result is less than 2**256.
        if (prod1 >= denominator) {
            return 0;
        }

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.
        uint256 twos = denominator & (~denominator + 1);
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the preconditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }
}