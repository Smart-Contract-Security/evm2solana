// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library SkullLib {
    bytes3 constant OL = 0x1a1520;

    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function skull(uint256 i) external pure returns (string memory out) {
        bytes3 s1 = P.skull(i, 0);
        bytes3 s2 = P.skull(i, 1);
        bytes3 s3 = P.skull(i, 2);
        bytes3 s4 = P.skull(i, 3);
        bytes3 s5 = P.skull(i, 4);
        bytes3 s6 = P.skull(i, 5);

        out = string(abi.encodePacked(
            S.rect(12,4,8,1,s1), S.rect(11,5,10,1,s1), S.rect(10,6,12,1,s1)
        ));
        out = _cat(out, string(abi.encodePacked(
            S.rect(9,7,14,1,s2), S.rect(9,8,14,1,s2), S.rect(9,9,14,1,s3)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(9,10,14,1,s3), S.rect(9,11,14,1,s3), S.rect(9,12,14,1,s4)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(10,13,12,1,s4), S.rect(10,14,12,1,s5),
            S.rect(11,15,10,1,s5), S.rect(12,16,8,1,s6)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(12,3,8,1,OL), S.rect(11,4,1,1,OL), S.rect(20,4,1,1,OL)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(10,5,1,1,OL), S.rect(21,5,1,1,OL),
            S.rect(9,6,1,1,OL),  S.rect(22,6,1,1,OL)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(8,7,1,1,OL),  S.rect(23,7,1,1,OL),
            S.rect(8,8,1,5,OL),  S.rect(23,8,1,5,OL)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(8,12,1,1,OL),  S.rect(23,12,1,1,OL),
            S.rect(9,13,1,1,OL),  S.rect(22,13,1,1,OL)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(10,15,1,1,OL), S.rect(21,15,1,1,OL),
            S.rect(11,16,1,1,OL), S.rect(20,16,1,1,OL)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(12,17,1,1,OL), S.rect(19,17,1,1,OL)
        )));
    }
}
