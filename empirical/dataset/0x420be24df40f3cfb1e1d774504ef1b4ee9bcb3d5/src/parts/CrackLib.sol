// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library CrackLib {
    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function crack(uint256 idx, uint256 eyeIdx) external pure returns (string memory) {
        if (idx == 3) return "";

        bytes3 ck = 0x3a3050;

        if (idx == 6) {
            return string(abi.encodePacked(
                S.rect(15,5,1,3,ck), S.rect(16,4,1,1,ck), S.rect(16,8,1,1,ck)
            ));
        }
        if (idx == 7) {
            return string(abi.encodePacked(
                S.rect(16,4,1,5,ck), S.rect(14,6,5,1,ck)
            ));
        }
        if (idx == 4) {
            bytes3 g1 = 0xffc832;
            bytes3 g2 = 0xcc9900;
            string memory a = string(abi.encodePacked(
                S.rect(16,4,1,1,g1), S.rect(15,5,2,1,g2), S.rect(15,6,1,1,g1)
            ));
            return _cat(a, string(abi.encodePacked(
                S.rect(16,7,1,1,g2), S.rect(16,8,1,1,g1), S.rect(15,8,1,1,g2)
            )));
        }

        bytes3 e2  = P.eye(eyeIdx, 1);
        bytes3 e4  = P.eye(eyeIdx, 3);
        bytes3 ck2 = 0x2a2040;

        string memory base = string(abi.encodePacked(
            S.rect(16,4,1,1,e2), S.rect(15,5,2,1,ck),
            S.rect(15,6,1,1,ck), S.rect(16,6,1,1,ck2)
        ));
        base = _cat(base, string(abi.encodePacked(
            S.rect(16,7,1,1,ck), S.rect(17,7,1,1,ck2),
            S.rect(16,8,1,1,ck), S.rect(15,8,1,1,ck2)
        )));

        if (idx == 0) return base;
        if (idx == 1) return _cat(base, string(abi.encodePacked(S.rect(14,6,1,1,ck), S.rect(18,8,1,1,ck))));
        if (idx == 2) return _cat(base, string(abi.encodePacked(S.rect(17,5,1,1,e4), S.rect(14,7,1,1,e4))));
        return _cat(base, string(abi.encodePacked(S.rect(15,6,1,1,e4), S.rect(16,4,1,1,e2))));
    }
}
