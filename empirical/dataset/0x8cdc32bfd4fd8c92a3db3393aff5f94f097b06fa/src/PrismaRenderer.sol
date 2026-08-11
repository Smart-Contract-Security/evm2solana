// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

library PrismaRenderer {
    using Strings for uint256;

    struct TokenTraits {
        string backgroundName;
        string coreName;
        uint256 rings;
        uint256 shards;
        uint256 rarityScore;
        string rarityClass;
        uint256 seed;
    }

    function render(TokenTraits memory traits, uint256 tokenId, string memory collectionName)
        internal
        pure
        returns (string memory)
    {
        string memory svg = _svg(traits, tokenId, collectionName);
        string memory image = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));

        string memory json = string(
            abi.encodePacked(
                '{"name":"',
                collectionName,
                " #",
                tokenId.toString(),
                '","description":"A premium on-chain NFT generated with mathematical formulas.","image":"',
                image,
                '","attributes":[',
                _attr("Collection", collectionName),
                ",",
                _attr("Token ID", tokenId.toString()),
                ",",
                _attr("Background Theme", traits.backgroundName),
                ",",
                _attr("Core Type", traits.coreName),
                ",",
                _attr("Geometry Rings", traits.rings.toString()),
                ",",
                _attr("Shard Count", traits.shards.toString()),
                ",",
                _attr("Rarity Class", traits.rarityClass),
                ",",
                _attr("Rarity Score", traits.rarityScore.toString()),
                "]}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _svg(TokenTraits memory traits, uint256 tokenId, string memory collectionName)
        private
        pure
        returns (string memory)
    {
        (string memory bg0, string memory bg1) = _background(traits.backgroundName);
        (string memory cL0, string memory cL1, string memory cR0, string memory cR1) =
            _core(traits.coreName);
        string memory ringStroke = keccak256(bytes(traits.rarityClass)) == keccak256(bytes("Legendary"))
            ? "#ffd700"
            : "#ffffff";

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">',
                "<defs>",
                '<radialGradient id="bg" cx="50%" cy="50%" r="70%">',
                '<stop offset="0%" stop-color="',
                bg0,
                '"/>',
                '<stop offset="100%" stop-color="',
                bg1,
                '"/>',
                "</radialGradient>",
                '<linearGradient id="left" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" stop-color="',
                cL0,
                '"/>',
                '<stop offset="100%" stop-color="',
                cL1,
                '"/>',
                "</linearGradient>",
                '<linearGradient id="right" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" stop-color="',
                cR0,
                '"/>',
                '<stop offset="100%" stop-color="',
                cR1,
                '"/>',
                "</linearGradient>",
                '<filter id="blur"><feGaussianBlur stdDeviation="18"/></filter>',
                "</defs>",
                '<rect width="1000" height="1000" fill="url(#bg)"/>',
                '<circle cx="500" cy="500" r="280" fill="#6e40c8" opacity="0.10" filter="url(#blur)"/>',
                '<circle cx="500" cy="500" r="180" fill="#f6d365" opacity="0.08" filter="url(#blur)"/>',
                _stars(traits.seed),
                _rings(traits.rings),
                '<circle cx="500" cy="500" r="340" fill="none" stroke="#ffffff0f" stroke-width="2"/>',
                '<circle cx="500" cy="500" r="250" fill="none" stroke="',
                ringStroke,
                '" stroke-width="4" opacity="0.15"/>',
                '<path d="M500 160 L360 430 L500 720 L640 430 Z" fill="url(#left)"/>',
                '<path d="M500 160 L640 430 L500 720 L360 430 Z" fill="url(#right)" fill-opacity="0.88"/>',
                '<path d="M500 160 L360 430 L500 720 L640 430 Z" fill="none" stroke="#ffffffcc" stroke-width="2" opacity="0.9"/>',
                '<path d="M500 160 L640 430 L500 720 L360 430 Z" fill="none" stroke="#ffffffaa" stroke-width="2" opacity="0.7"/>',
                '<path d="M500 160 L500 720" stroke="#ffffff88" stroke-width="2"/>',
                _shards(traits.shards, traits.seed),
                '<circle cx="500" cy="500" r="72" fill="none" stroke="#ffffff26" stroke-width="3"/>',
                '<text x="500" y="865" fill="#f3f4f6" font-family="monospace" font-size="32" text-anchor="middle">',
                collectionName,
                " #",
                tokenId.toString(),
                "</text>",
                '<text x="500" y="910" fill="#9ca3af" font-family="monospace" font-size="18" text-anchor="middle">',
                traits.rarityClass,
                " | ",
                traits.rarityScore.toString(),
                "</text>",
                "</svg>"
            )
        );
    }

    function _background(string memory name) private pure returns (string memory, string memory) {
        if (keccak256(bytes(name)) == keccak256(bytes("Deep Space"))) return ("#111424", "#010204");
        if (keccak256(bytes(name)) == keccak256(bytes("Cyberpunk Purple"))) return ("#431252", "#08020e");
        if (keccak256(bytes(name)) == keccak256(bytes("Legendary Gold"))) return ("#4d3910", "#0b0802");
        return ("#2a2d45", "#050608");
    }

    function _core(string memory name)
        private
        pure
        returns (string memory, string memory, string memory, string memory)
    {
        if (keccak256(bytes(name)) == keccak256(bytes("Fire Ruby"))) {
            return ("#ff0844", "#ffb199", "#f857a6", "#ff5858");
        }
        if (keccak256(bytes(name)) == keccak256(bytes("Emerald Green"))) {
            return ("#0ba360", "#3cba92", "#13547a", "#80d0c7");
        }
        if (keccak256(bytes(name)) == keccak256(bytes("Cosmic Void"))) {
            return ("#300840", "#08000a", "#6a11cb", "#2575fc");
        }
        if (keccak256(bytes(name)) == keccak256(bytes("Pure Sapphire"))) {
            return ("#1e3c72", "#2a5298", "#e0c3fc", "#8ec5fc");
        }
        return ("#4facfe", "#00f2fe", "#fee140", "#fa709a");
    }

    function _attr(string memory traitType, string memory value) private pure returns (string memory) {
        return string(abi.encodePacked('{"trait_type":"', traitType, '","value":"', value, '"}'));
    }

    function _rings(uint256 ringCount) private pure returns (string memory out) {
        for (uint256 i = 1; i <= ringCount; ++i) {
            out = string(
                abi.encodePacked(
                    out,
                    '<circle cx="500" cy="500" r="',
                    (80 + i * 60).toString(),
                    '" fill="none" stroke="#ffffff1a" stroke-width="4"/>'
                )
            );
        }
    }

    function _stars(uint256 seed) private pure returns (string memory out) {
        uint256 localSeed = seed;
        for (uint256 i = 0; i < 120; ++i) {
            localSeed = uint256(keccak256(abi.encodePacked(localSeed, i, "star")));
            uint256 x = localSeed % 1000;
            localSeed = uint256(keccak256(abi.encodePacked(localSeed, "y")));
            uint256 y = localSeed % 1000;
            out = string(
                abi.encodePacked(
                    out,
                    '<circle cx="',
                    x.toString(),
                    '" cy="',
                    y.toString(),
                    '" r="',
                    uint256(i % 2 == 0 ? 1 : 2).toString(),
                    '" fill="#ffffff" opacity="',
                    (i % 5 == 0 ? "0.20" : "0.08"),
                    '"/>'
                )
            );
        }
    }

    function _shards(uint256 shardCount, uint256 seed) private pure returns (string memory out) {
        uint256 localSeed = seed;
        for (uint256 i = 0; i < shardCount; ++i) {
            localSeed = uint256(keccak256(abi.encodePacked(localSeed, i)));
            uint256 x = 300 + (localSeed % 400);
            localSeed = uint256(keccak256(abi.encodePacked(localSeed, "y")));
            uint256 y = 300 + (localSeed % 400);
            localSeed = uint256(keccak256(abi.encodePacked(localSeed, "s")));
            uint256 size = 6 + (localSeed % 12);

            out = string(
                abi.encodePacked(
                    out,
                    '<path d="M',
                    x.toString(),
                    " ",
                    (y - size).toString(),
                    " L",
                    (x + size / 2).toString(),
                    " ",
                    (y + size / 2).toString(),
                    " L",
                    (x - size / 2).toString(),
                    " ",
                    (y + size / 2).toString(),
                    '" fill="#ffffff99"/>'
                )
            );
        }
    }
}
