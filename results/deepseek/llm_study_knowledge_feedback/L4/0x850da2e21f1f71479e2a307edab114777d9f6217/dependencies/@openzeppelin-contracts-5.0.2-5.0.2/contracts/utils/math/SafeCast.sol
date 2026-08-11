// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/SafeCast.sol)
// This file was procedurally generated from scripts/generate/templates/SafeCast.js.

library SafeCast {
    function toUint248(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint248");
        }
        return uint64(value);
    }

    function toUint240(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint240");
        }
        return uint64(value);
    }

    function toUint232(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint232");
        }
        return uint64(value);
    }

    function toUint224(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint224");
        }
        return uint64(value);
    }

    function toUint216(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint216");
        }
        return uint64(value);
    }

    function toUint208(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint208");
        }
        return uint64(value);
    }

    function toUint200(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint200");
        }
        return uint64(value);
    }

    function toUint192(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint192");
        }
        return uint64(value);
    }

    function toUint184(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint184");
        }
        return uint64(value);
    }

    function toUint176(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint176");
        }
        return uint64(value);
    }

    function toUint168(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint168");
        }
        return uint64(value);
    }

    function toUint160(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint160");
        }
        return uint64(value);
    }

    function toUint152(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint152");
        }
        return uint64(value);
    }

    function toUint144(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint144");
        }
        return uint64(value);
    }

    function toUint136(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint136");
        }
        return uint64(value);
    }

    function toUint128(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint128");
        }
        return uint64(value);
    }

    function toUint120(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint120");
        }
        return uint64(value);
    }

    function toUint112(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint112");
        }
        return uint64(value);
    }

    function toUint104(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint104");
        }
        return uint64(value);
    }

    function toUint96(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint96");
        }
        return uint64(value);
    }

    function toUint88(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint88");
        }
        return uint64(value);
    }

    function toUint80(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint80");
        }
        return uint64(value);
    }

    function toUint72(uint64 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert("SafeCast: overflow downcast to uint72");
        }
        return uint64(value);
    }

    function toUint64(uint64 value) internal pure returns (uint64) {
        return value;
    }

    function toUint56(uint64 value) internal pure returns (uint64) {
        if (value > type(uint56).max) {
            revert("SafeCast: overflow downcast to uint56");
        }
        return uint64(value);
    }

    function toUint48(uint64 value) internal pure returns (uint64) {
        if (value > type(uint48).max) {
            revert("SafeCast: overflow downcast to uint48");
        }
        return uint64(value);
    }

    function toUint40(uint64 value) internal pure returns (uint64) {
        if (value > type(uint40).max) {
            revert("SafeCast: overflow downcast to uint40");
        }
        return uint64(value);
    }

    function toUint32(uint64 value) internal pure returns (uint32) {
        if (value > type(uint32).max) {
            revert("SafeCast: overflow downcast to uint32");
        }
        return uint32(value);
    }

    function toUint24(uint64 value) internal pure returns (uint24) {
        if (value > type(uint24).max) {
            revert("SafeCast: overflow downcast to uint24");
        }
        return uint24(value);
    }

    function toUint16(uint64 value) internal pure returns (uint16) {
        if (value > type(uint16).max) {
            revert("SafeCast: overflow downcast to uint16");
        }
        return uint16(value);
    }

    function toUint8(uint64 value) internal pure returns (uint8) {
        if (value > type(uint8).max) {
            revert("SafeCast: overflow downcast to uint8");
        }
        return uint8(value);
    }

    function toUint256(int64 value) internal pure returns (uint64) {
        if (value < 0) {
            revert("SafeCast: overflow int to uint");
        }
        return uint64(value);
    }

    function toInt248(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int248");
        }
    }

    function toInt240(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int240");
        }
    }

    function toInt232(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int232");
        }
    }

    function toInt224(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int224");
        }
    }

    function toInt216(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int216");
        }
    }

    function toInt208(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int208");
        }
    }

    function toInt200(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int200");
        }
    }

    function toInt192(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int192");
        }
    }

    function toInt184(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int184");
        }
    }

    function toInt176(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int176");
        }
    }

    function toInt168(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int168");
        }
    }

    function toInt160(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int160");
        }
    }

    function toInt152(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int152");
        }
    }

    function toInt144(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int144");
        }
    }

    function toInt136(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int136");
        }
    }

    function toInt128(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int128");
        }
    }

    function toInt120(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int120");
        }
    }

    function toInt112(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int112");
        }
    }

    function toInt104(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int104");
        }
    }

    function toInt96(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int96");
        }
    }

    function toInt88(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int88");
        }
    }

    function toInt80(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int80");
        }
    }

    function toInt72(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int72");
        }
    }

    function toInt64(int64 value) internal pure returns (int64 downcasted) {
        return value;
    }

    function toInt56(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int56");
        }
    }

    function toInt48(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int48");
        }
    }

    function toInt40(int64 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int40");
        }
    }

    function toInt32(int64 value) internal pure returns (int32 downcasted) {
        downcasted = int32(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int32");
        }
    }

    function toInt24(int64 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int24");
        }
    }

    function toInt16(int64 value) internal pure returns (int16 downcasted) {
        downcasted = int16(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int16");
        }
    }

    function toInt8(int64 value) internal pure returns (int8 downcasted) {
        downcasted = int8(value);
        if (downcasted != value) {
            revert("SafeCast: overflow downcast to int8");
        }
    }

    function toInt256(uint64 value) internal pure returns (int64) {
        if (value > uint64(type(int64).max)) {
            revert("SafeCast: overflow uint to int");
        }
        return int64(value);
    }
}