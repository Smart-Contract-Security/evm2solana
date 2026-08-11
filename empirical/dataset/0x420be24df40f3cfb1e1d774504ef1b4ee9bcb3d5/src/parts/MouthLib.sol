// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library MouthLib {
    bytes3 constant OL = 0x1a1520;
    bytes3 constant BONE = 0xf5f0e5;
    bytes3 constant DARK = 0x0a0a12;

    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function mouth(uint256 idx, uint256 skullIdx) external pure returns (string memory) {
        bytes3 s6 = P.skull(skullIdx, 5);

        if (idx == 0) return _checker(BONE, DARK, s6, false, true);
        if (idx == 3) return _checker(BONE, DARK, s6, true,  false);
        if (idx == 4) return _checker(bytes3(0xffc832), DARK, s6, false, false);

        if (idx == 1) return _gasMask(s6);
        if (idx == 2) return _bandana(s6);
        if (idx == 5) return _missingTeeth(s6);
        if (idx == 6) return _vampireFangs();
        return _bubblegum();
    }

    function _checker(bytes3 a, bytes3 b, bytes3 s6, bool fangs, bool sideAccent)
        private pure returns (string memory r)
    {
        r = string(abi.encodePacked(
            S.rect(12,15,1,1,a), S.rect(13,15,1,1,b),
            S.rect(14,15,1,1,a), S.rect(15,15,1,1,b)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(16,15,1,1,a), S.rect(17,15,1,1,b),
            S.rect(18,15,1,1,a), S.rect(19,15,1,1,b)
        )));
        if (fangs) {
            r = _cat(r, string(abi.encodePacked(
                S.rect(12,16,1,2,a), S.rect(19,16,1,2,a)
            )));
        } else {
            r = _cat(r, string(abi.encodePacked(
                S.rect(12,16,1,1,b), S.rect(13,16,1,1,a),
                S.rect(14,16,1,1,b), S.rect(15,16,1,1,a)
            )));
            r = _cat(r, string(abi.encodePacked(
                S.rect(16,16,1,1,b), S.rect(17,16,1,1,a),
                S.rect(18,16,1,1,b), S.rect(19,16,1,1,a)
            )));
            if (sideAccent) {
                r = _cat(r, string(abi.encodePacked(
                    S.rect(11,15,1,1,s6), S.rect(20,15,1,1,s6)
                )));
            }
        }
        r = _cat(r, S.rect(13,17,6,1,s6));
    }

    function _gasMask(bytes3 s6) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(10,13,12,1,0x1a2a1e),
            S.rect(10,14,12,1,0x223828),
            S.rect(11,15,10,1,0x1a2a1e)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(12,16,8,1,0x162218),
            S.rect(15,13,2,2,0x0a1a0e),
            S.rect(13,17,6,1,s6)
        )));
    }

    function _bandana(bytes3 s6) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(10,14,12,1,0x2a0818),
            S.rect(11,15,10,1,0x3a0c20),
            S.rect(12,16,8,1,0x2a0818)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(15,15,2,1,0xff0040),
            S.rect(13,17,6,1,s6)
        )));
    }

    function _missingTeeth(bytes3 s6) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(12,15,1,1,BONE), S.rect(14,15,1,1,DARK),
            S.rect(15,15,1,1,BONE), S.rect(17,15,1,1,DARK)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(18,15,1,1,BONE), S.rect(13,16,1,1,BONE),
            S.rect(16,16,1,1,BONE), S.rect(19,16,1,1,DARK)
        )));
        r = _cat(r, S.rect(13,17,6,1,s6));
    }

    function _vampireFangs() private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(12,15,8,1,OL),
            S.rect(13,16,1,2,0xffffff),
            S.rect(18,16,1,2,0xffffff)
        ));
    }

    function _bubblegum() private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(14,15,4,4,0xff69b4),
            S.rect(13,16,6,2,0xff69b4),
            S.rect(17,16,1,1,0xffb6c1)
        ));
    }
}
