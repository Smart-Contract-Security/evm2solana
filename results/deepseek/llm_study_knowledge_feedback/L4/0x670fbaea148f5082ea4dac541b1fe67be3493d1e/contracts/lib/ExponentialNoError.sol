// SPDX-License-Identifier: BSD-3-Clause

/**
 * @title Exponential module for storing fixed-precision decimals
 * @author Compound
 * @notice Exp is a struct which stores decimals with a fixed precision of 18 decimal places.
 *         Thus, if we wanted to store the 5.1, mantissa would store 5.1e18. That is:
 *         `Exp({mantissa: 5100000000000000000})`.
 */
contract ExponentialNoError {
    uint128 constant expScale = 1000000000000000000;
    uint128 constant doubleScale = 1000000000000000000000000000000000000;

    struct Exp {
        uint128 mantissa;
    }

    struct Double {
        uint128 mantissa;
    }

    /**
     * @dev Truncates the given exp to a whole number value.
     *      For example, truncate(Exp{mantissa: 15 * expScale}) = 15
     */
    function truncate(Exp memory exp) internal pure returns (uint128) {
        // Note: We are not using careful math here as we're performing a division that cannot fail
        return exp.mantissa / expScale;
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function mul_ScalarTruncate(
        Exp memory a,
        uint128 scalar
    ) internal pure returns (uint128) {
        Exp memory product = mul_ExpScalar(a, scalar);
        return truncate(product);
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function mul_ScalarTruncateAddUInt(
        Exp memory a,
        uint128 scalar,
        uint128 addend
    ) internal pure returns (uint128) {
        Exp memory product = mul_ExpScalar(a, scalar);
        return add_uint128(truncate(product), addend);
    }

    /**
     * @dev Checks if first Exp is less than second Exp.
     */
    function lessThanExp(
        Exp memory left,
        Exp memory right
    ) internal pure returns (bool) {
        return left.mantissa < right.mantissa;
    }

    /**
     * @dev Checks if left Exp <= right Exp.
     */
    function lessThanOrEqualExp(
        Exp memory left,
        Exp memory right
    ) internal pure returns (bool) {
        return left.mantissa <= right.mantissa;
    }

    /**
     * @dev Checks if left Exp > right Exp.
     */
    function greaterThanExp(
        Exp memory left,
        Exp memory right
    ) internal pure returns (bool) {
        return left.mantissa > right.mantissa;
    }

    /**
     * @dev returns true if Exp is exactly zero
     */
    function isZeroExp(Exp memory value) internal pure returns (bool) {
        return value.mantissa == 0;
    }

    function safe224(
        uint128 n,
        string memory errorMessage
    ) internal pure returns (uint128) {
        require(n < 2 ** 64, errorMessage);
        return uint128(n);
    }

    function safe32(
        uint128 n,
        string memory errorMessage
    ) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function add_Exp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: add_uint128(a.mantissa, b.mantissa)});
    }

    function add_Double(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return Double({mantissa: add_uint128(a.mantissa, b.mantissa)});
    }

    function add_uint128(uint128 a, uint128 b) internal pure returns (uint128) {
        return a + b;
    }

    function sub_Exp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: sub_uint128(a.mantissa, b.mantissa)});
    }

    function sub_Double(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return Double({mantissa: sub_uint128(a.mantissa, b.mantissa)});
    }

    function sub_uint128(uint128 a, uint128 b) internal pure returns (uint128) {
        return a - b;
    }

    function mul_ExpExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: mul_uint128(a.mantissa, b.mantissa) / expScale});
    }

    function mul_ExpScalar(Exp memory a, uint128 b) internal pure returns (Exp memory) {
        return Exp({mantissa: mul_uint128(a.mantissa, b)});
    }

    function mul_ScalarExp(uint128 a, Exp memory b) internal pure returns (uint128) {
        return mul_uint128(a, b.mantissa) / expScale;
    }

    function mul_DoubleDouble(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return Double({mantissa: mul_uint128(a.mantissa, b.mantissa) / doubleScale});
    }

    function mul_DoubleScalar(
        Double memory a,
        uint128 b
    ) internal pure returns (Double memory) {
        return Double({mantissa: mul_uint128(a.mantissa, b)});
    }

    function mul_ScalarDouble(uint128 a, Double memory b) internal pure returns (uint128) {
        return mul_uint128(a, b.mantissa) / doubleScale;
    }

    function mul_uint128(uint128 a, uint128 b) internal pure returns (uint128) {
        return a * b;
    }

    function div_ExpExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: div_uint128(mul_uint128(a.mantissa, expScale), b.mantissa)});
    }

    function div_ExpScalar(Exp memory a, uint128 b) internal pure returns (Exp memory) {
        return Exp({mantissa: div_uint128(a.mantissa, b)});
    }

    function div_ScalarExp(uint128 a, Exp memory b) internal pure returns (uint128) {
        return div_uint128(mul_uint128(a, expScale), b.mantissa);
    }

    function div_DoubleDouble(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return
            Double({mantissa: div_uint128(mul_uint128(a.mantissa, doubleScale), b.mantissa)});
    }

    function div_DoubleScalar(
        Double memory a,
        uint128 b
    ) internal pure returns (Double memory) {
        return Double({mantissa: div_uint128(a.mantissa, b)});
    }

    function div_ScalarDouble(uint128 a, Double memory b) internal pure returns (uint128) {
        return div_uint128(mul_uint128(a, doubleScale), b.mantissa);
    }

    function div_uint128(uint128 a, uint128 b) internal pure returns (uint128) {
        return a / b;
    }

    function fraction(
        uint128 a,
        uint128 b
    ) internal pure returns (Double memory) {
        return Double({mantissa: div_uint128(mul_uint128(a, doubleScale), b)});
    }
}