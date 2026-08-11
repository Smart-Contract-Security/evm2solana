// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library EyesLib {
    bytes3 constant OL = 0x1a1520;

    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function eyes(uint256 idx) external pure returns (string memory out) {
        bytes3 c1 = P.eye(idx, 0);
        bytes3 c3 = P.eye(idx, 2);
        bytes3 c4 = P.eye(idx, 3);

        out = string(abi.encodePacked(
            S.rect(10,9,4,4,OL), S.rect(18,9,4,4,OL)
        ));

        uint256 b = idx > 7 ? (idx % 8) : idx;

        if (b == 0 || b == 5)      out = _cat(out, _xeyes(c1, c3, c4));
        else if (b == 1)            out = _cat(out, _biohazard(c1, c3, c4));
        else if (b == 2)            out = _cat(out, _spiral(c1, c3, c4));
        else if (b == 3)            out = _cat(out, _diamond(c1, c3, c4));
        else if (b == 4)            out = _cat(out, _voidDots(c3, c4));
        else if (b == 6)            out = _cat(out, _heart(c1, c3, c4));
        else                        out = _cat(out, _deadEmpty(c4));
    }

    function _xeyes(bytes3 c1, bytes3 c3, bytes3 c4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(10,9,1,1,c1), S.rect(13,9,1,1,c1),
            S.rect(11,10,2,2,c3), S.rect(10,12,1,1,c1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(13,12,1,1,c1), S.rect(18,9,1,1,c1),
            S.rect(21,9,1,1,c1),  S.rect(19,10,2,2,c3)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,12,1,1,c1), S.rect(21,12,1,1,c1),
            S.rect(9,9,1,1,c4),   S.rect(14,9,1,1,c4)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(17,9,1,1,c4),  S.rect(22,9,1,1,c4)
        )));
    }

    function _biohazard(bytes3 c1, bytes3 c3, bytes3 c4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(11,9,2,1,c1),  S.rect(10,10,1,1,c1),
            S.rect(13,10,1,1,c1), S.rect(11,11,2,1,c3)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(10,12,1,1,c1), S.rect(13,12,1,1,c1),
            S.rect(19,9,2,1,c1),  S.rect(18,10,1,1,c1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(21,10,1,1,c1), S.rect(19,11,2,1,c3),
            S.rect(18,12,1,1,c1), S.rect(21,12,1,1,c1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(9,9,1,1,c4),  S.rect(14,9,1,1,c4),
            S.rect(17,9,1,1,c4), S.rect(22,9,1,1,c4)
        )));
    }

    function _spiral(bytes3 c1, bytes3 c3, bytes3 c4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(10,9,4,1,c1),  S.rect(10,10,1,1,c1),
            S.rect(11,10,1,1,c3), S.rect(13,10,1,1,c1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(10,11,1,1,c1), S.rect(12,11,1,1,c3),
            S.rect(13,11,1,1,c1), S.rect(10,12,4,1,c1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,9,4,1,c1),  S.rect(18,10,1,1,c1),
            S.rect(19,10,1,1,c3), S.rect(21,10,1,1,c1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,11,1,1,c1), S.rect(20,11,1,1,c3),
            S.rect(21,11,1,1,c1), S.rect(18,12,4,1,c1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(9,9,1,1,c4),  S.rect(14,9,1,1,c4),
            S.rect(17,9,1,1,c4), S.rect(22,9,1,1,c4)
        )));
    }

    function _diamond(bytes3 c1, bytes3 c3, bytes3 c4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(11,9,2,1,c1),  S.rect(10,10,1,1,c1),
            S.rect(11,10,2,1,c3), S.rect(13,10,1,1,c1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(11,11,2,1,c1), S.rect(19,9,2,1,c1),
            S.rect(18,10,1,1,c1), S.rect(19,10,2,1,c3)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(21,10,1,1,c1), S.rect(19,11,2,1,c1),
            S.rect(10,9,1,1,c4),  S.rect(13,11,1,1,c4)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,9,1,1,c4), S.rect(21,11,1,1,c4)
        )));
    }

    function _voidDots(bytes3 c3, bytes3 c4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(11,10,1,1,c3), S.rect(12,11,1,1,c3),
            S.rect(11,10,2,2,c4), S.rect(19,10,1,1,c3)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(20,11,1,1,c3), S.rect(19,10,2,2,c4),
            S.rect(10,9,1,1,c4),  S.rect(13,9,1,1,c4)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,9,1,1,c4), S.rect(21,9,1,1,c4)
        )));
    }

    function _heart(bytes3 c1, bytes3 c3, bytes3 c4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(10,9,1,1,c1),  S.rect(12,9,1,1,c1),
            S.rect(10,10,3,1,c3), S.rect(11,11,1,1,c1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,9,1,1,c1),  S.rect(20,9,1,1,c1),
            S.rect(18,10,3,1,c3), S.rect(19,11,1,1,c1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(9,9,1,1,c4),  S.rect(14,9,1,1,c4),
            S.rect(17,9,1,1,c4), S.rect(22,9,1,1,c4)
        )));
    }

    function _deadEmpty(bytes3 c4) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(11,10,2,1,c4), S.rect(11,11,2,1,c4),
            S.rect(19,10,2,1,c4), S.rect(19,11,2,1,c4)
        ));
    }
}
