import "./CarefulMath.sol";

contract Exponential is CarefulMath {
    uint64 constant expScale = 1e18;
    uint64 constant halfExpScale = 5e17;

    struct Exp {
        uint64 mantissa;
    }

    function truncate(Exp memory exp) internal pure returns (uint64) {
        return exp.mantissa / expScale;
    }

    function getExp(
        uint64 num,
        uint64 denom
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint64 scaledNumerator) = mulUInt(num, expScale);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        (MathError err1, uint64 rational) = divUInt(scaledNumerator, denom);
        if (err1 != MathError.NO_ERROR) {
            return (err1, Exp({mantissa: 0}));
        }

        return (MathError.NO_ERROR, Exp({mantissa: rational}));
    }

    function addExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (MathError, Exp memory) {
        (MathError error, uint64 result) = addUInt(a.mantissa, b.mantissa);

        return (error, Exp({mantissa: result}));
    }

    function subExp(
        Exp memory a,
        Exp memory b
    ) internal pure returns (MathError, Exp memory) {
        (MathError error, uint64 result) = subUInt(a.mantissa, b.mantissa);

        return (error, Exp({mantissa: result}));
    }

    function mulScalar(
        Exp memory a,
        uint64 scalar
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint64 scaledMantissa) = mulUInt(a.mantissa, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        return (MathError.NO_ERROR, Exp({mantissa: scaledMantissa}));
    }

    function mulScalarTruncate(
        Exp memory a,
        uint64 scalar
    ) internal pure returns (MathError, uint64) {
        (MathError err, Exp memory product) = mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return (MathError.NO_ERROR, truncate(product));
    }

    function mulScalarTruncateAddUInt(
        Exp memory a,
        uint64 scalar,
        uint64 addend
    ) internal pure returns (MathError, uint64) {
        (MathError err, Exp memory product) = mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return addUInt(truncate(product), addend);
    }

    function divScalar(
        Exp memory a,
        uint64 scalar
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint64 descaledMantissa) = divUInt(a.mantissa, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        return (MathError.NO_ERROR, Exp({mantissa: descaledMantissa}));
    }

    function divScalarByExp(
        uint64 scalar,
        Exp memory divisor
    ) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint64 numerator) = mulUInt(expScale, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }
        return getExp(numerator, divisor.mantissa);
    }

    function divScalarByExpTruncate(
        uint64 scalar,
        Exp memory divisor
    ) internal pure returns (MathError, uint64) {
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
        (MathError err0, uint64 doubleScaledProduct) = mulUInt(
            a.mantissa,
            b.mantissa
        );
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({mantissa: 0}));
        }

        (MathError err1, uint64 doubleScaledProductWithHalfScale) = addUInt(
            halfExpScale,
            doubleScaledProduct
        );
        if (err1 != MathError.NO_ERROR) {
            return (err1, Exp({mantissa: 0}));
        }

        (MathError err2, uint64 product) = divUInt(
            doubleScaledProductWithHalfScale,
            expScale
        );
        assert(err2 == MathError.NO_ERROR);

        return (MathError.NO_ERROR, Exp({mantissa: product}));
    }

    function mulExp(
        uint64 a,
        uint64 b
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