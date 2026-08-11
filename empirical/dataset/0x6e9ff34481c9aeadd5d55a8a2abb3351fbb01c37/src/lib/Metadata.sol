// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Types} from "./Types.sol";
import {Traits} from "./Traits.sol";
import {Renderer} from "./Renderer.sol";

/// @title Metadata — assembles base64 JSON tokenURI from token data + SVG
/// @notice Mint price snapshot is INTERNAL ONLY. Never exposed in attributes.
library Metadata {
    using Strings for uint256;

    function buildTokenURI(uint256 tokenId, Types.TokenData memory d)
        public
        pure
        returns (string memory)
    {
        string memory svg = Renderer.renderSVG(tokenId, d);
        string memory svgBase64 = Base64.encode(bytes(svg));

        string memory json = string(abi.encodePacked(
            '{"name":"', _name(tokenId, d.tier), '",',
            '"description":"', _description(), '",',
            '"image":"data:image/svg+xml;base64,', svgBase64, '",',
            '"animation_url":"data:image/svg+xml;base64,', svgBase64, '",',
            '"attributes":', _attributes(d),
            '}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }


    // ----------------------------------------------------------
    // Name / description
    // ----------------------------------------------------------

    function _name(uint256 tokenId, uint8 tier) private pure returns (string memory) {
        return string(abi.encodePacked(
            Types.tierName(tier), " #", tokenId.toString()
        ));
    }

    function _description() private pure returns (string memory) {
        return "Obol &amp; Ash: 10,000 souls ferried across the River Styx. "
               "Every passage is paid for. The river takes. The Ferryman repays. "
               "You are not collecting. You are ferrying.";
    }

    // ----------------------------------------------------------
    // OpenSea attributes — only locked, non-internal traits
    // ----------------------------------------------------------

    function _attributes(Types.TokenData memory d) private pure returns (string memory) {
        return string(abi.encodePacked(
            '[',
            _attr("Tier",         Types.tierRarity(d.tier)), ',',
            _attr("Form",         Types.tierName(d.tier)), ',',
            _attr("Hood",         Traits.hoodName(d.hoodShape)), ',',
            _attr("Face",         Traits.faceName(d.faceInside)), ',',
            _attr("Obol",         Traits.obolName(d.obolPosition)), ',',
            _attr("Coin Mark",    Traits.coinMarkName(d.coinMark)), ',',
            _attr("Top Sigil",    Traits.sigilName(d.topSigil)), ',',
            _attr("Background",   Traits.backgroundName(d.background)), ',',
            _attr("Posture",      Traits.postureName(d.posture)), ',',
            _attr("Cloak",        Traits.cloakName(d.cloakDetail)), ',',
            _attrNum("Ascensions", d.ascensionCount),
            ']'
        ));
    }

    function _attr(string memory key, string memory value) private pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"', key, '","value":"', value, '"}'
        ));
    }

    function _attrNum(string memory key, uint8 value) private pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"', key, '","value":', uint256(value).toString(), '}'
        ));
    }

}
