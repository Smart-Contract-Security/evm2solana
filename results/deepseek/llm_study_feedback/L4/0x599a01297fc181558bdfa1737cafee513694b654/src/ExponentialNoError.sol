// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract ExponentialNoError {
    uint constant expScale = 1e18;
    uint constant doubleScale = 1e36;
    uint constant halfExpScale = expScale / 2;
    uint constant mantissaOne = expScale;

    struct Exp {
        uint mantissa;
    }

    struct Double {
        uint mantissa;
    }

    function truncate(Exp memory exp) internal pure returns (uint) {
        return exp.mantissa / expScale;
    }

    function mul_ScalarTruncate(
        Exp memory a,
        uint scalar
    ) internal pure returns (uint) {
        Exp memory product = mul_ExpScalar(a, scalar);
        return truncate(product);
    }

    function mul_ScalarTruncateAddUInt(
        Exp memory a,
        uint scalar,
        uint addend
    ) internal pure returns (uint) {
        Exp memory product = mul_ExpScalar(a, scalar);
        return add_uint(truncate(product), addend);
    }

    function lessThanExp(
        Exp memory left,
        Exp memory right
    ) internal pure returns (bool) {
        return left.mantissa < right.mantissa;
    }

    function lessThanOrEqualExp(
        Exp memory left,
        Exp memory right
    ) internal pure returns (bool) {
        return left.mantissa <= right.mantissa;
    }

    function greaterThanExp(
        Exp memory left,
        Exp memory right
    ) internal pure returns (bool) {
        return left.mantissa > right.mantissa;
    }

    function isZeroExp(Exp memory value) internal pure returns (bool) {
        return value.mantissa == 0;
    }

    function safe224(
        uint n,
        string memory errorMessage
    ) internal pure returns (uint224) {
        require(n < 2 ** 224, errorMessage);
        return uint224(n);
    }

    function safe32(
        uint n,
        string memory errorMessage
    ) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function add_Exp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: add_uint(a.mantissa, b.mantissa)});
    }

    function add_Double(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return Double({mantissa: add_uint(a.mantissa, b.mantissa)});
    }

    function add_uint(uint a, uint b) internal pure returns (uint) {
        return add_uint(a, b, "addition overflow");
    }

    function add_uint(
        uint a,
        uint b,
        string memory errorMessage
    ) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub_Exp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: sub_uint(a.mantissa, b.mantissa)});
    }

    function sub_Double(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return Double({mantissa: sub_uint(a.mantissa, b.mantissa)});
    }

    function sub_uint(uint a, uint b) internal pure returns (uint) {
        return sub_uint(a, b, "subtraction underflow");
    }

    function sub_uint(
        uint a,
        uint b,
        string memory errorMessage
    ) internal pure returns (uint) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function mul_ExpExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: mul_uint(a.mantissa, b.mantissa) / expScale});
    }

    function mul_ExpScalar(Exp memory a, uint b) internal pure returns (Exp memory) {
        return Exp({mantissa: mul_uint(a.mantissa, b)});
    }

    function mul_ScalarExp(uint a, Exp memory b) internal pure returns (uint) {
        return mul_uint(a, b.mantissa) / expScale;
    }

    function mul_DoubleDouble(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return Double({mantissa: mul_uint(a.mantissa, b.mantissa) / doubleScale});
    }

    function mul_DoubleScalar(
        Double memory a,
        uint b
    ) internal pure returns (Double memory) {
        return Double({mantissa: mul_uint(a.mantissa, b)});
    }

    function mul_ScalarDouble(uint a, Double memory b) internal pure returns (uint) {
        return mul_uint(a, b.mantissa) / doubleScale;
    }

    function mul_uint(uint a, uint b) internal pure returns (uint) {
        return mul_uint(a, b, "multiplication overflow");
    }

    function mul_uint(
        uint a,
        uint b,
        string memory errorMessage
    ) internal pure returns (uint) {
        if (a == 0 || b == 0) {
            return 0;
        }
        uint c = a * b;
        require(c / a == b, errorMessage);
        return c;
    }

    function div_ExpExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: div_uint(mul_uint(a.mantissa, expScale), b.mantissa)});
    }

    function div_ExpScalar(Exp memory a, uint b) internal pure returns (Exp memory) {
        return Exp({mantissa: div_uint(a.mantissa, b)});
    }

    function div_ScalarExp(uint a, Exp memory b) internal pure returns (uint) {
        return div_uint(mul_uint(a, expScale), b.mantissa);
    }

    function div_DoubleDouble(
        Double memory a,
        Double memory b
    ) internal pure returns (Double memory) {
        return
            Double({mantissa: div_uint(mul_uint(a.mantissa, doubleScale), b.mantissa)});
    }

    function div_DoubleScalar(
        Double memory a,
        uint b
    ) internal pure returns (Double memory) {
        return Double({mantissa: div_uint(a.mantissa, b)});
    }

    function div_ScalarDouble(uint a, Double memory b) internal pure returns (uint) {
        return div_uint(mul_uint(a, doubleScale), b.mantissa);
    }

    function div_uint(uint a, uint b) internal pure returns (uint) {
        return div_uint(a, b, "divide by zero");
    }

    function div_uint(
        uint a,
        uint b,
        string memory errorMessage
    ) internal pure returns (uint) {
        require(b > 0, errorMessage);
        return a / b;
    }

    function fraction(uint a, uint b) internal pure returns (Double memory) {
        return Double({mantissa: div_uint(mul_uint(a, doubleScale), b)});
    }
}