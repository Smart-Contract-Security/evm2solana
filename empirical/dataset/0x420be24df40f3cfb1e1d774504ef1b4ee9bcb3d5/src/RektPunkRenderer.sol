// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BgLib}     from "./parts/BgLib.sol";
import {SkullLib}  from "./parts/SkullLib.sol";
import {CrackLib}  from "./parts/CrackLib.sol";
import {MouthLib}  from "./parts/MouthLib.sol";
import {HoodieLib} from "./parts/HoodieLib.sol";
import {EyesLib}   from "./parts/EyesLib.sol";
import {HeadLib}   from "./parts/HeadLib.sol";
import {LogoLib}   from "./parts/LogoLib.sol";
import {FxLib}     from "./parts/FxLib.sol";

/// @title RektPunk fully-onchain SVG renderer
/// @notice Stateless wrt user input. Trait rendering is delegated to 9 external libs
///         (one per trait category) to stay under the 24 KB EIP-170 contract size limit.
contract RektPunkRenderer {
    string[9] private TRAIT_LABELS = [
        "Background", "Skull", "Eyes", "Mouth",
        "Head", "Crack", "Hoodie", "Logo", "FX"
    ];

    string[12][9] private TRAIT_NAMES = [
        ["Crimson Dark","Toxic Night","Cyber Deep","Gold Dusk","Void Purple","Blood Moon","Arctic Black","Neon Abyss","Sky Blue","Mint Green","Hot Pink","Sunshine Yellow"],
        ["Bone White","Toxic Tint","Ice Blue","Gold Plated","Phantom","Bleached","Ash Grey","Obsidian","Emerald","Ruby Red","Amethyst","Desert Sand"],
        ["X-Eyes Red","Biohazard","Spiral Cyan","Diamond Gold","Void Dots","Laser Red","Heart Pink","Dead Empty","Cyber Green","Neon Orange","Electric Violet","Ice White"],
        ["Pixel Teeth","Gas Mask","Bandana","Fang Grin","Gold Grillz","Missing Teeth","Vampire Fangs","Bubblegum","","","",""],
        ["None","Crown","Horns","Visor","Beanie","Mohawk","Halo","Headphones","Top Hat","","",""],
        ["Standard","Branching","Lightning","None","Golden","Glowing","Crescent","Cross","","","",""],
        ["Midnight","Forest","Ocean","Void Black","Crimson","White","Camo","Neon","Cyber Yellow","Bubblegum Pink","Toxic Green","Royal Blue"],
        ["REKT","Biohazard","Dollar","Void","Skull","None","Circuit","Flame","Diamond","Heart","",""],
        ["Glitch","Blood Drip","Sparkle","Smoke","Rain","Fire","None","Lightning","Matrix","Snow","",""]
    ];

    /// @notice Build the full SVG for a punk from its 9 traits.
    /// @param t [bg, skull, eyes, mouth, head, crack, hoodie, logo, fx]
    function renderSVG(uint8[9] memory t) public view returns (string memory) {
        string memory body = string(abi.encodePacked(
            BgLib.background(t[0]),
            HoodieLib.hoodie(t[6], t[2]),
            SkullLib.skull(t[1]),
            CrackLib.crack(t[5], t[2])
        ));
        string memory face = string(abi.encodePacked(
            MouthLib.mouth(t[3], t[1]),
            EyesLib.eyes(t[2])
        ));
        string memory over = string(abi.encodePacked(
            HeadLib.head(t[4], t[2]),
            LogoLib.logo(t[7], t[2]),
            FxLib.fx(t[8], t[2])
        ));

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" shape-rendering="crispEdges" width="512" height="512">',
            body, face, over,
            '</svg>'
        ));
    }

    function tokenURI(uint256 tokenId, uint8[9] memory t) external view returns (string memory) {
        string memory svg = renderSVG(t);
        string memory json = string(abi.encodePacked(
            '{"name":"Rekt Punks #', Strings.toString(tokenId),
            '","description":"Fully onchain Rekt Punk. 32x32 pixel SVG rendered from packed trait data.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
            '","attributes":', _attributes(t), '}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _attributes(uint8[9] memory t) internal view returns (string memory out) {
        out = "[";
        for (uint256 i = 0; i < 9; i++) {
            string memory v = TRAIT_NAMES[i][t[i]];
            out = string(abi.encodePacked(
                out,
                i == 0 ? "" : ",",
                '{"trait_type":"', TRAIT_LABELS[i],
                '","value":"', v, '"}'
            ));
        }
        out = string(abi.encodePacked(out, "]"));
    }
}
