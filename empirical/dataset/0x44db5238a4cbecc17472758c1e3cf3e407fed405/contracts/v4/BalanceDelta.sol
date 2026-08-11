// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

type BalanceDelta is int256;

library BalanceDeltaLibrary {
    BalanceDelta public constant ZERO_DELTA = BalanceDelta.wrap(0);

    function amount0(BalanceDelta delta) internal pure returns (int128) {
        return int128(int256(BalanceDelta.unwrap(delta) >> 128));
    }

    function amount1(BalanceDelta delta) internal pure returns (int128) {
        return int128(int256(BalanceDelta.unwrap(delta)));
    }
}
