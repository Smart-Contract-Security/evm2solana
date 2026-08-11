// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library FxLib {
    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function fx(uint256 idx, uint256 eyeIdx) external pure returns (string memory) {
        if (idx == 6) return "";

        bytes3 e1 = P.eye(eyeIdx, 0);
        bytes3 e2 = P.eye(eyeIdx, 1);
        bytes3 e4 = P.eye(eyeIdx, 3);

        if (idx == 0) return _fxGlitch(e1, e2, e4);
        if (idx == 1) return _fxBlood(e1, e2, e4);
        if (idx == 2) return _fxSparkle(e1, e2, e4);
        if (idx == 3) return _fxSmoke(e4);
        if (idx == 4) return _fxRain(e4);
        if (idx == 5) return _fxFire(e1, e2, e4);
        if (idx == 7) return _fxLightning(e1, e2);
        if (idx == 8) return _fxMatrix();
        return _fxSnow();
    }

    function _fxGlitch(bytes3 e1, bytes3 e2, bytes3 e4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(2,3,1,1,e1), S.rect(29,7,1,1,e2),
            S.rect(3,14,1,1,e4), S.rect(1,28,1,1,e1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(30,3,1,1,e2), S.rect(4,9,1,1,e4)
        )));
    }

    function _fxBlood(bytes3 e1, bytes3 e2, bytes3 e4) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(12,17,1,2,e4), S.rect(19,17,1,2,e4),
            S.rect(2,5,1,1,e1),   S.rect(29,10,1,1,e2)
        ));
    }

    function _fxSparkle(bytes3 e1, bytes3 e2, bytes3 e4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(2,2,1,1,e1),   S.rect(29,4,1,1,e2),
            S.rect(3,10,1,1,e4),  S.rect(28,16,1,1,e1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(1,20,1,1,e2),  S.rect(30,8,1,1,e1)
        )));
    }

    function _fxSmoke(bytes3 e4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(6,0,1,1,e4),  S.rect(25,0,1,1,e4),
            S.rect(8,1,1,1,e4),  S.rect(23,1,1,1,e4)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(5,1,1,1,e4),  S.rect(26,1,1,1,e4)
        )));
    }

    function _fxRain(bytes3 e4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(5,2,1,2,e4),  S.rect(10,0,1,2,e4),
            S.rect(20,1,1,2,e4), S.rect(26,3,1,2,e4)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(3,6,1,2,e4),  S.rect(28,8,1,2,e4)
        )));
    }

    function _fxFire(bytes3 e1, bytes3 e2, bytes3 e4) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(5,28,1,3,e1),  S.rect(6,29,1,2,e2),
            S.rect(26,28,1,3,e1), S.rect(25,29,1,2,e2)
        ));
        r = _cat(r, S.rect(15,28,2,3,e4));
    }

    function _fxLightning(bytes3 e1, bytes3 e2) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(4,2,1,1,e1),  S.rect(5,3,1,1,e1),
            S.rect(4,4,1,1,e2),  S.rect(27,5,1,1,e1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(26,6,1,1,e1), S.rect(27,7,1,1,e2)
        )));
    }

    function _fxMatrix() private pure returns (string memory r) {
        bytes3 g  = 0x00ff00;
        bytes3 g2 = 0xaaffaa;
        r = string(abi.encodePacked(
            S.rect(3,1,1,3,g),  S.rect(3,5,1,1,g2),
            S.rect(9,6,1,4,g),  S.rect(9,11,1,1,g2)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(25,2,1,5,g),  S.rect(25,8,1,1,g2),
            S.rect(28,12,1,3,g), S.rect(28,16,1,1,g2)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(2,22,1,2,g), S.rect(24,25,1,4,g)
        )));
    }

    function _fxSnow() private pure returns (string memory r) {
        bytes3 w = 0xffffff;
        r = string(abi.encodePacked(
            S.rect(4,4,1,1,w),  S.rect(12,2,1,1,w),
            S.rect(24,5,1,1,w), S.rect(6,12,1,1,w)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(28,10,1,1,w), S.rect(18,7,1,1,w),
            S.rect(2,20,1,1,w),  S.rect(26,22,1,1,w)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(14,18,1,1,w), S.rect(29,26,1,1,w),
            S.rect(5,28,1,1,w),  S.rect(20,30,1,1,w)
        )));
    }
}
