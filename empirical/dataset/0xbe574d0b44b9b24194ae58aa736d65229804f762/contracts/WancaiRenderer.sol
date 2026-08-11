// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {SSTORE2} from "./SSTORE2.sol";

/**
 * @title  WancaiRenderer
 * @notice On-chain SVG + metadata renderer for WANCAI 万财.
 *         Fragment blob (14940 bytes) is stored via SSTORE2 in constructor.
 *         All dispatch reads slices from that blob using compile-time offset table.
 */
contract WancaiRenderer {
    address public immutable fragments;

    bytes constant SVG_HEAD =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="1000" height="1000" shape-rendering="crispEdges">';

    constructor(bytes memory blob) {
        fragments = SSTORE2.write(blob);
    }

    // ============ Fragment slicers ============

    function _slice(uint256 s, uint256 e) internal view returns (bytes memory) {
        return SSTORE2.readSlice(fragments, s, e);
    }

    function corners() internal view returns (bytes memory) {
        return _slice(0, 350);
    }

    function _bgRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (350, 395); // Dark Crimson
        if (i == 1) return (395, 440); // Imperial Gold
        if (i == 2) return (440, 768); // Bamboo Forest
        if (i == 3) return (768, 999); // Sakura Pink
        return (999, 1348); // Cyber Shanghai (default)
    }
    function _patternRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (1348, 1620); // Gold Spots
        if (i == 1) return (1620, 1620); // Plain
        if (i == 2) return (1620, 1852); // 福 Character
        if (i == 3) return (1852, 2207); // Tiger Stripes
        return (2207, 2731); // Dragon Scales (default)
    }
    function _outfitRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (2731, 2731); // None
        if (i == 1) return (2731, 2985); // Imperial Robe
        return (2985, 3303); // Monk Robe (default)
    }
    function _eyeRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (3303, 3963); // Default
        if (i == 1) return (3963, 4230); // Closed Happy
        if (i == 2) return (4230, 4499); // Closed Meditation
        if (i == 3) return (4499, 5034); // Heart
        if (i == 4) return (5034, 6042); // ¥ Yuan
        if (i == 5) return (6042, 6998); // Crying
        return (6998, 7325); // Laser (default)
    }
    function _headwearRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (7325, 7325); // None
        if (i == 1) return (7325, 7719); // Bamboo Douli
        if (i == 2) return (7719, 8012); // Kungfu Headband
        if (i == 3) return (8012, 8244); // Top Hat
        if (i == 4) return (8244, 8711); // Halo
        return (8711, 9332); // Imperial Crown (default)
    }
    function _mouthRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (9332, 9905); // Gold Coin
        if (i == 1) return (9905, 10118); // Empty
        if (i == 2) return (10118, 10543); // Jade Disc
        if (i == 3) return (10543, 10884); // 元宝 Ingot
        if (i == 4) return (10884, 11309); // Bitcoin
        return (11309, 11734); // Silver Coin (default)
    }
    function _baseRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (11734, 12153); // 3 Gold Coins
        if (i == 1) return (12153, 12388); // 元宝 Ingot
        if (i == 2) return (12388, 12913); // Lotus Throne
        if (i == 3) return (12913, 13272); // Bamboo Mat
        if (i == 4) return (13272, 13650); // Green Candle
        return (13650, 14028); // Red Candle (default)
    }
    function _auraRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (14028, 14028); // None
        if (i == 1) return (14028, 14401); // Gold Sparkles
        return (14401, 14669); // Lightning (default)
    }
    function _accessoryRange(uint8 i) internal pure returns (uint256 s, uint256 e) {
        if (i == 0) return (14669, 14669); // None
        return (14669, 14940); // Long Mustache (default)
    }

    function _bg(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _bgRange(i); return _slice(s, e); }
    function _pattern(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _patternRange(i); return _slice(s, e); }
    function _outfit(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _outfitRange(i); return _slice(s, e); }
    function _eye(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _eyeRange(i); return _slice(s, e); }
    function _headwear(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _headwearRange(i); return _slice(s, e); }
    function _mouth(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _mouthRange(i); return _slice(s, e); }
    function _base(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _baseRange(i); return _slice(s, e); }
    function _aura(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _auraRange(i); return _slice(s, e); }
    function _accessory(uint8 i) internal view returns (bytes memory) { (uint256 s, uint256 e) = _accessoryRange(i); return _slice(s, e); }

    function _bodyPalette(uint8 i) internal pure returns (bytes3 main, bytes3 hi, bytes3 sh) {
        if (i == 0) return (bytes3(0x4a8a3a), bytes3(0x6aaa5a), bytes3(0x2a6a1a)); // Jade Green
        if (i == 1) return (bytes3(0xd4a020), bytes3(0xf0d030), bytes3(0xa07010)); // Imperial Gold
        if (i == 2) return (bytes3(0x2a2a3a), bytes3(0x4a4a6a), bytes3(0x0a0a1a)); // Obsidian Black
        if (i == 3) return (bytes3(0xc41020), bytes3(0xe84050), bytes3(0x800a18)); // Ruby Red
        if (i == 5) return (bytes3(0xe8e0d8), bytes3(0xfff8e8), bytes3(0xa8a098)); // Pearl White
        if (i == 7) return (bytes3(0xf0a0b0), bytes3(0xfff0f0), bytes3(0xc87080)); // Cherry Pink
        if (i == 9) return (bytes3(0x8050d0), bytes3(0xb080f0), bytes3(0x5030a0)); // Cyber Neon
        return (bytes3(0x4a8a3a), bytes3(0x6aaa5a), bytes3(0x2a6a1a)); // default
    }

    // ============ Body shapes (inline — only ~700 bytes total) ============

    function _bodyMain(bytes3 main, bytes3 hi, bytes3 sh) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '<g fill="#', _hex(main), '">'
            '<rect x="9" y="11" width="14" height="1"/>'
            '<rect x="7" y="12" width="18" height="1"/>'
            '<rect x="6" y="13" width="20" height="2"/>'
            '<rect x="5" y="15" width="22" height="4"/>'
            '<rect x="6" y="19" width="20" height="2"/>'
            '<rect x="7" y="21" width="18" height="1"/>'
            '<rect x="8" y="22" width="16" height="1"/>'
            '</g>'
            '<g fill="#', _hex(hi), '">'
            '<rect x="7" y="13" width="2" height="2"/>'
            '<rect x="6" y="15" width="2" height="2"/>'
            '</g>'
            '<g fill="#', _hex(sh), '">'
            '<rect x="24" y="17" width="2" height="2"/>'
            '<rect x="22" y="20" width="3" height="1"/>'
            '</g>'
        );
    }

    function _bodyLegs(bytes3 main, bytes3 sh) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '<g fill="#', _hex(main), '">'
            '<rect x="6" y="23" width="3" height="2"/>'
            '<rect x="23" y="23" width="3" height="2"/>'
            '<rect x="14" y="23" width="4" height="1"/>'
            '<rect x="13" y="24" width="6" height="1"/>'
            '</g>'
            '<g fill="#', _hex(sh), '">'
            '<rect x="5" y="25" width="5" height="1"/>'
            '<rect x="22" y="25" width="5" height="1"/>'
            '</g>'
        );
    }

    function _hex(bytes3 c) internal pure returns (bytes memory s) {
        bytes16 H = "0123456789abcdef";
        s = new bytes(6);
        for (uint256 i = 0; i < 3; i++) {
            uint8 b = uint8(c[i]);
            s[i * 2]     = H[b >> 4];
            s[i * 2 + 1] = H[b & 0x0f];
        }
    }

    // ============ Render pipeline ============

    function _renderSVG(uint8[10] memory t) internal view returns (bytes memory) {
        (bytes3 main, bytes3 hi, bytes3 sh) = _bodyPalette(t[1]);
        return abi.encodePacked(
            SVG_HEAD,
            _bg(t[0]),
            corners(),
            _aura(t[8]),
            _bodyMain(main, hi, sh),
            _pattern(t[2]),
            _outfit(t[6]),
            _eye(t[4]),
            _headwear(t[3]),
            _mouth(t[5]),
            _bodyLegs(main, sh),
            _base(t[7]),
            _accessory(t[9]),
            "</svg>"
        );
    }

    // ============ Public entry ============

    function tokenURI(uint256 tokenId, uint8[10] memory traits, uint8 tierIdx)
        external view returns (string memory)
    {
        bytes memory svg = _renderSVG(traits);
        bytes memory json = abi.encodePacked(
            '{"name":"WANCAI #', _pad4(tokenId), unicode' 万财",',
            '"description":"10000 Jin Chan, fully on-chain. First Chinese NFT on ERC-8257.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(svg), '",',
            '"attributes":', _attributes(traits, tierIdx),
            '}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function _attributes(uint8[10] memory t, uint8 tierIdx) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '[',
            _attr("Background", _bgName(t[0])),       ',',
            _attr("Body Color", _bodyName(t[1])),     ',',
            _attr("Body Pattern", _patternName(t[2])), ',',
            _attr("Headwear", _headwearName(t[3])),   ',',
            _attr("Eyes", _eyeName(t[4])),            ',',
            _attr("Mouth", _mouthName(t[5])),         ',',
            _attr("Outfit", _outfitName(t[6])),       ',',
            _attr("Base", _baseName(t[7])),           ',',
            _attr("Aura", _auraName(t[8])),           ',',
            _attr("Accessory", _accessoryName(t[9])), ',',
            _attr("Tier", _tierName(tierIdx)),
            ']'
        );
    }

    function _attr(string memory k, string memory v) internal pure returns (bytes memory) {
        return abi.encodePacked('{"trait_type":"', k, '","value":"', v, '"}');
    }

    function _bgName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Dark Crimson";
        if (i == 1) return "Imperial Gold";
        if (i == 2) return "Bamboo Forest";
        if (i == 3) return "Sakura Pink";
        return "Cyber Shanghai";
    }
    function _patternName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Gold Spots";
        if (i == 1) return "Plain";
        if (i == 2) return unicode"福 Character";
        if (i == 3) return "Tiger Stripes";
        return "Dragon Scales";
    }
    function _outfitName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "None";
        if (i == 1) return "Imperial Robe";
        return "Monk Robe";
    }
    function _eyeName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Default";
        if (i == 1) return "Closed Happy";
        if (i == 2) return "Closed Meditation";
        if (i == 3) return "Heart";
        if (i == 4) return unicode"¥ Yuan";
        if (i == 5) return "Crying";
        return "Laser";
    }
    function _headwearName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "None";
        if (i == 1) return "Bamboo Douli";
        if (i == 2) return "Kungfu Headband";
        if (i == 3) return "Top Hat";
        if (i == 4) return "Halo";
        return "Imperial Crown";
    }
    function _mouthName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Gold Coin";
        if (i == 1) return "Empty";
        if (i == 2) return "Jade Disc";
        if (i == 3) return unicode"元宝 Ingot";
        if (i == 4) return "Bitcoin";
        return "Silver Coin";
    }
    function _baseName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "3 Gold Coins";
        if (i == 1) return unicode"元宝 Ingot";
        if (i == 2) return "Lotus Throne";
        if (i == 3) return "Bamboo Mat";
        if (i == 4) return "Green Candle";
        return "Red Candle";
    }
    function _auraName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "None";
        if (i == 1) return "Gold Sparkles";
        return "Lightning";
    }
    function _accessoryName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "None";
        return "Long Mustache";
    }

    function _bodyName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Jade Green";
        if (i == 1) return "Imperial Gold";
        if (i == 2) return "Obsidian Black";
        if (i == 3) return "Ruby Red";
        if (i == 4) return "Bronze Patina";
        if (i == 5) return "Pearl White";
        if (i == 6) return "Sage Olive";
        if (i == 7) return "Cherry Pink";
        if (i == 8) return "Marble Veined";
        if (i == 9) return "Cyber Neon";
        if (i == 10) return "Cosmic";
        return "Rainbow";
    }

    function _tierName(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Mythic";
        if (i == 1) return "Legendary";
        if (i == 2) return "Epic";
        if (i == 3) return "Rare";
        if (i == 4) return "Uncommon";
        return "Common";
    }

    function _pad4(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(4);
        for (uint256 i = 4; i > 0; i--) {
            b[i - 1] = bytes1(uint8(48 + (n % 10)));
            n /= 10;
        }
        return string(b);
    }
}
