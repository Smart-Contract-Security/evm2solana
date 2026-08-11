// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library HeadLib {
    function _cat(string memory a, string memory b) private pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function head(uint256 idx, uint256 eyeIdx) external pure returns (string memory out) {
        if (idx == 0) return "";

        bytes3 e1 = P.eye(eyeIdx, 0);
        bytes3 e3 = P.eye(eyeIdx, 2);

        if (idx < 7) out = _baseHood();

        if (idx == 1)      out = _cat(out, _crown(e1, e3));
        else if (idx == 2) out = _cat(out, _horns(e1));
        else if (idx == 3) out = _cat(out, _visor(e1));
        else if (idx == 4) out = _cat(out, _beanie(e1));
        else if (idx == 5) out = _cat(out, _mohawk(e1, e3));
        else if (idx == 6) out = _cat(out, _halo(e1, e3));
        else if (idx == 7) out = _headphones();
        else if (idx == 8) out = _topHat();
    }

    function _baseHood() private pure returns (string memory r) {
        bytes3 h2 = 0x16162e;
        bytes3 h3 = 0x101028;
        r = string(abi.encodePacked(
            S.rect(9,3,14,1,h2),  S.rect(8,4,16,1,h2),
            S.rect(7,5,18,1,h3),  S.rect(7,5,1,12,h2)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(8,5,1,12,h3),  S.rect(23,5,1,12,h2), S.rect(24,5,1,12,h3)
        )));
    }

    function _crown(bytes3 e1, bytes3 e3) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(10,3,12,1,e1), S.rect(10,4,12,1,e1),
            S.rect(13,1,1,2,e3),  S.rect(16,0,1,3,e3),
            S.rect(19,1,1,2,e3)
        ));
    }

    function _horns(bytes3 e1) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(9,0,1,2,e1), S.rect(10,1,1,2,e1),
            S.rect(22,0,1,2,e1), S.rect(21,1,1,2,e1)
        ));
    }

    function _visor(bytes3 e1) private pure returns (string memory) {
        return string(abi.encodePacked(S.rect(8,6,16,1,e1), S.rect(8,7,16,1,e1)));
    }

    function _beanie(bytes3 e1) private pure returns (string memory) {
        return string(abi.encodePacked(S.rect(10,2,12,1,e1), S.rect(9,3,14,1,e1)));
    }

    function _mohawk(bytes3 e1, bytes3 e3) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(15,0,2,4,e1), S.rect(14,1,1,3,e3), S.rect(17,1,1,3,e3)
        ));
    }

    function _halo(bytes3 e1, bytes3 e3) private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(10,1,12,1,e3), S.rect(9,2,1,1,e1), S.rect(22,2,1,1,e1)
        ));
    }

    function _headphones() private pure returns (string memory r) {
        r = string(abi.encodePacked(
            S.rect(9,2,14,2,0x222222),
            S.rect(7,4,3,6,0x333333),
            S.rect(22,4,3,6,0x333333)
        ));
        r = _cat(r, string(abi.encodePacked(
            S.rect(8,5,1,4,0x111111),
            S.rect(23,5,1,4,0x111111)
        )));
    }

    function _topHat() private pure returns (string memory) {
        return string(abi.encodePacked(
            S.rect(10,0,12,4,0x1a1a1a),
            S.rect(8,4,16,1,0x1a1a1a),
            S.rect(10,3,12,1,0xff0040)
        ));
    }
}
