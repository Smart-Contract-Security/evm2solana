// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract Exponential {
    uint constant expScale = 1e18;
    uint constant halfExpScale = 5e17;

    enum MathError {
        NO_ERROR,
        DIVISION_BY_ZERO,
        INTEGER_OVERFLOW,
        INTEGER_UNDERFLOW
    }

    struct Exp {
        uint mantissa;
    }

    function mulUInt(uint a, uint b) internal pure returns (MathError, uint) {
        if (a == 0) {
            return (MathError.NO_ERROR, 0);
        }
        uint c = a * b;
        if (c / a != b) {
            return (MathError.INTEGER_OVERFLOW, 0);
        }
        return (MathError.NO_ERROR, c);
    }

    function divUInt(uint a, uint b) internal pure returns (MathError, uint) {
        if (b == 0) {
            return (MathError.DIVISION_BY_ZERO, 0);
        }
        return (MathError.NO_ERROR, a / b);
    }

    function addUInt(uint a, uint b) internal pure returns (MathError, uint) {
        uint c = a + b;
        if (c < a) {
            return (MathError.INTEGER_OVERFLOW, 0);
        }
        return (MathError.NO_ERROR, c);
    }

    function subUInt(uint a, uint b) internal pure returns (MathError, uint) {
        if (b > a) {
            return (MathError.INTEGER_UNDERFLOW, 0);
        }
        return (MathError.NO_ERROR, a - b);
    }

    function truncate(Exp memory exp) internal pure returns (uint) {
        return exp.mantissa / expScale;
    }

    function getExp(
        uint num,
        uint denom
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint scaledNumerator) = mulUInt(num, expScale);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        (MathError err1, uint rational) = divUInt(scaledNumerator, denom);
        if (err1 != MathError.NO_ERROR) {
            return (err1, Exp({mantissa: 0}));
        }

        return (MathError.NO_ERROR, Exp({mantissa: rational}));
    }

    function addExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (MathError, Exp memory) {
        (MathError error, uint result) = addUInt(a.mantissa, b.mantissa);

        return (error, Exp({mantissa: result}));
    }

    function subExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (MathError, Exp memory) {
        (MathError error, uint result) = subUInt(a.mantissa, b.mantissa);

        return (error, Exp({mantissa: result}));
    }

    function mulScalar(
        Exp memory a,
        uint scalar
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint scaledMantissa) = mulUInt(a.mantissa, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        return (MathError.NO_ERROR, Exp({mantissa: scaledMantissa}));
    }

    function mulScalarTruncate(
        Exp memory a,
        uint scalar
    ) internal pure returns (MathError, uint) {
        (MathError err, Exp memory product) = mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return (MathError.NO_ERROR, truncate(product));
    }

    function mulScalarTruncateAddUInt(
        Exp memory a,
        uint scalar,
        uint addend
    ) internal pure returns (MathError, uint) {
        (MathError err, Exp memory product) = mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return addUInt(truncate(product), addend);
    }

    function divScalar(
        Exp memory a,
        uint scalar
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint descaledMantissa) = divUInt(a.mantissa, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        return (MathError.NO_ERROR, Exp({mantissa: descaledMantissa}));
    }

    function divScalarByExp(
        uint scalar,
        Exp memory divisor
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint numerator) = mulUInt(expScale, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }
        return getExp(numerator, divisor.mantissa);
    }

    function divScalarByExpTruncate(
        uint scalar,
        Exp memory divisor
    ) internal pure returns (MathError, uint) {
        (MathError err, Exp memory fraction) = divScalarByExp(scalar, divisor);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return (MathError.NO_ERROR, truncate(fraction));
    }

    function mulExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint doubleScaledProduct) = mulUInt(
            a.mantissa,
            b.mantissa
        );
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        (MathError err1, uint doubleScaledProductWithHalfScale) = addUInt(
            halfExpScale,
            doubleScaledProduct
        );
        if (err1 != MathError.NO_ERROR) {
            return (err1, Exp({mantissa: 0}));
        }

        (MathError err2, uint product) = divUInt(
            doubleScaledProductWithHalfScale,
            expScale
        );
        assert(err2 == MathError.NO_ERROR);

        return (MathError.NO_ERROR, Exp({mantissa: product}));
    }

    function mulExp(
        uint a,
        uint b
    ) internal pure returns (MathError, Exp memory) {
        return mulExp(Exp({mantissa: a}), Exp({mantissa: b}));
    }

    function mulExp3(
        Exp memory a,
        Exp memory b,
        Exp memory c
    ) internal pure returns (MathError, Exp memory) {
        (MathError err, Exp memory ab) = mulExp(a, b);
        if (err != MathError.NO_ERROR) {
            return (err, ab);
        }
        return mulExp(ab, c);
    }

    function divExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (MathError, Exp memory) {
        return getExp(a.mantissa, b.mantissa);
    }
}