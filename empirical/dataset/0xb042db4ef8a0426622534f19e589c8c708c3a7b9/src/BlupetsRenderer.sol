// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IBlupetsCore} from "./IBlupetsCore.sol";
import {IBlupetsCustomArtRegistry} from "./IBlupetsCustomArtRegistry.sol";
import {IBlupetsDescriptor} from "./IBlupetsDescriptor.sol";
import {IBlupetsArtStorage} from "./IBlupetsArtStorage.sol";
import {IBlupetsRenderer} from "./IBlupetsRenderer.sol";

contract BlupetsRenderer is IBlupetsRenderer {
    using Strings for uint256;

    uint8 internal constant MODE_4BIT = 4;
    uint8 internal constant MODE_8BIT = 8;

    IBlupetsCore public immutable core;
    IBlupetsArtStorage public immutable artStorage;
    IBlupetsDescriptor public immutable descriptor;
    IBlupetsCustomArtRegistry public immutable customArtRegistry;
    string public collectionDescription;

    error InvalidDependency();
    error InvalidDescription();

    constructor(
        address core_,
        address artStorage_,
        address descriptor_,
        address customArtRegistry_,
        string memory description_
    ) {
        if (core_ == address(0) || artStorage_ == address(0) || descriptor_ == address(0)) revert InvalidDependency();
        if (bytes(description_).length == 0) revert InvalidDescription();
        core = IBlupetsCore(core_);
        artStorage = IBlupetsArtStorage(artStorage_);
        descriptor = IBlupetsDescriptor(descriptor_);
        customArtRegistry = IBlupetsCustomArtRegistry(customArtRegistry_);
        collectionDescription = description_;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        IBlupetsCore.TokenState memory state = core.tokenState(tokenId);
        (bool hasCustomArt,, string memory customLineage, string memory customForm) = _customArt(tokenId);

        string memory json = string.concat(
            '{"name":"Blupet #',
            tokenId.toString(),
            '","description":"',
            _jsonEscape(collectionDescription),
            '","image":"',
            imageURI(tokenId, state),
            '","attributes":',
            attributesJson(state, hasCustomArt, customLineage, customForm),
            "}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function imageURI(uint256 tokenId, IBlupetsCore.TokenState memory state) public view returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg(tokenId, state))));
    }

    function svg(uint256 tokenId, IBlupetsCore.TokenState memory state) public view returns (string memory) {
        (bool hasCustomArt, bytes32 customKey,,) = _customArt(tokenId);

        if (hasCustomArt && customKey != bytes32(0)) {
            try artStorage.packed(customKey) returns (bytes memory packedData) {
                string memory customFragment = renderPackedFragment(packedData);
                if (bytes(customFragment).length != 0) return wrapSvg(state, customFragment);
            } catch {}
        }

        bytes32 defaultKey = descriptor.artKey(state.stage, state.lineage, state.form);
        if (defaultKey != bytes32(0)) {
            try artStorage.packed(defaultKey) returns (bytes memory packedData) {
                string memory fragment = renderPackedFragment(packedData);
                if (bytes(fragment).length != 0) return wrapSvg(state, fragment);
            } catch {}
        }

        return fallbackSvg(state);
    }

    function attributesJson(
        IBlupetsCore.TokenState memory state,
        bool hasCustomArt,
        string memory customLineage,
        string memory customForm
    ) public view returns (string memory) {
        if (state.stage == 0) {
            return '[{"trait_type":"Stage","value":"Unrevealed"}]';
        }

        string memory lineage = hasCustomArt ? customLineage : descriptor.lineageName(state.stage, state.lineage);
        string memory form = hasCustomArt ? customForm : descriptor.formName(state.stage, state.lineage, state.form);

        return string.concat(
            '[{"trait_type":"Stage","value":"',
            stageName(state.stage, state.flags),
            '"},{"trait_type":"Lineage","value":"',
            _jsonEscape(lineage),
            '"},{"trait_type":"Form","value":"',
            _jsonEscape(form),
            '"},{"trait_type":"Vibe","value":"',
            _jsonEscape(descriptor.vibeName(state.vibe)),
            '"}]'
        );
    }

    function renderPackedFragment(bytes memory data) public pure returns (string memory) {
        if (data.length < 2) return "";

        uint8 mode = uint8(data[0]);
        uint8 paletteLength = uint8(data[1]);
        uint256 pixelOffset = 2 + uint256(paletteLength) * 3;
        if (mode != MODE_4BIT && mode != MODE_8BIT) return "";
        if (paletteLength == 0 || data.length < pixelOffset) return "";
        if (mode == MODE_4BIT && data.length < pixelOffset + 512) return "";
        if (mode == MODE_8BIT && data.length < pixelOffset + 1024) return "";

        bytes memory output;
        for (uint256 y = 0; y < 32; y++) {
            uint256 x = 0;
            while (x < 32) {
                uint8 colorIndex = _pixelIndex(data, mode, pixelOffset, y * 32 + x);
                if (colorIndex == 0) {
                    x++;
                    continue;
                }
                if (colorIndex > paletteLength) return "";

                uint256 width = 1;
                while (x + width < 32 && _pixelIndex(data, mode, pixelOffset, y * 32 + x + width) == colorIndex) {
                    width++;
                }

                output = bytes.concat(
                    output,
                    bytes("<rect x='"),
                    bytes(x.toString()),
                    bytes("' y='"),
                    bytes(y.toString()),
                    bytes("' width='"),
                    bytes(width.toString()),
                    bytes("' height='1' fill='#"),
                    bytes(_colorHex(data, colorIndex)),
                    bytes("'/>")
                );
                x += width;
            }
        }

        return string(output);
    }

    function wrapSvg(IBlupetsCore.TokenState memory state, string memory fragment)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' shape-rendering='crispEdges'>",
            backgroundRect(state),
            "<g transform='translate(4 4)'>",
            fragment,
            "</g>",
            "</svg>"
        );
    }

    function _pixelIndex(bytes memory data, uint8 mode, uint256 pixelOffset, uint256 pixelPosition)
        internal
        pure
        returns (uint8)
    {
        if (mode == MODE_8BIT) return uint8(data[pixelOffset + pixelPosition]);

        uint8 packedByte = uint8(data[pixelOffset + pixelPosition / 2]);
        if (pixelPosition % 2 == 0) return packedByte >> 4;
        return packedByte & 0x0f;
    }

    function _colorHex(bytes memory data, uint8 colorIndex) internal pure returns (string memory) {
        uint256 offset = 2 + (uint256(colorIndex) - 1) * 3;
        bytes memory result = new bytes(6);
        (result[0], result[1]) = _hexPair(uint8(data[offset]));
        (result[2], result[3]) = _hexPair(uint8(data[offset + 1]));
        (result[4], result[5]) = _hexPair(uint8(data[offset + 2]));
        return string(result);
    }

    function _jsonEscape(string memory value) internal pure returns (string memory) {
        bytes memory input = bytes(value);
        bytes memory output;

        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];
            if (char == bytes1('"')) {
                output = bytes.concat(output, bytes("\\\""));
            } else if (char == bytes1("\\")) {
                output = bytes.concat(output, bytes("\\\\"));
            } else if (char == bytes1("\n")) {
                output = bytes.concat(output, bytes("\\n"));
            } else if (char == bytes1("\r")) {
                output = bytes.concat(output, bytes("\\r"));
            } else if (char == bytes1("\t")) {
                output = bytes.concat(output, bytes("\\t"));
            } else if (uint8(char) >= 0x20) {
                output = bytes.concat(output, abi.encodePacked(char));
            }
        }

        return string(output);
    }

    function _hexPair(uint8 value) internal pure returns (bytes1 high, bytes1 low) {
        bytes16 alphabet = "0123456789ABCDEF";
        high = alphabet[value >> 4];
        low = alphabet[value & 0x0f];
    }

    function fallbackSvg(IBlupetsCore.TokenState memory state) internal pure returns (string memory) {
        string memory front = colorFill(state.lineage);
        string memory top = topFill(state.lineage);

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' shape-rendering='crispEdges'>",
            backgroundRect(state),
            "<g transform='translate(4 4)'>",
            "<rect x='6' y='6' width='20' height='6' fill='",
            top,
            "'/><rect x='5' y='12' width='22' height='14' fill='",
            front,
            "'/><rect x='9' y='16' width='5' height='6' fill='#ffffff'/><rect x='18' y='16' width='5' height='6' fill='#ffffff'/>",
            "<rect x='11' y='17' width='2' height='4' fill='#222222'/><rect x='19' y='17' width='2' height='4' fill='#222222'/>",
            "</g>",
            "</svg>"
        );
    }

    function backgroundRect(IBlupetsCore.TokenState memory state) internal pure returns (string memory) {
        return string.concat("<rect width='40' height='40' fill='", backgroundFill(state.stage, state.lineage), "'/>");
    }

    function backgroundFill(uint8 stage, uint8 lineage) internal pure returns (string memory) {
        if (stage == 0) return "#3E4755";
        if (stage == 1) return "#D7EEF8";
        if (stage == 2) return "#0082CC";
        if (stage == 3) return "#8D30CC";
        if (stage == 4 && lineage == 36) return "#CC2257";
        if (stage == 4) return "#F6B73C";
        return "#3E4755";
    }

    function _customArt(uint256 tokenId)
        internal
        view
        returns (bool active, bytes32 artKey, string memory lineage, string memory form)
    {
        if (address(customArtRegistry) == address(0)) return (false, bytes32(0), "", "");
        try customArtRegistry.customArt(tokenId) returns (
            bool active_, bytes32 artKey_, string memory lineage_, string memory form_
        ) {
            return (active_, artKey_, lineage_, form_);
        } catch {
            return (false, bytes32(0), "", "");
        }
    }

    function stageName(uint8 stage, uint8 flags) internal pure returns (string memory) {
        if (stage == 0) return "Unrevealed";
        if (stage == 1) return "Base";
        if (stage == 2) return "Base Evolved";
        if (stage == 3) return "Advanced";
        if (stage == 4 && (flags & 1) != 0) return "Origin";
        return "Ascended";
    }

    function colorFill(uint8 lineage) internal pure returns (string memory) {
        if (lineage == 0) return "#D9233F";
        if (lineage == 1) return "#E89B11";
        if (lineage == 2) return "#4A923F";
        if (lineage == 3) return "#22AEB7";
        if (lineage == 4) return "#2F6FD0";
        if (lineage == 5) return "#8323CF";
        if (lineage == 6) return "#292930";
        if (lineage == 7) return "#D9D9D3";
        return "#9A968C";
    }

    function topFill(uint8 lineage) internal pure returns (string memory) {
        if (lineage == 0) return "#FF4B45";
        if (lineage == 1) return "#FFD736";
        if (lineage == 2) return "#77C85A";
        if (lineage == 3) return "#54D9D9";
        if (lineage == 4) return "#5AA6F0";
        if (lineage == 5) return "#A965E8";
        if (lineage == 6) return "#3C3B43";
        if (lineage == 7) return "#EDE6D8";
        return "#B8B3A8";
    }
}
