// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library PRNGLib {

    struct State {
        uint32 a;
        uint32 b;
        uint32 c;
        uint32 d;
        uint32 a2;
        uint32 b2;
        uint32 c2;
        uint32 d2;
        bool useA;
    }

    function init(bytes32 seed) internal pure returns (State memory s) {
        uint256 raw = uint256(seed);

        s.a = uint32(raw >> 224);
        s.b = uint32(raw >> 192);
        s.c = uint32(raw >> 160);
        s.d = uint32(raw >> 128);

        s.a2 = uint32(raw >> 96);
        s.b2 = uint32(raw >> 64);
        s.c2 = uint32(raw >> 32);
        s.d2 = uint32(raw);

        s.useA = false;
    }

    function _sfc32Step(
        uint32 a, uint32 b, uint32 c, uint32 d
    ) private pure returns (
        uint32 result,
        uint32 na, uint32 nb, uint32 nc, uint32 nd
    ) {
        unchecked {
            uint32 t = (a + b) + d;
            nd = d + 1;
            na = b ^ (b >> 9);
            nb = c + (c << 3);
            nc = (c << 21) | (c >> 11);
            nc = nc + t;
            result = t;
        }
    }

    function next(State memory s) internal pure returns (uint32 result) {
        s.useA = !s.useA;

        if (s.useA) {
            (result, s.a, s.b, s.c, s.d) = _sfc32Step(s.a, s.b, s.c, s.d);
        } else {
            (result, s.a2, s.b2, s.c2, s.d2) = _sfc32Step(s.a2, s.b2, s.c2, s.d2);
        }
    }

    function nextRange(State memory s, uint32 max) internal pure returns (uint32) {
        return uint32((uint64(next(s)) * uint64(max)) >> 32);
    }
}