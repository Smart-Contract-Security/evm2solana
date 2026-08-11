// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library LogoLib {
    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function logo(uint256 idx, uint256 eyeIdx) external pure returns (string memory) {
        if (idx == 5) return "";

        bytes3 e1 = P.eye(eyeIdx, 0);
        bytes3 e3 = P.eye(eyeIdx, 2);

        if (idx == 0) return _logoRekt(e1, e3);
        if (idx == 1) return _logoBiohazard(e1, e3);
        if (idx == 2) return _logoDollar(e1);
        if (idx == 3) return _logoVoid(e1, e3);
        if (idx == 4) return _logoSkull(e1, e3);
        if (idx == 6) return _logoCircuit(e1);
        if (idx == 7) return _logoFlame(e1, e3);
        if (idx == 8) return _logoDiamond(e1);
        return _logoHeart();
    }

    function _logoRekt(bytes3 e1, bytes3 e3) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(10,25,2,1,e1), S.rect(10,26,1,1,e1),
            S.rect(11,26,1,1,e3), S.rect(10,27,2,1,e1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(13,25,2,1,e1), S.rect(13,26,1,1,e1),
            S.rect(13,27,2,1,e1), S.rect(16,25,1,1,e1)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(17,25,1,1,e3), S.rect(16,26,2,1,e1),
            S.rect(16,27,1,1,e1), S.rect(17,27,1,1,e3)
        )));
        r = _cat(r, string(abi.encodePacked(
            S.rect(19,25,3,1,e1), S.rect(20,26,1,2,e1)
        )));
    }

    function _logoBiohazard(bytes3 e1, bytes3 e3) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(15,24,2,1,e1), S.rect(14,25,1,1,e1),
            S.rect(17,25,1,1,e1), S.rect(14,26,1,1,e1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(15,26,2,1,e3), S.rect(17,26,1,1,e1),
            S.rect(15,27,2,1,e1)
        )));
    }

    function _logoDollar(bytes3 e1) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(15,24,2,1,e1), S.rect(14,25,1,1,e1),
            S.rect(15,26,2,1,e1), S.rect(17,27,1,1,e1),
            S.rect(15,28,2,1,e1)
        ));
    }

    function _logoVoid(bytes3 e1, bytes3 e3) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(14,24,4,1,e1), S.rect(14,25,1,1,e1),
            S.rect(17,25,1,1,e1), S.rect(15,25,2,1,e3)
        ));
        r = _cat(r, S.rect(14,26,4,1,e1));
    }

    function _logoSkull(bytes3 e1, bytes3 e3) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(15,24,2,1,e1), S.rect(14,25,4,1,e1),
            S.rect(14,26,1,1,e3), S.rect(17,26,1,1,e3)
        ));
        r = _cat(r, S.rect(15,27,2,1,e1));
    }

    function _logoCircuit(bytes3 e1) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(10,24,12,1,e1), S.rect(10,26,12,1,e1),
            S.rect(10,25,1,1,e1),  S.rect(21,25,1,1,e1)
        ));
    }

    function _logoFlame(bytes3 e1, bytes3 e3) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(15,24,2,1,e1), S.rect(14,25,1,1,e3),
            S.rect(17,25,1,1,e3), S.rect(15,25,2,1,e1)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(15,26,2,1,e3), S.rect(16,27,1,1,e1)
        )));
    }

    function _logoDiamond(bytes3 e1) private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(15,24,2,1,e1), S.rect(14,25,4,1,e1),
            S.rect(13,26,6,1,e1), S.rect(14,27,4,1,e1)
        ));
        r = _cat(r, S.rect(15,28,2,1,e1));
    }

    function _logoHeart() private pure returns (string memory r) {
        bytes3 h = 0xff0040;
        r = string(abi.encodePacked(
            S.rect(13,24,2,1,h), S.rect(17,24,2,1,h),
            S.rect(12,25,8,1,h), S.rect(13,26,6,1,h)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(14,27,4,1,h), S.rect(15,28,2,1,h)
        )));
    }
}
