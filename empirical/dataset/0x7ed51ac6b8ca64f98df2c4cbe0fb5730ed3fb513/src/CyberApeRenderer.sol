// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TraitStorage} from "./TraitStorage.sol";

/// @title CyberApeRenderer
/// @notice On-chain SVG + JSON metadata renderer. Reads trait fragments from a
///         TraitStorage instance and composes the final SVG.
///
///         The CAT_* id is a storage key only — visual paint order is decided
///         separately by `_zOrder()` so categories can be registered in any
///         convenient sequence without affecting how layers stack.
library CyberApeRenderer {
    using Strings for uint256;

    // Storage category ids (registration order — must match how blobs were uploaded).
    uint8 internal constant CAT_BG = 0;
    uint8 internal constant CAT_NECKLACE = 1;
    uint8 internal constant CAT_FUR = 2;
    uint8 internal constant CAT_EYES = 3;
    uint8 internal constant CAT_MOUTH = 4;
    uint8 internal constant CAT_CLOTHES = 5;
    uint8 internal constant CAT_TATTOO = 6;
    uint8 internal constant CAT_EARRING = 7;
    uint8 internal constant CAT_HAT = 8;

    uint256 internal constant CAT_COUNT = 9;

    struct Trait {
        uint8 idx;
        string name;
        string svg;
    }

    string internal constant SVG_HEADER = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600">';
    string internal constant SVG_FOOTER = "</svg>";

    /// @notice Pack picked indices into a bytes32 fingerprint, one byte per category.
    function dnaOf(TraitStorage store, uint256 seed) internal view returns (bytes32) {
        uint256 packed;
        for (uint8 c = 0; c < CAT_COUNT; ++c) {
            uint8 idx = store.pickIndex(c, _slice(seed, c));
            packed |= uint256(idx) << (uint256(c) * 8);
        }
        return bytes32(packed);
    }

    function tokenURI(TraitStorage store, uint256 tokenId, uint256 seed) internal view returns (string memory) {
        Trait[CAT_COUNT] memory picks = _pickAll(store, seed);

        // Compose SVG body in z-order (back to front).
        uint8[CAT_COUNT] memory z = _zOrder();
        string memory body;
        for (uint256 i = 0; i < CAT_COUNT; ++i) {
            body = string(abi.encodePacked(body, picks[z[i]].svg));
        }
        string memory svg = string(abi.encodePacked(SVG_HEADER, body, SVG_FOOTER));

        string memory attrs = _attributesJson(picks);
        string memory json = string(
            abi.encodePacked(
                '{"name":"Cyber Apes Club #',
                tokenId.toString(),
                '","description":"Fully on-chain generative cyber ape.",',
                '"image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(svg)),
                '","attributes":',
                attrs,
                "}"
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _pickAll(TraitStorage store, uint256 seed) private view returns (Trait[CAT_COUNT] memory picks) {
        for (uint8 c = 0; c < CAT_COUNT; ++c) {
            uint8 idx = store.pickIndex(c, _slice(seed, c));
            picks[c] = Trait({idx: idx, name: store.traitName(c, idx), svg: store.traitSVG(c, idx)});
        }
    }

    /// @dev Paint order: background first, then ape body (fur owns neck+head+
    ///      snout), face tattoos on the head skin, then clothes covering the
    ///      lower neck/shoulders, with necklace layered above the chest, then
    ///      mouth/eyes, ear-mounted earring, and finally hat above the head.
    function _zOrder() private pure returns (uint8[CAT_COUNT] memory z) {
        z[0] = CAT_BG;
        z[1] = CAT_FUR;
        z[2] = CAT_TATTOO;
        z[3] = CAT_CLOTHES;
        z[4] = CAT_NECKLACE;
        z[5] = CAT_MOUTH;
        z[6] = CAT_EYES;
        z[7] = CAT_EARRING;
        z[8] = CAT_HAT;
    }

    function _attributesJson(Trait[CAT_COUNT] memory picks) private pure returns (string memory) {
        string[CAT_COUNT] memory labels = _labels();
        bytes memory out = bytes("[");
        for (uint256 i = 0; i < CAT_COUNT; ++i) {
            if (i > 0) out = abi.encodePacked(out, ",");
            out = abi.encodePacked(out, '{"trait_type":"', labels[i], '","value":"', picks[i].name, '"}');
        }
        return string(abi.encodePacked(out, "]"));
    }

    function _labels() private pure returns (string[CAT_COUNT] memory labels) {
        labels[CAT_BG] = "Background";
        labels[CAT_NECKLACE] = "Necklace";
        labels[CAT_FUR] = "Fur";
        labels[CAT_EYES] = "Eyes";
        labels[CAT_MOUTH] = "Mouth";
        labels[CAT_CLOTHES] = "Clothes";
        labels[CAT_TATTOO] = "Tattoo";
        labels[CAT_EARRING] = "Earring";
        labels[CAT_HAT] = "Hat";
    }

    /// @dev Derive an independent random stream per category so reshuffling one
    ///      layer's variants doesn't cascade into the others.
    function _slice(uint256 seed, uint8 catId) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, catId)));
    }
}
