// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TraitGen.sol";
import "./SVGBuilder.sol";
import "./Base64.sol";

/**
 * @title  SVGRenderer V1
 * @notice Clean. No evolved art yet. V2 comes post-launch via setRenderer().
 */
contract SVGRenderer {

    function render(uint256 tokenId, bool evolved)
        external pure returns (string memory)
    {
        TraitGen.Traits memory t = TraitGen.generate(tokenId);
        string memory svg = SVGBuilder.build(tokenId, t);
        string memory imgURI = string(abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        ));
        string memory json = _buildJSON(tokenId, t, evolved, imgURI);
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    function _buildJSON(
        uint256 tokenId,
        TraitGen.Traits memory t,
        bool evolved,
        string memory imgURI
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"name":"GHOST_ROOT #', _str(tokenId), '",',
            '"description":"You found it. You earned it. 2000 terminals. One per hunter.",',
            '"image":"', imgURI, '",',
            '"attributes":', _buildAttrs(t, evolved), '}'
        ));
    }

    function _buildAttrs(TraitGen.Traits memory t, bool evolved)
        internal pure returns (string memory)
    {
        return string(abi.encodePacked(
            '[{"trait_type":"Background","value":"', TraitGen.backgroundName(t.background), '"},',
            '{"trait_type":"Language","value":"',    TraitGen.languageName(t.language),    '"},',
            '{"trait_type":"Status","value":"',      TraitGen.statusName(t.status),        '"},',
            '{"trait_type":"Error","value":"',       TraitGen.errorName(t.errorType),      '"},',
            '{"trait_type":"Color","value":"',       TraitGen.colorHex(t.textColor),       '"},',
            '{"trait_type":"Evolved","value":"',     evolved ? "Yes" : "No",               '"}]'
        ));
    }

    function _str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 temp = v; uint256 d;
        while (temp != 0) { d++; temp /= 10; }
        bytes memory buf = new bytes(d);
        while (v != 0) { d--; buf[d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }
}
