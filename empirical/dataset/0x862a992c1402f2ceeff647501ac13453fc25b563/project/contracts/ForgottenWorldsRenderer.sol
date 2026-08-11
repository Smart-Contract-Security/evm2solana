// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library FWStrings {
    bytes16 private constant HEX = "0123456789abcdef";

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function color(uint24 value) internal pure returns (string memory) {
        bytes memory buffer = new bytes(7);
        buffer[0] = "#";
        for (uint256 i = 0; i < 6; i++) {
            buffer[6 - i] = HEX[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}

library FWBase64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);

        assembly {
            mstore(result, encodedLen)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)

            for {} lt(dataPtr, endPtr) {} {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }

            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }

        return result;
    }
}

contract ForgottenWorldsRenderer {
    using FWStrings for uint256;
    using FWStrings for uint24;

    uint8 private constant SKY_ROWS = 36;
    uint8 private constant GRID = 64;

    struct Palette {
        string name;
        uint24 skyTop;
        uint24 skyHorizon;
        uint24 glow;
        uint24 far;
        uint24 mid;
        uint24 near;
        uint24 water;
        uint24 shimmer;
        uint24 ruin;
        uint24 ruinShade;
        uint24 weather;
        uint24 celestial;
        uint24 halo;
    }

    struct Traits {
        uint8 terrain;
        uint8 skyMood;
        uint8 palette;
        uint8 weather;
        uint8 celestialBody;
        uint8 ruins;
        uint8 waterState;
        uint8 atmosphere;
        uint8 animation;
        uint8 rarityTier;
        uint8 mintPhase;
    }

    function tokenURI(uint256 tokenId) external pure returns (string memory) {
        return tokenURIForPhase(tokenId, _phaseForToken(tokenId));
    }

    function tokenURIForPhase(uint256 tokenId, uint8 phaseId) public pure returns (string memory) {
        string memory image = string.concat(
            "data:image/svg+xml;base64,",
            FWBase64.encode(bytes(svgForPhase(tokenId, phaseId)))
        );
        string memory json = string.concat(
            '{"name":"Forgotten World #',
            tokenId.toString(),
            '","description":"Forgotten Worlds on-chain SVG renderer based on the current JavaScript generator.","image":"',
            image,
            '","attributes":[',
            _attributes(_pickTraits(tokenId, phaseId)),
            "]}"
        );
        return string.concat("data:application/json;base64,", FWBase64.encode(bytes(json)));
    }

    function svg(uint256 tokenId) external pure returns (string memory) {
        return svgForPhase(tokenId, _phaseForToken(tokenId));
    }

    function svgForPhase(uint256 tokenId, uint8 phaseId) public pure returns (string memory) {
        Traits memory traits = _pickTraits(tokenId, phaseId);
        Palette memory pal = _palette(traits.palette);
        return string.concat(_svgOpen(tokenId, pal, traits), _sceneLayers(tokenId, pal, traits), "</svg>");
    }

    function _svgOpen(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="512" height="512" shape-rendering="crispEdges">',
            '<title>Forgotten World #',
            tokenId.toString(),
            "</title><desc>",
            _description(traits),
            '</desc><style>svg{background:',
            pal.skyTop.color(),
            ";image-rendering:pixelated}</style>"
        );
    }

    function _sceneLayers(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        string memory skyAndBody = string.concat(
            drawSky(pal, traits),
            _celestialLayer(tokenId, pal, traits)
        );
        string memory landAndWater = string.concat(
            drawTerrainBack(tokenId, pal, traits),
            _waterLayer(tokenId, pal, traits),
            drawTerrainFront(tokenId, pal, traits)
        );
        return string.concat(skyAndBody, landAndWater, drawRuins(tokenId, pal, traits), _weatherLayer(traits, drawWeather(tokenId, pal, traits)));
    }

    function _celestialLayer(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        string memory body = drawCelestial(tokenId, pal, traits);
        return traits.animation == 4 ? _wrapAnimation("CelestialPulse", body) : body;
    }

    function _waterLayer(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        string memory water = drawWater(tokenId, pal, traits);
        return traits.animation == 1 ? _wrapAnimation("WaterShimmer", water) : water;
    }

    function drawSky(Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        uint24 top = pal.skyTop;
        uint256 atmDark = _atmosphereDark(traits.atmosphere);
        if (atmDark > 0) top = _lerpColor(top, 0x000000, atmDark, 1000);

        string memory out = string.concat(
            '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">',
            '<stop offset="0%" stop-color="',
            top.color(),
            '"/><stop offset="75%" stop-color="',
            pal.skyHorizon.color(),
            '"/><stop offset="100%" stop-color="',
            pal.glow.color(),
            '"/></linearGradient></defs>',
            '<rect x="0" y="0" width="64" height="64" fill="url(#sky)"/>'
        );
        if (traits.skyMood == 0 || traits.skyMood == 2 || traits.skyMood == 3 || traits.skyMood == 4) {
            out = string.concat(out, _rectOp(0, SKY_ROWS - 1, 64, 1, pal.glow.color(), "0.7"));
        }
        return out;
    }

    function drawCelestial(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        if (traits.celestialBody == 0) return "";
        uint8 cx = uint8(12 + (_rand(tokenId, "celestialPlace", 1) % 40));
        uint8 cy = traits.celestialBody == 1 || traits.celestialBody == 4 || traits.celestialBody == 5
            ? uint8(SKY_ROWS - 6 - (_rand(tokenId, "celestialPlace", 2) % 6))
            : uint8(6 + (_rand(tokenId, "celestialPlace", 3) % 14));

        if (traits.celestialBody == 1) {
            return string.concat(_halo(cx, cy, 5, pal.halo), _disk(cx, cy, 5, pal.celestial.color(), ""), _ring(cx, cy, 8, 7, pal.glow.color(), "0.2"));
        }
        if (traits.celestialBody == 2) {
            return string.concat(_halo(cx, cy, 4, pal.halo), _disk(cx, cy, 4, pal.celestial.color(), ""));
        }
        if (traits.celestialBody == 3) {
            uint8 cx2 = _clampU8(int256(uint256(cx)) + 14 + int256(_rand(tokenId, "celestialPlace", 4) % 6), 3, 60);
            uint8 cy2 = _clampU8(int256(uint256(cy)) + (_rand(tokenId, "celestialPlace", 5) % 2 == 0 ? int256(-3) : int256(3)), 3, int256(uint256(SKY_ROWS - 5)));
            return string.concat(_halo(cx, cy, 3, pal.halo), _disk(cx, cy, 3, pal.celestial.color(), ""), _ring(cx2, cy2, 3, 2, pal.halo.color(), "0.4"), _disk(cx2, cy2, 2, pal.celestial.color(), ""));
        }
        if (traits.celestialBody == 4) {
            return string.concat(_halo(cx, cy, 6, pal.halo), _disk(cx, cy, 6, pal.celestial.color(), ""), _disk(cx, cy, 4, pal.skyTop.color(), ""));
        }
        if (traits.celestialBody == 5) {
            return string.concat(
                _halo(cx, cy, 3, pal.halo),
                _disk(cx, cy, 3, pal.celestial.color(), ""),
                _rectOp(cx, cy > 6 ? cy - 6 : 0, 1, 3, pal.halo.color(), "0.7"),
                _rectOp(cx, cy + 4 > 63 ? 63 : cy + 4, 1, 3, pal.halo.color(), "0.7"),
                _rectOp(cx > 6 ? cx - 6 : 0, cy, 3, 1, pal.halo.color(), "0.7"),
                _rectOp(cx + 4 > 63 ? 63 : cx + 4, cy, 3, 1, pal.halo.color(), "0.7")
            );
        }

        return string.concat(
            _halo(cx, cy, 5, pal.halo),
            _disk(cx, cy, 5, pal.celestial.color(), ""),
            _rectOp(cx > 1 ? cx - 1 : 0, cy > 2 ? cy - 2 : 0, 2, 2, pal.skyTop.color(), "0.75"),
            _rectOp(cx + 2, cy + 1, 2, 1, pal.skyTop.color(), "0.65"),
            _rect(cx > 3 ? cx - 3 : 0, cy + 2, 1, 1, pal.skyTop.color())
        );
    }

    function drawTerrainBack(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        return string.concat(_drawTerrainLayer(tokenId, traits, 0, pal.far.color()), _drawTerrainLayer(tokenId, traits, 1, pal.mid.color()));
    }

    function drawTerrainFront(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        return _drawTerrainLayer(tokenId, traits, 2, pal.near.color());
    }

    function drawWater(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        if (traits.waterState == 4) return "";
        uint8 surface = _waterSurface(traits.terrain);
        if (surface >= GRID) return "";
        string memory out = string.concat(_rect(0, surface, 64, uint8(64 - surface), pal.water.color()), _rectOp(0, surface, 64, 1, pal.shimmer.color(), "0.35"));
        uint8 shimmerCount = traits.waterState == 2 ? 14 : traits.waterState == 3 ? 18 : 8;
        uint8 lineRows = surface + 6 > 63 ? 63 : surface + 6;
        for (uint8 i = 0; i < shimmerCount; i++) {
            out = string.concat(out, _waterShimmerLine(tokenId, i, surface, lineRows, pal.shimmer.color()));
        }
        if (traits.waterState == 0) {
            for (uint8 j = 0; j < 5; j++) {
                out = string.concat(out, _waterDeepLine(tokenId, j, surface, pal.shimmer.color()));
            }
        }
        return out;
    }

    function drawRuins(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        if (traits.ruins == 0) return "";
        uint8 count = traits.ruins == 4 ? 1 : uint8(1 + (_rand(tokenId, "ruins", 0) % 10 < 4 ? 1 : 0));
        string memory out;
        for (uint8 i = 0; i < count; i++) {
            uint8 x = uint8(8 + (_rand(tokenId, "ruins", i + 1) % 48));
            if (i == 1) x = x > 32 ? x - 18 : x + 18;
            uint8 baseY = _nearHeight(tokenId, traits, x);
            if (traits.ruins == 1) out = string.concat(out, _brokenPillar(x, baseY, pal));
            else if (traits.ruins == 2) out = string.concat(out, _fallenArch(x, baseY, pal));
            else if (traits.ruins == 3) out = string.concat(out, _tombStones(x, baseY, pal));
            else out = string.concat(out, _cityShard(x, baseY, pal));
        }
        return out;
    }

    function drawWeather(uint256 tokenId, Palette memory pal, Traits memory traits) internal pure returns (string memory) {
        if (traits.weather == 0) return "";
        uint256 boost = traits.atmosphere == 0 ? 10 : traits.atmosphere == 1 ? 12 : traits.atmosphere == 2 ? 13 : 14;
        string memory out;

        if (traits.weather == 1) {
            for (uint8 i = 0; i < 4; i++) {
                uint8 y = uint8(SKY_ROWS - 2 + i + (_rand(tokenId, "weather", i) % 2));
                out = string.concat(out, _rectOp(0, y, 64, 1, pal.weather.color(), _opacity(6 + i * 4)));
            }
            return out;
        }

        uint256 count = traits.weather == 2 ? (30 * boost) / 10 : traits.weather == 3 ? (25 * boost) / 10 : traits.weather == 4 ? (25 * boost) / 10 : (35 * boost) / 10;
        if (traits.weather == 2 && count > 35) count = 35;
        else if (traits.weather == 3 && count > 30) count = 30;
        else if (traits.weather == 4 && count > 30) count = 30;
        else if (count > 40) count = 40;
        for (uint256 i2 = 0; i2 < count; i2++) {
            out = string.concat(out, _weatherParticle(tokenId, i2, traits.weather, pal.weather.color()));
        }
        return out;
    }

    function _pickTraits(uint256 tokenId, uint8 phaseId) internal pure returns (Traits memory t) {
        if (phaseId > 3) phaseId = 3;
        t.mintPhase = phaseId;
        t.terrain = _pickTerrain(tokenId, phaseId);
        t.skyMood = _pickSky(tokenId, phaseId);
        t.weather = _pickWeather(tokenId, phaseId);
        t.celestialBody = _pickCelestial(tokenId, phaseId);
        t.ruins = _pickRuins(tokenId, phaseId);
        t.waterState = _pickWater(tokenId, phaseId);
        t.atmosphere = _pickAtmosphere(tokenId, phaseId);
        t.animation = _pickAnimation(tokenId, phaseId);
        t.palette = _pickPalette(tokenId, phaseId, t.skyMood);
        t = _resolveTraits(tokenId, t);
        t.rarityTier = _deriveRarity(t);
    }

    function _resolveTraits(uint256 tokenId, Traits memory t) internal pure returns (Traits memory) {
        if (t.waterState == 4 && (t.terrain == 3 || t.terrain == 4)) t.terrain = 2;
        if (t.waterState == 4 && t.animation == 1) t.animation = t.mintPhase == 0 ? 0 : 3;
        if (t.animation == 2 && !(t.weather == 2 || t.weather == 3 || t.weather == 4 || t.weather == 5)) t.animation = 3;
        if (t.weather == 4 && t.skyMood == 0 && t.atmosphere == 0) t.weather = 1;
        if (t.terrain == 4 && t.ruins == 0 && _rand(tokenId, "resolve", 1) % 10 < 8) t.ruins = _rand(tokenId, "resolve", 2) % 2 == 0 ? 1 : 2;
        if (t.animation == 4 && t.celestialBody == 0) t.animation = 3;
        return t;
    }

    function _attributes(Traits memory t) internal pure returns (string memory) {
        string memory a = string.concat(
            _trait("Mint Phase", _phaseName(t.mintPhase)),
            ",",
            _trait("Terrain", _terrainName(t.terrain)),
            ",",
            _trait("Sky Mood", _skyName(t.skyMood)),
            ",",
            _trait("Weather", _weatherName(t.weather))
        );
        string memory b = string.concat(
            _trait("Celestial Body", _celestialName(t.celestialBody)),
            ",",
            _trait("Ruins", _ruinsName(t.ruins)),
            ",",
            _trait("Water State", _waterName(t.waterState)),
            ",",
            _trait("Atmosphere", _atmosphereName(t.atmosphere))
        );
        string memory c = string.concat(
            _trait("Animation", _animationName(t.animation)),
            ",",
            _trait("Palette", _palette(t.palette).name),
            ",",
            _trait("Rarity Tier", _rarityName(t.rarityTier))
        );
        return string.concat(a, ",", b, ",", c);
    }

    function _description(Traits memory t) internal pure returns (string memory) {
        return string.concat(
            _phaseName(t.mintPhase),
            " | ",
            _terrainName(t.terrain),
            " | ",
            _skyName(t.skyMood),
            " | ",
            _weatherName(t.weather),
            " | ",
            _celestialName(t.celestialBody),
            " | ",
            _ruinsName(t.ruins),
            " | ",
            _waterName(t.waterState),
            " | ",
            _atmosphereName(t.atmosphere),
            " | ",
            _animationName(t.animation),
            " | ",
            _rarityName(t.rarityTier)
        );
    }

    function _drawTerrainLayer(uint256 tokenId, Traits memory traits, uint8 layer, string memory fill) internal pure returns (string memory) {
        string memory out;
        uint8 runStart = 0;
        uint8 runH = _heightAt(tokenId, traits, layer, 0);
        for (uint8 x = 1; x <= GRID; x++) {
            if (x == GRID || _heightAt(tokenId, traits, layer, x) != runH) {
                out = string.concat(out, _rect(runStart, runH, x - runStart, uint8(64 - runH), fill));
                if (x < GRID) {
                    runStart = x;
                    runH = _heightAt(tokenId, traits, layer, x);
                }
            }
        }
        return out;
    }

    function _heightAt(uint256 tokenId, Traits memory traits, uint8 layer, uint8 x) internal pure returns (uint8) {
        (uint8 baseRow, uint8 amp, uint8 profile) = _terrainProfile(traits.terrain, layer);
        uint256 seg = (uint256(x) * 7) / 63;
        uint256 f = (uint256(x) * 7 * 1000) / 63 - seg * 1000;
        uint256 a = _rand(tokenId, _layerLabel(layer), seg) % 1000;
        uint256 b = _rand(tokenId, _layerLabel(layer), seg + 1) % 1000;
        uint256 v = ((a * (1000 - f)) + (b * f)) / 1000;
        if (profile == 1) v = _sqrt(v * 1000);
        else if (profile == 2) v = 400 + (v * 200) / 1000;
        else if (profile == 3) v = ((v * 4) / 1000) * 1000 / 3;

        int256 row = int256(uint256(baseRow)) - int256((v * amp) / 1000);
        return _clampU8(row, int256(uint256(SKY_ROWS - 2)), 63);
    }

    function _nearHeight(uint256 tokenId, Traits memory traits, uint8 x) internal pure returns (uint8) {
        uint8 best = 64;
        for (uint8 i = 0; i < 3; i++) {
            uint8 xi = x;
            if (i == 0 && x > 0) xi = x - 1;
            if (i == 2 && x < 63) xi = x + 1;
            uint8 h = _heightAt(tokenId, traits, 2, xi);
            if (h < best) best = h;
        }
        return best;
    }

    function _terrainProfile(uint8 terrain, uint8 layer) internal pure returns (uint8 baseRow, uint8 amp, uint8 profile) {
        if (terrain == 1) return layer == 0 ? (37, 7, 1) : layer == 1 ? (41, 9, 1) : (48, 11, 1);
        if (terrain == 2) return layer == 0 ? (39, 2, 2) : layer == 1 ? (44, 3, 2) : (50, 4, 2);
        if (terrain == 3) return layer == 0 ? (38, 3, 0) : layer == 1 ? (43, 4, 0) : (52, 5, 0);
        if (terrain == 4) return layer == 0 ? (40, 3, 0) : layer == 1 ? (44, 4, 0) : (49, 4, 0);
        if (terrain == 5) return layer == 0 ? (38, 5, 3) : layer == 1 ? (43, 6, 3) : (49, 8, 3);
        return layer == 0 ? (38, 4, 0) : layer == 1 ? (42, 6, 0) : (48, 8, 0);
    }

    function _palette(uint8 id) internal pure returns (Palette memory) {
        if (id == 0) return Palette("First Dawn", 0x1b2a4a, 0xf4c27a, 0xffd9a0, 0x5a6e7d, 0x3f5260, 0x243944, 0x3a6b8a, 0xcfe6f2, 0xcbb497, 0x6f5d49, 0xe6eef5, 0xffe7b3, 0xffb978);
        if (id == 1) return Palette("Pale Ash", 0x2a2730, 0xbcaeb0, 0xd8c4bf, 0x6a626a, 0x4b4550, 0x2c2830, 0x4a505c, 0xb9c0c8, 0xa99b8e, 0x574e49, 0xdadada, 0xe6dfd5, 0x9a8d8a);
        if (id == 2) return Palette("Convergence", 0x0d0f2b, 0x7a3b8a, 0xc46ad1, 0x3d3a5a, 0x2a2745, 0x171530, 0x2c3a6b, 0x9ab2ff, 0x9a8fb0, 0x3a3450, 0xc8c2ff, 0xf0d3ff, 0x7a3b8a);
        if (id == 3) return Palette("Ruinfall", 0x160a0a, 0x7a2a1c, 0xc45a2a, 0x4a2a26, 0x2f1c1a, 0x170d0c, 0x3b2a2a, 0xc47a5a, 0x8a6a55, 0x3a2a22, 0xe6884a, 0xffb070, 0xa93a1a);
        if (id == 4) return Palette("Burned Horizon", 0x0a0000, 0xa01000, 0xff5a1a, 0x3a1a14, 0x220c0a, 0x0c0403, 0x2a0a08, 0xff7a3a, 0x705a4a, 0x2a1a14, 0xff8a3a, 0xff3010, 0x5a0500);
        if (id == 5) return Palette("Glass Sea", 0x08283a, 0x7ad3e0, 0xcfeef3, 0x3a6a78, 0x244a58, 0x12303a, 0x2b8aa0, 0xe8fbff, 0xa8c8d0, 0x3a5a64, 0xd0eef6, 0xeaffff, 0x7ad3e0);
        return Palette("Verdant", 0x173042, 0xe6c47a, 0xffe2a0, 0x3a5a3a, 0x244a2a, 0x13301a, 0x2e6a64, 0xb5e6cf, 0xc6b487, 0x5a4a30, 0xdff0d6, 0xfff0c0, 0xe6c47a);
    }

    function _pickPalette(uint256 tokenId, uint8 phaseId, uint8 skyMood) internal pure returns (uint8) {
        if (_rand(tokenId, "palette", 0) % 100 < 75) {
            if (skyMood == 0) return 0;
            if (skyMood == 1) return 1;
            if (skyMood == 2) return 2;
            if (skyMood == 3) return 3;
            if (skyMood == 4) return 4;
            return 6;
        }
        uint256 roll = _rand(tokenId, "palette", 1) % 100;
        if (phaseId == 0) return roll < 40 ? 0 : roll < 65 ? 1 : roll < 75 ? 2 : roll < 80 ? 3 : roll < 90 ? 5 : 6;
        if (phaseId == 1) return roll < 5 ? 0 : roll < 30 ? 1 : roll < 70 ? 2 : roll < 85 ? 3 : roll < 90 ? 4 : roll < 95 ? 5 : 6;
        if (phaseId == 2) return roll < 20 ? 1 : roll < 35 ? 2 : roll < 70 ? 3 : roll < 90 ? 4 : roll < 95 ? 5 : 6;
        return roll < 10 ? 1 : roll < 20 ? 2 : roll < 45 ? 3 : roll < 90 ? 4 : roll < 95 ? 5 : 6;
    }

    function _pickTerrain(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "terrain", 0) % 100;
        if (phaseId == 0) return r < 40 ? 0 : r < 60 ? 1 : r < 70 ? 2 : r < 80 ? 3 : r < 95 ? 4 : 5;
        if (phaseId == 1) return r < 30 ? 0 : r < 55 ? 1 : r < 70 ? 2 : r < 85 ? 3 : r < 95 ? 4 : 5;
        if (phaseId == 2) return r < 15 ? 0 : r < 40 ? 1 : r < 65 ? 2 : r < 80 ? 3 : r < 90 ? 4 : 5;
        return r < 5 ? 0 : r < 30 ? 1 : r < 60 ? 2 : r < 70 ? 3 : r < 75 ? 4 : 5;
    }

    function _pickSky(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "sky", 0) % 100;
        if (phaseId == 0) return r < 45 ? 0 : r < 65 ? 1 : r < 75 ? 2 : r < 80 ? 3 : r < 85 ? 4 : 5;
        if (phaseId == 1) return r < 15 ? 0 : r < 40 ? 1 : r < 75 ? 2 : r < 85 ? 3 : r < 95 ? 4 : 5;
        if (phaseId == 2) return r < 5 ? 0 : r < 30 ? 1 : r < 50 ? 2 : r < 65 ? 3 : r < 90 ? 4 : 5;
        return r < 15 ? 1 : r < 25 ? 2 : r < 45 ? 3 : r < 80 ? 4 : 5;
    }

    function _pickWeather(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "weather", 0) % 100;
        if (phaseId == 0) return r < 55 ? 0 : r < 75 ? 1 : r < 85 ? 2 : r < 95 ? 3 : 5;
        if (phaseId == 1) return r < 30 ? 0 : r < 55 ? 1 : r < 75 ? 2 : r < 85 ? 3 : r < 90 ? 4 : 5;
        if (phaseId == 2) return r < 15 ? 0 : r < 35 ? 1 : r < 55 ? 2 : r < 65 ? 3 : r < 85 ? 4 : 5;
        return r < 10 ? 0 : r < 20 ? 1 : r < 25 ? 2 : r < 30 ? 3 : r < 65 ? 4 : 5;
    }

    function _pickCelestial(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "celestial", 0) % 100;
        if (phaseId == 0) return r < 10 ? 0 : r < 55 ? 1 : r < 75 ? 2 : r < 85 ? 3 : r < 90 ? 4 : r < 95 ? 5 : 6;
        if (phaseId == 1) return r < 5 ? 0 : r < 20 ? 1 : r < 50 ? 2 : r < 75 ? 3 : r < 90 ? 4 : r < 95 ? 5 : 6;
        if (phaseId == 2) return r < 5 ? 0 : r < 10 ? 1 : r < 30 ? 2 : r < 50 ? 3 : r < 75 ? 4 : r < 90 ? 5 : 6;
        return r < 5 ? 0 : r < 15 ? 2 : r < 30 ? 3 : r < 55 ? 4 : r < 85 ? 5 : 6;
    }

    function _pickRuins(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "ruins", 0) % 100;
        if (phaseId == 0) return r < 45 ? 0 : r < 70 ? 1 : r < 85 ? 2 : r < 95 ? 3 : 4;
        if (phaseId == 1) return r < 25 ? 0 : r < 55 ? 1 : r < 75 ? 2 : r < 90 ? 3 : 4;
        if (phaseId == 2) return r < 10 ? 0 : r < 35 ? 1 : r < 60 ? 2 : r < 80 ? 3 : 4;
        return r < 5 ? 0 : r < 20 ? 1 : r < 40 ? 2 : r < 65 ? 3 : 4;
    }

    function _pickWater(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "water", 0) % 100;
        if (phaseId == 0) return r < 50 ? 1 : r < 75 ? 2 : r < 90 ? 3 : r < 95 ? 0 : 4;
        if (phaseId == 1) return r < 30 ? 1 : r < 60 ? 2 : r < 80 ? 3 : r < 90 ? 0 : 4;
        if (phaseId == 2) return r < 20 ? 1 : r < 45 ? 2 : r < 60 ? 3 : r < 80 ? 0 : 4;
        return r < 10 ? 1 : r < 25 ? 2 : r < 35 ? 3 : r < 60 ? 0 : 4;
    }

    function _pickAtmosphere(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "atmosphere", 0) % 100;
        if (phaseId == 0) return r < 55 ? 0 : r < 80 ? 1 : r < 90 ? 2 : 3;
        if (phaseId == 1) return r < 25 ? 0 : r < 60 ? 1 : r < 80 ? 2 : 3;
        if (phaseId == 2) return r < 10 ? 0 : r < 35 ? 1 : r < 65 ? 2 : 3;
        return r < 5 ? 0 : r < 20 ? 1 : r < 55 ? 2 : 3;
    }

    function _pickAnimation(uint256 tokenId, uint8 phaseId) internal pure returns (uint8) {
        uint256 r = _rand(tokenId, "animation", 0) % 100;
        if (phaseId == 0) return r < 50 ? 0 : r < 75 ? 1 : r < 90 ? 2 : 3;
        if (phaseId == 1) return r < 30 ? 0 : r < 55 ? 1 : r < 80 ? 2 : r < 95 ? 3 : 4;
        if (phaseId == 2) return r < 25 ? 0 : r < 45 ? 1 : r < 75 ? 2 : r < 90 ? 3 : 4;
        return r < 20 ? 0 : r < 35 ? 1 : r < 65 ? 2 : r < 80 ? 3 : 4;
    }

    function _deriveRarity(Traits memory t) internal pure returns (uint8) {
        uint8 score;
        if (t.terrain == 5) score += 2;
        else if (t.terrain == 4 || t.terrain == 3) score += 1;
        if (t.skyMood == 4) score += 2;
        else if (t.skyMood == 3 || t.skyMood == 2) score += 1;
        if (t.celestialBody == 6 || t.celestialBody == 5) score += 2;
        else if (t.celestialBody == 4) score += 1;
        if (t.weather == 5) score += 2;
        else if (t.weather == 4) score += 1;
        if (t.ruins == 4) score += 2;
        else if (t.ruins == 3) score += 1;
        if (t.atmosphere == 3) score += 2;
        else if (t.atmosphere == 2) score += 1;
        score += t.mintPhase;
        if (score >= 11) return 5;
        if (score >= 8) return 4;
        if (score >= 6) return 3;
        if (score >= 4) return 2;
        if (score >= 2) return 1;
        return 0;
    }

    function _phaseForToken(uint256 tokenId) internal pure returns (uint8) {
        if (tokenId <= 1000) return 0;
        if (tokenId <= 1300) return 1;
        if (tokenId <= 1800) return 2;
        return 3;
    }

    function _brokenPillar(uint8 x, uint8 baseY, Palette memory pal) internal pure returns (string memory) {
        uint8 h = uint8(4 + ((uint256(x) * 13) % 3));
        uint8 top = baseY > h ? baseY - h : 0;
        return string.concat(_rect(x, top, 2, h, pal.ruin.color()), _rect(x + 1, top, 1, h, pal.ruinShade.color()), _rectOp(x, top, 1, 1, pal.skyTop.color(), "0.4"));
    }

    function _fallenArch(uint8 x, uint8 baseY, Palette memory pal) internal pure returns (string memory) {
        return string.concat(_rect(x, baseY - 4, 1, 4, pal.ruin.color()), _rect(x + 4, baseY - 5, 1, 5, pal.ruin.color()), _rect(x + 5, baseY - 5, 1, 5, pal.ruinShade.color()), _rect(x, baseY - 5, 3, 1, pal.ruin.color()), _rect(x + 3, baseY - 5, 1, 1, pal.ruinShade.color()));
    }

    function _tombStones(uint8 x, uint8 baseY, Palette memory pal) internal pure returns (string memory) {
        return string.concat(_rect(x, baseY - 3, 2, 3, pal.ruin.color()), _rect(x + 1, baseY - 3, 1, 3, pal.ruinShade.color()), _rect(x + 3, baseY - 2, 1, 2, pal.ruin.color()), _rect(x + 5, baseY - 4, 2, 4, pal.ruin.color()), _rect(x + 6, baseY - 4, 1, 4, pal.ruinShade.color()));
    }

    function _cityShard(uint8 x, uint8 baseY, Palette memory pal) internal pure returns (string memory) {
        uint8 h = 9;
        return string.concat(_rect(x, baseY - h, 4, h, pal.ruin.color()), _rect(x + 3, baseY - h, 1, h, pal.ruinShade.color()), _rect(x + 1, baseY - h + 2, 1, 1, pal.skyTop.color()), _rect(x + 1, baseY - h + 5, 1, 1, pal.skyTop.color()), _rectOp(x + 2, baseY - h, 2, 1, pal.skyTop.color(), "0.6"), _rect(x + 5, baseY - 2, 2, 2, pal.ruinShade.color()));
    }

    function _wrapAnimation(string memory animation, string memory inner) internal pure returns (string memory) {
        if (bytes(inner).length == 0) return "";
        if (_eq(animation, "Falling")) return string.concat('<g>', inner, '<animateTransform attributeName="transform" type="translate" from="0 -6" to="0 6" dur="2s" repeatCount="indefinite"/></g>');
        if (_eq(animation, "Drift")) return string.concat('<g>', inner, '<animateTransform attributeName="transform" type="translate" from="-3 0" to="3 0" dur="6s" repeatCount="indefinite"/></g>');
        if (_eq(animation, "WaterShimmer")) return string.concat('<g>', inner, '<animate attributeName="opacity" values="0.8;1;0.8" dur="3s" repeatCount="indefinite"/></g>');
        return string.concat('<g>', inner, '<animate attributeName="opacity" values="0.85;1;0.85" dur="4s" repeatCount="indefinite"/></g>');
    }

    function _weatherLayer(Traits memory traits, string memory weather) internal pure returns (string memory) {
        if (traits.animation == 2) return _wrapAnimation("Falling", weather);
        if (traits.animation == 3) return _wrapAnimation("Drift", weather);
        return weather;
    }

    function _rect(uint8 x, uint8 y, uint8 width, uint8 height, string memory fill) internal pure returns (string memory) {
        return string.concat('<rect x="', uint256(x).toString(), '" y="', uint256(y).toString(), '" width="', uint256(width).toString(), '" height="', uint256(height).toString(), '" fill="', fill, '"/>');
    }

    function _rectOp(uint8 x, uint8 y, uint8 width, uint8 height, string memory fill, string memory opacity) internal pure returns (string memory) {
        return string.concat('<rect x="', uint256(x).toString(), '" y="', uint256(y).toString(), '" width="', uint256(width).toString(), '" height="', uint256(height).toString(), '" fill="', fill, '" opacity="', opacity, '"/>');
    }

    function _disk(uint8 cx, uint8 cy, uint8 r, string memory fill, string memory opacity) internal pure returns (string memory) {
        string memory out;
        for (uint8 yy = 0; yy <= r * 2; yy++) {
            int256 y = int256(uint256(cy)) + int256(uint256(yy)) - int256(uint256(r));
            if (y < 0 || y > 63) continue;
            int256 dy = y - int256(uint256(cy));
            uint256 dx = _sqrt(uint256(int256(uint256(r * r)) - dy * dy));
            uint8 x0 = _clampU8(int256(uint256(cx)) - int256(dx), 0, 63);
            uint8 x1 = _clampU8(int256(uint256(cx)) + int256(dx), 0, 63);
            out = string.concat(out, bytes(opacity).length == 0 ? _rect(x0, uint8(uint256(y)), x1 - x0 + 1, 1, fill) : _rectOp(x0, uint8(uint256(y)), x1 - x0 + 1, 1, fill, opacity));
        }
        return out;
    }

    function _ring(uint8 cx, uint8 cy, uint8 outer, uint8 inner, string memory fill, string memory opacity) internal pure returns (string memory) {
        return string.concat(_disk(cx, cy, outer, fill, opacity), _disk(cx, cy, inner, _palette(1).skyTop.color(), "1"));
    }

    function _halo(uint8 cx, uint8 cy, uint8 r, uint24 colorValue) internal pure returns (string memory) {
        string memory c = colorValue.color();
        return string.concat(_ring(cx, cy, r + 2, r + 1, c, "0.25"), _ring(cx, cy, r + 1, r, c, "0.45"));
    }

    function _waterSurface(uint8 terrain) internal pure returns (uint8) {
        if (terrain == 4) return SKY_ROWS + 4;
        if (terrain == 3) return SKY_ROWS + 6;
        if (terrain == 2) return SKY_ROWS + 14;
        if (terrain == 5) return SKY_ROWS + 16;
        return SKY_ROWS + 12;
    }

    function _waterShimmerLine(uint256 tokenId, uint8 i, uint8 surface, uint8 lineRows, string memory fill) internal pure returns (string memory) {
        uint8 y = uint8(surface + 1 + (_rand(tokenId, "water", i) % (lineRows - surface)));
        uint8 len = uint8(3 + (_rand(tokenId, "water", i + 41) % 12));
        uint8 x = uint8(_rand(tokenId, "water", i + 83) % (64 - len));
        string memory op = _opacity(15 + (_rand(tokenId, "water", i + 121) % 45));
        return _rectOp(x, y, len, 1, fill, op);
    }

    function _waterDeepLine(uint256 tokenId, uint8 i, uint8 surface, string memory fill) internal pure returns (string memory) {
        uint8 len = uint8(6 + (_rand(tokenId, "water", i + 167) % 10));
        uint8 x = uint8(_rand(tokenId, "water", i + 181) % (64 - len));
        uint8 y = uint8(surface + 2 + (_rand(tokenId, "water", i + 191) % (62 - surface)));
        return _rectOp(x, y, len, 1, fill, "0.1");
    }

    function _weatherParticle(uint256 tokenId, uint256 i, uint8 weather, string memory fill) internal pure returns (string memory) {
        if (weather == 4) return _emberParticle(tokenId, i, fill);
        if (weather == 5) return _ashParticle(tokenId, i, fill);
        uint8 x = uint8(_rand(tokenId, "weather", i + 11) % 64);
        uint8 y = uint8(2 + (_rand(tokenId, "weather", i + 211) % 59));
        if (weather == 2) return _rectOp(x, y, 1, 2, fill, "0.8");
        if (weather == 3) return _rectOp(x, y, 1, 1, fill, "0.9");
        return "";
    }

    function _emberParticle(uint256 tokenId, uint256 i, string memory fill) internal pure returns (string memory) {
        uint8 x = uint8(_rand(tokenId, "weather", i + 11) % 64);
        uint8 y = uint8(2 + (_rand(tokenId, "weather", i + 211) % 57));
        uint8 h = _rand(tokenId, "weather", i + 411) % 10 < 2 ? 2 : 1;
        string memory op = _opacity(60 + (_rand(tokenId, "weather", i + 511) % 40));
        return _rectOp(x, y, 1, h, fill, op);
    }

    function _ashParticle(uint256 tokenId, uint256 i, string memory fill) internal pure returns (string memory) {
        uint8 x = uint8(_rand(tokenId, "weather", i + 11) % 64);
        uint8 y = uint8(2 + (_rand(tokenId, "weather", i + 211) % 59));
        uint8 len = uint8(2 + (_rand(tokenId, "weather", i + 611) % 3));
        if (x + len > 64) len = 64 - x;
        string memory op = _opacity(25 + (_rand(tokenId, "weather", i + 711) % 50));
        return _rectOp(x, y, len, 1, fill, op);
    }

    function _skyTuning(uint8 skyMood) internal pure returns (uint256 glow, uint8 width) {
        if (skyMood == 0) return (550, 10);
        if (skyMood == 1) return (200, 6);
        if (skyMood == 2) return (450, 12);
        if (skyMood == 3) return (650, 8);
        if (skyMood == 4) return (750, 14);
        return (350, 8);
    }

    function _atmosphereDark(uint8 atmosphere) internal pure returns (uint256) {
        if (atmosphere == 1) return 50;
        if (atmosphere == 2) return 120;
        if (atmosphere == 3) return 180;
        return 0;
    }

    function _lerpColor(uint24 a, uint24 b, uint256 step, uint256 maxStep) internal pure returns (uint24) {
        uint8 ar = uint8(a >> 16);
        uint8 ag = uint8(a >> 8);
        uint8 ab = uint8(a);
        uint8 br = uint8(b >> 16);
        uint8 bg = uint8(b >> 8);
        uint8 bb = uint8(b);
        return (uint24(_lerpChannel(ar, br, step, maxStep)) << 16) | (uint24(_lerpChannel(ag, bg, step, maxStep)) << 8) | uint24(_lerpChannel(ab, bb, step, maxStep));
    }

    function _lerpChannel(uint8 a, uint8 b, uint256 step, uint256 maxStep) internal pure returns (uint8) {
        if (b >= a) return uint8(uint256(a) + ((uint256(b - a) * step) / maxStep));
        return uint8(uint256(a) - ((uint256(a - b) * step) / maxStep));
    }

    function _opacity(uint256 percent) internal pure returns (string memory) {
        if (percent >= 100) return "1";
        if (percent < 10) return string.concat("0.0", percent.toString());
        return string.concat("0.", percent.toString());
    }

    function _trait(string memory key, string memory value) internal pure returns (string memory) {
        return string.concat('{"trait_type":"', key, '","value":"', value, '"}');
    }

    function _rand(uint256 tokenId, string memory label, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenId, label, salt)));
    }

    function _layerLabel(uint8 layer) internal pure returns (string memory) {
        if (layer == 0) return "terrainFar";
        if (layer == 1) return "terrainMid";
        return "terrainNear";
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _clampU8(int256 value, int256 minValue, int256 maxValue) internal pure returns (uint8) {
        if (value < minValue) return uint8(uint256(minValue));
        if (value > maxValue) return uint8(uint256(maxValue));
        return uint8(uint256(value));
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _phaseName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "Phase 1 - First Dawn";
        if (id == 1) return "Phase 2 - Convergence";
        if (id == 2) return "Phase 3 - Ruinfall";
        return "Phase 4 - Burned Horizon";
    }

    function _terrainName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "RollingHills";
        if (id == 1) return "JaggedPeaks";
        if (id == 2) return "AshenPlains";
        if (id == 3) return "SunkenIsles";
        if (id == 4) return "FloodedWorld";
        return "ShatteredMesa";
    }

    function _skyName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "ClearDawn";
        if (id == 1) return "PaleAsh";
        if (id == 2) return "Convergence";
        if (id == 3) return "Eclipse";
        if (id == 4) return "Bloodlight";
        return "Verdant";
    }

    function _weatherName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "Calm";
        if (id == 1) return "Mist";
        if (id == 2) return "Rain";
        if (id == 3) return "Snow";
        if (id == 4) return "Embers";
        return "AshStorm";
    }

    function _celestialName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "None";
        if (id == 1) return "RisingSun";
        if (id == 2) return "PaleMoon";
        if (id == 3) return "TwinMoons";
        if (id == 4) return "EclipsedSun";
        if (id == 5) return "BloodStar";
        return "ShatteredOrb";
    }

    function _ruinsName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "None";
        if (id == 1) return "BrokenPillar";
        if (id == 2) return "FallenArch";
        if (id == 3) return "TombStones";
        return "CityShard";
    }

    function _waterName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "Sunken";
        if (id == 1) return "Calm";
        if (id == 2) return "Rippled";
        if (id == 3) return "Reflective";
        return "Dry";
    }

    function _atmosphereName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "Clean";
        if (id == 1) return "Hazy";
        if (id == 2) return "Smoky";
        return "Otherworldly";
    }

    function _animationName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "None";
        if (id == 1) return "WaterShimmer";
        if (id == 2) return "Falling";
        if (id == 3) return "Drift";
        return "CelestialPulse";
    }

    function _rarityName(uint8 id) internal pure returns (string memory) {
        if (id == 0) return "Common";
        if (id == 1) return "Uncommon";
        if (id == 2) return "Rare";
        if (id == 3) return "Epic";
        if (id == 4) return "Legendary";
        return "Mythic";
    }
}
