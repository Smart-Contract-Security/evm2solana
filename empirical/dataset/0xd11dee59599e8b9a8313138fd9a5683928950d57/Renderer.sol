// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface ISpriteData {
    function speciesName(uint8) external pure returns (string memory);
    function bodyVariantName(uint8, uint8) external pure returns (string memory);
    function headwearName(uint8) external pure returns (string memory);
    function weaponName(uint8) external pure returns (string memory);
    function capeName(uint8) external pure returns (string memory);
    function backgroundName(uint8) external pure returns (string memory);
    function effectName(uint8) external pure returns (string memory);
    function pickHeadwear(uint256) external pure returns (uint8, uint8);
    function pickWeapon(uint256) external pure returns (uint8, uint8);
    function pickCape(uint256) external pure returns (uint8, uint8);
    function pickBackground(uint256) external pure returns (uint8, uint8);
    function pickEffect(uint256) external pure returns (uint8, uint8);
    function pickBodyVariant(uint8, uint256) external pure returns (uint8, uint8);
    function partyhatHeadwearIdx(uint8) external pure returns (uint8);
    function dragonDaggerWeaponIdx() external pure returns (uint8);
    function dragonSpearWeaponIdx() external pure returns (uint8);
    function capeSVG(uint8) external pure returns (string memory);
    function backgroundBGColor(uint8, uint8) external pure returns (string memory);
    function backgroundOverlay(uint8) external pure returns (string memory);
    function effectSVG(uint8) external pure returns (string memory);
}

interface ISpriteDataSpecies {
    function speciesSVG(uint8) external pure returns (string memory);
    function variantSwaps(uint8, uint8) external pure returns (
        string memory, string memory, string memory, string memory,
        string memory, string memory, string memory, string memory
    );
}

interface ISpriteDataHeadwear {
    function headwearSVG(uint8) external pure returns (string memory);
}

interface ISpriteDataWeapons {
    function weaponSVG(uint8) external pure returns (string memory);
}

interface ISpriteDataShields {
    function shieldName(uint8) external pure returns (string memory);
    function pickShield(uint256) external pure returns (uint8, uint8);
    function shieldSVG(uint8) external pure returns (string memory);
}

interface ISpriteDataIcons {
    function oneOfOneFullSVG(uint256) external pure returns (string memory);
}

interface IRenderer {
    function renderTokenURI(uint256, uint256, uint8) external view returns (string memory);
}

/**
 * @title Renderer
 * @notice Composes the final SVG + JSON metadata at tokenURI time.
 *         Orchestrates calls across 5 data contracts and applies variant
 *         color swaps via _replaceFour() (up to 4 substitutions per sprite).
 */
contract Renderer is IRenderer {
    using Strings for uint256;

    ISpriteData         public immutable data;
    ISpriteDataSpecies  public immutable speciesData;
    ISpriteDataHeadwear public immutable headwearData;
    ISpriteDataWeapons  public immutable weaponsData;
    ISpriteDataShields  public immutable shieldsData;
    ISpriteDataIcons    public immutable iconsData;

    string[5] private ONE_OF_ONE_NAMES = ["Doge", "Shib", "WIF", "Pepe", "Moodeng"];

    uint256 private constant ONE_OF_ONES = 5;

    constructor(
        address _data,
        address _species,
        address _headwear,
        address _weapons,
        address _shields,
        address _icons
    ) {
        data         = ISpriteData(_data);
        speciesData  = ISpriteDataSpecies(_species);
        headwearData = ISpriteDataHeadwear(_headwear);
        weaponsData  = ISpriteDataWeapons(_weapons);
        shieldsData  = ISpriteDataShields(_shields);
        iconsData    = ISpriteDataIcons(_icons);
    }

    // ============ ENTRY ============

    function renderTokenURI(uint256 tokenId, uint256 slot, uint8 kind)
        external
        view
        override
        returns (string memory)
    {
        string memory svg = _buildSVG(tokenId, slot, kind);
        string memory image = string(abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        ));

        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name":"', _name(tokenId, slot, kind),
            '","description":"Onchainimals - 4,444 fully onchain SVG pixel animals on Ethereum. No IPFS. No off-chain dependency.",',
            '"image":"', image, '",',
            '"attributes":', _attrs(tokenId, slot, kind),
            '}'
        ))));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // ============ SVG COMPOSITION ============

    function _buildSVG(uint256 tokenId, uint256 slot, uint8 kind)
        internal
        view
        returns (string memory)
    {
        if (kind == 1) {
            // 1/1 — return the bespoke full SVG (already includes <svg> wrapper)
            return iconsData.oneOfOneFullSVG(slot);
        }

        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId, slot)));
        Traits memory t = _rollTraits(seed, slot, kind);

        // Apply variant color swaps to base species sprite
        string memory species = speciesData.speciesSVG(t.speciesIdx);
        if (t.bodyVariant > 0) {
            species = _applyVariant(species, t.speciesIdx, t.bodyVariant);
        }

        string memory headwear = headwearData.headwearSVG(t.headwear);
        if (bytes(headwear).length > 0) {
            bool isHweenMask = t.headwear >= 17 && t.headwear <= 20;
            if (isHweenMask) {
                // H'ween masks: align with each species' eye y-position
                if (t.speciesIdx == 2) {
                    // Frog eyes at y=6-7, shift mask up 2
                    headwear = string(abi.encodePacked('<g transform="translate(0,-2)">', headwear, '</g>'));
                } else if (t.speciesIdx == 5) {
                    // Ape eyes at y=9, shift mask down 1
                    headwear = string(abi.encodePacked('<g transform="translate(0,1)">', headwear, '</g>'));
                }
            }
        }

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="', data.backgroundBGColor(t.background, t.speciesIdx), '"/>',
            data.backgroundOverlay(t.background),
            data.capeSVG(t.cape),
            species,
            headwear,
            weaponsData.weaponSVG(t.weapon),
            shieldsData.shieldSVG(t.shield),
            data.effectSVG(t.effect),
            '</svg>'
        ));
    }

    struct Traits {
        uint8 speciesIdx;
        uint8 bodyVariant;
        uint8 headwear;
        uint8 weapon;
        uint8 shield;
        uint8 cape;
        uint8 background;
        uint8 effect;
        uint8 tier;
    }

    function _rollTraits(uint256 seed, uint256 slot, uint8 kind)
        internal
        view
        returns (Traits memory t)
    {
        t.speciesIdx = uint8(seed % 6);
        seed >>= 8;

        uint8 bvT;
        (t.bodyVariant, bvT) = data.pickBodyVariant(t.speciesIdx, seed);
        seed >>= 16;

        uint8 hwT;
        (t.headwear, hwT) = data.pickHeadwear(seed);
        seed >>= 16;

        // Sleeping Cap (idx 7) + Santa Hat (idx 16) don't fit on frog (2), ape (5), penguin (4) — swap to None
        if ((t.headwear == 7 || t.headwear == 16) && (t.speciesIdx == 2 || t.speciesIdx == 4 || t.speciesIdx == 5)) {
            t.headwear = 0;
            hwT = 0;
        }

        uint8 wpT;
        (t.weapon, wpT) = data.pickWeapon(seed);
        seed >>= 16;

        uint8 shT;
        (t.shield, shT) = shieldsData.pickShield(seed);
        seed >>= 16;

        uint8 cpT;
        (t.cape, cpT) = data.pickCape(seed);
        seed >>= 16;

        uint8 bgT;
        (t.background, bgT) = data.pickBackground(seed);
        seed >>= 16;

        uint8 efT;
        (t.effect, efT) = data.pickEffect(seed);

        // Special-kind overrides
        if (kind == 2) {
            uint256 colorIdx = (slot - ONE_OF_ONES) / 10;
            t.headwear = data.partyhatHeadwearIdx(uint8(colorIdx));
            hwT = 4;
        } else if (kind == 3) {
            t.weapon = data.dragonDaggerWeaponIdx();
            wpT = 2;
        } else if (kind == 4) {
            t.weapon = data.dragonSpearWeaponIdx();
            wpT = 3;
        }

        t.tier = bvT;
        if (hwT > t.tier) t.tier = hwT;
        if (wpT > t.tier) t.tier = wpT;
        if (shT > t.tier) t.tier = shT;
        if (cpT > t.tier) t.tier = cpT;
        if (bgT > t.tier) t.tier = bgT;
        if (efT > t.tier) t.tier = efT;
        if (kind == 2) t.tier = 4;
    }

    // ============ VARIANT COLOR SWAPS ============

    function _applyVariant(string memory svg, uint8 speciesIdx, uint8 variantIdx)
        internal
        view
        returns (string memory)
    {
        (string memory f1, string memory t1,
         string memory f2, string memory t2,
         string memory f3, string memory t3,
         string memory f4, string memory t4) = speciesData.variantSwaps(speciesIdx, variantIdx);

        bytes memory b = bytes(svg);
        if (bytes(f1).length > 0) b = _replace(b, bytes(f1), bytes(t1));
        if (bytes(f2).length > 0) b = _replace(b, bytes(f2), bytes(t2));
        if (bytes(f3).length > 0) b = _replace(b, bytes(f3), bytes(t3));
        if (bytes(f4).length > 0) b = _replace(b, bytes(f4), bytes(t4));
        return string(b);
    }

    function _replace(bytes memory haystack, bytes memory needle, bytes memory replacement)
        internal
        pure
        returns (bytes memory)
    {
        uint256 hlen = haystack.length;
        uint256 nlen = needle.length;
        if (nlen == 0 || nlen > hlen) return haystack;

        bytes memory result = new bytes(0);
        uint256 i = 0;
        while (i <= hlen - nlen) {
            bool m = true;
            for (uint256 j = 0; j < nlen; j++) {
                if (haystack[i + j] != needle[j]) { m = false; break; }
            }
            if (m) {
                result = abi.encodePacked(result, replacement);
                i += nlen;
            } else {
                result = abi.encodePacked(result, haystack[i]);
                i++;
            }
        }
        // Append remaining bytes that couldn't have started a match
        for (uint256 k = i; k < hlen; k++) {
            result = abi.encodePacked(result, haystack[k]);
        }
        return result;
    }

    // ============ METADATA ============

    function _name(uint256 tokenId, uint256 slot, uint8 kind)
        internal
        view
        returns (string memory)
    {
        if (kind == 1) return string(abi.encodePacked(ONE_OF_ONE_NAMES[slot], " (1/1)"));
        return string(abi.encodePacked("Onchainimal #", tokenId.toString()));
    }

    function _attrs(uint256 tokenId, uint256 slot, uint8 kind)
        internal
        view
        returns (string memory)
    {
        if (kind == 1) {
            return string(abi.encodePacked(
                '[{"trait_type":"Type","value":"1/1 Unique"},',
                '{"trait_type":"Name","value":"', ONE_OF_ONE_NAMES[slot], '"},',
                '{"trait_type":"Tier","value":"Mythic"}]'
            ));
        }

        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId, slot)));
        Traits memory t = _rollTraits(seed, slot, kind);

        return string(abi.encodePacked(
            abi.encodePacked(
                '[{"trait_type":"Species","value":"', data.speciesName(t.speciesIdx), '"},',
                '{"trait_type":"Body","value":"', data.bodyVariantName(t.speciesIdx, t.bodyVariant), '"},',
                '{"trait_type":"Headwear","value":"', data.headwearName(t.headwear), '"},',
                '{"trait_type":"Weapon","value":"', data.weaponName(t.weapon), '"},',
                '{"trait_type":"Shield","value":"', shieldsData.shieldName(t.shield), '"},'
            ),
            abi.encodePacked(
                '{"trait_type":"Cape","value":"', data.capeName(t.cape), '"},',
                '{"trait_type":"Background","value":"', data.backgroundName(t.background), '"},',
                '{"trait_type":"Effect","value":"', data.effectName(t.effect), '"},',
                '{"trait_type":"Tier","value":"', _tierName(t.tier), '"}]'
            )
        ));
    }

    function _tierName(uint8 tier) internal pure returns (string memory) {
        if (tier == 0) return "Common";
        if (tier == 1) return "Rare";
        if (tier == 2) return "Epic";
        if (tier == 3) return "Legendary";
        return "Mythic";
    }
}
