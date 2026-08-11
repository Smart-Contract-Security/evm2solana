// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library HoodieLib {
    bytes3 constant OL = 0x1a1520;

    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function hoodie(uint256 i, uint256 eyeIdx) external pure returns (string memory out) {
        bytes3 h1 = P.hoodie(i, 0);
        bytes3 h2 = P.hoodie(i, 1);
        bytes3 h3 = P.hoodie(i, 2);
        bytes3 h4 = P.hoodie(i, 3);
        bytes3 h5 = P.hoodie(i, 4);
        bytes3 h6 = P.hoodie(i, 5);
        bytes3 e1 = P.eye(eyeIdx, 0);

        out = string(abi.encodePacked(
            S.rect(8,17,16,1,h1), S.rect(4,18,24,1,h1),
            S.rect(4,19,24,1,h2), S.rect(4,20,24,1,h2)
        ));
        out = _cat(out, string(abi.encodePacked(
            S.rect(4,21,24,1,h3), S.rect(4,22,24,1,h3),
            S.rect(4,23,24,2,h4), S.rect(4,25,24,7,h5)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(14,18,4,1,h4), S.rect(15,19,2,1,h5),
            S.rect(13,18,1,5,h6), S.rect(18,18,1,5,h6)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(13,23,1,1,e1), S.rect(18,23,1,1,e1),
            S.rect(8,20,1,7,h1),  S.rect(23,20,1,7,h1)
        )));
        out = _cat(out, string(abi.encodePacked(
            S.rect(3,19,1,2,OL), S.rect(28,19,1,2,OL)
        )));
    }
}
