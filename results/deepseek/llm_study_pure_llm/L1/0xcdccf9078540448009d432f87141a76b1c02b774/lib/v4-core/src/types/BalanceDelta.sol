// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "../libraries/SafeCast.sol";

/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the amount0
/// and the lower 128 bits represent the amount1.
type BalanceDelta is int256;

using {add as +, sub as -, eq as ==, neq as !=} for BalanceDelta global;
using BalanceDeltaLibrary for BalanceDelta global;
using SafeCast for int256;

function toBalanceDelta(int128 _amount0, int128 _amount1) pure returns (BalanceDelta balanceDelta) {
    int256 shiftedAmount0 = int256(_amount0) << 128;
    int256 maskedAmount1 = int256(_amount1) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    balanceDelta = BalanceDelta.wrap(shiftedAmount0 | maskedAmount1);
}

function add(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    int256 aInt = BalanceDelta.unwrap(a);
    int256 bInt = BalanceDelta.unwrap(b);

    int256 a0 = aInt >> 128;
    int256 a1 = (aInt << 128) >> 128;
    int256 b0 = bInt >> 128;
    int256 b1 = (bInt << 128) >> 128;

    int256 res0 = a0 + b0;
    int256 res1 = a1 + b1;

    return toBalanceDelta(res0.toInt128(), res1.toInt128());
}

function sub(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    int256 aInt = BalanceDelta.unwrap(a);
    int256 bInt = BalanceDelta.unwrap(b);

    int256 a0 = aInt >> 128;
    int256 a1 = (aInt << 128) >> 128;
    int256 b0 = bInt >> 128;
    int256 b1 = (bInt << 128) >> 128;

    int256 res0 = a0 - b0;
    int256 res1 = a1 - b1;

    return toBalanceDelta(res0.toInt128(), res1.toInt128());
}

function eq(BalanceDelta a, BalanceDelta b) pure returns (bool) {
    return BalanceDelta.unwrap(a) == BalanceDelta.unwrap(b);
}

function neq(BalanceDelta a, BalanceDelta b) pure returns (bool) {
    return BalanceDelta.unwrap(a) != BalanceDelta.unwrap(b);
}

/// @notice Library for getting the amount0 and amount1 deltas from the BalanceDelta type
library BalanceDeltaLibrary {
    /// @notice A BalanceDelta of 0
    BalanceDelta public constant ZERO_DELTA = BalanceDelta.wrap(0);

    function amount0(BalanceDelta balanceDelta) internal pure returns (int128 _amount0) {
        int256 val = BalanceDelta.unwrap(balanceDelta);
        _amount0 = int128(val >> 128);
    }

    function amount1(BalanceDelta balanceDelta) internal pure returns (int128 _amount1) {
        int256 val = BalanceDelta.unwrap(balanceDelta);
        _amount1 = int128((val << 128) >> 128);
    }
}