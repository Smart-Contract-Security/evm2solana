// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SVG} from "./SVG.sol";

/// @title TierAccents — animations and tier-exclusive overlays
/// @notice Adds SMIL flames, embers, halo glow, etc. Onchain-safe (no external assets).
library TierAccents {

    /// @notice Return tier accent overlay layer (drawn AFTER figure — flames, embers, halo).
    function render(uint8 tier) public pure returns (string memory) {
        if (tier == 3) return _lanternFlames();
        if (tier == 4) return _emberDrowned();
        if (tier == 5) return _riverbornHalo();
        return "";
    }

    /// @notice Return tier backdrop (drawn BEFORE figure — throne arch for Mythic, etc.)
    function backdrop(uint8 tier) public pure returns (string memory) {
        if (tier == 5) return _riverbornThrone();
        return "";
    }

    /// @dev Mythic-only arched throne backdrop (placed behind the figure).
    function _riverbornThrone() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<g stroke="', SVG.INK, '" fill="none">',
            '<path d="M 155 225 Q 155 155 215 135 Q 300 120 385 135 Q 445 155 445 225" stroke-width="2.4"/>',
            '<line x1="155" y1="225" x2="155" y2="440" stroke-width="2"/>',
            '<line x1="445" y1="225" x2="445" y2="440" stroke-width="2"/>',
            '<path d="M 180 190 Q 300 168 420 190" stroke-width="0.8"/>',
            '<path d="M 195 210 Q 300 188 405 210" stroke-width="0.8"/>',
            '<line x1="160" y1="230" x2="160" y2="430" stroke-width="0.5"/>',
            '<line x1="165" y1="230" x2="165" y2="430" stroke-width="0.5"/>',
            '<line x1="440" y1="230" x2="440" y2="430" stroke-width="0.5"/>',
            '<line x1="435" y1="230" x2="435" y2="430" stroke-width="0.5"/>',
            '</g>'
        ));
    }

    // ----------------------------------------------------------
    // Tier 3 — Lanternward — animated lantern flames
    // ----------------------------------------------------------

    function _lanternFlames() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<g transform="translate(170, 320)" stroke="', SVG.INK, '" stroke-width="1.4" fill="none">',
            '<rect x="-12" y="-20" width="24" height="32" stroke-width="1.4"/>',
            '<line x1="-12" y1="-12" x2="12" y2="-12"/>',
            '<path d="M 0 -22 Q -4 -34 0 -42 Q 4 -34 0 -22 Z" fill="', SVG.EMBER, '" stroke="none">',
            '<animate attributeName="d" dur="2s" repeatCount="indefinite" ',
            'values="M 0 -22 Q -4 -34 0 -42 Q 4 -34 0 -22 Z;',
            'M 0 -22 Q -5 -32 0 -40 Q 5 -32 0 -22 Z;',
            'M 0 -22 Q -4 -34 0 -42 Q 4 -34 0 -22 Z"/>',
            '</path></g>',
            '<g transform="translate(430, 320)" stroke="', SVG.INK, '" stroke-width="1.4" fill="none">',
            '<rect x="-12" y="-20" width="24" height="32" stroke-width="1.4"/>',
            '<line x1="-12" y1="-12" x2="12" y2="-12"/>',
            '<path d="M 0 -22 Q -4 -34 0 -42 Q 4 -34 0 -22 Z" fill="', SVG.EMBER, '" stroke="none">',
            '<animate attributeName="d" dur="2.4s" repeatCount="indefinite" ',
            'values="M 0 -22 Q -4 -34 0 -42 Q 4 -34 0 -22 Z;',
            'M 0 -22 Q -3 -33 0 -40 Q 3 -33 0 -22 Z;',
            'M 0 -22 Q -4 -34 0 -42 Q 4 -34 0 -22 Z"/>',
            '</path></g>'
        ));
    }

    // ----------------------------------------------------------
    // Tier 4 — Ember-Drowned — drifting embers around the figure
    // ----------------------------------------------------------

    function _emberDrowned() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<g fill="', SVG.EMBER, '">',
            '<circle cx="160" cy="380" r="3">',
            '<animate attributeName="cy" dur="3s" values="380;240;380" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="3s" values="0.9;0.3;0.9" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="200" cy="420" r="2.4">',
            '<animate attributeName="cy" dur="2.6s" values="420;260;420" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="2.6s" values="0.8;0.2;0.8" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="240" cy="440" r="2">',
            '<animate attributeName="cy" dur="3.4s" values="440;280;440" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="3.4s" values="0.7;0.2;0.7" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="360" cy="430" r="2.6">',
            '<animate attributeName="cy" dur="2.8s" values="430;250;430" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="2.8s" values="0.85;0.25;0.85" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="410" cy="400" r="3">',
            '<animate attributeName="cy" dur="3.2s" values="400;240;400" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="3.2s" values="0.9;0.3;0.9" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="440" cy="430" r="2.2">',
            '<animate attributeName="cy" dur="3.6s" values="430;270;430" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="3.6s" values="0.8;0.2;0.8" repeatCount="indefinite"/>',
            '</circle>',
            '</g>'
        ));
    }

    // ----------------------------------------------------------
    // Tier 5 — Riverborn — golden halo + ascending light particles
    // ----------------------------------------------------------

    function _riverbornHalo() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<g transform="translate(300, 250)" fill="none" stroke="', SVG.GOLD, '">',
            '<circle cx="0" cy="0" r="92" stroke-width="2.4" opacity="0.85">',
            '<animate attributeName="r" dur="5s" values="90;96;90" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="0" cy="0" r="78" stroke-width="0.8" opacity="0.55"/>',
            '</g>',
            '<g transform="translate(300, 250)" fill="', SVG.GOLD, '">',
            '<circle cx="0" cy="-88" r="2"/>',
            '<circle cx="44" cy="-76" r="1.8"/>',
            '<circle cx="76" cy="-44" r="1.8"/>',
            '<circle cx="88" cy="0" r="2"/>',
            '<circle cx="76" cy="44" r="1.8"/>',
            '<circle cx="44" cy="76" r="1.8"/>',
            '<circle cx="-44" cy="76" r="1.8"/>',
            '<circle cx="-76" cy="44" r="1.8"/>',
            '<circle cx="-88" cy="0" r="2"/>',
            '<circle cx="-76" cy="-44" r="1.8"/>',
            '<circle cx="-44" cy="-76" r="1.8"/>',
            '</g>',
            '<g fill="', SVG.GOLD, '">',
            '<circle cx="200" cy="430" r="2.4">',
            '<animate attributeName="cy" dur="4s" values="430;230;430" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="4s" values="0.9;0;0.9" repeatCount="indefinite"/>',
            '</circle>',
            '<circle cx="400" cy="430" r="2.4">',
            '<animate attributeName="cy" dur="4.4s" values="430;230;430" repeatCount="indefinite"/>',
            '<animate attributeName="opacity" dur="4.4s" values="0.9;0;0.9" repeatCount="indefinite"/>',
            '</circle>',
            '</g>'
        ));
    }
}
