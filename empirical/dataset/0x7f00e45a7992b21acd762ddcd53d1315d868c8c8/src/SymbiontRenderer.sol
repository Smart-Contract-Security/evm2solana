// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SymbiontRenderer {
    
    function generateSVG(
        uint256 tokenId,
        address owner,
        uint256 health,
        uint256 balanceAtMint,
        uint256 rarityTier
    ) external view returns (string memory) {
        uint256 seed = uint256(keccak256(abi.encodePacked(owner, tokenId)));
        
        // 4 visual tiers
        // 0=Common, 1=Rare, 2=Epic, 3=Legendary
        uint256 stage = rarityTier;
        
        // Glow intensity based on health (10-100%)
        uint256 glow = 10 + (health * 90) / 100;
        
        // Base size increases with rarity
        uint256 base = 30 + (stage * 8) + (_random(seed, 0) % 15);
        
        // Colors per stage
        // Common: deep teal
        // Rare: teal + blue
        // Epic: bright cyan
        // Legendary: cyan + gold
        string memory bc; // body color
        string memory gc; // glow color
        string memory tc; // tentacle color
        string memory ac; // accent color (legendary only)
        
        if (stage == 3) {
            bc = "#00e5c7";
            gc = "#fffbe6";
            tc = "#7df9ff";
            ac = "#ffd700";
        } else if (stage == 2) {
            bc = "#00e5c7";
            gc = "#7df9ff";
            tc = "#7df9ff";
            ac = "#00e5c7";
        } else if (stage == 1) {
            bc = "#00b4d8";
            gc = "#00e5c7";
            tc = "#00e5c7";
            ac = "#00b4d8";
        } else {
            bc = "#005f5f";
            gc = "#00b4d8";
            tc = "#00b4d8";
            ac = "#005f5f";
        }
        
        string memory op = _concat("0.", _uint2str(glow));
        
        // --- Build SVG ---
        string memory svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">';
        
        // Defs with glow filter
        svg = _concat(svg, '<defs>');
        svg = _concat(svg, '<filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="');
        svg = _concat(svg, _uint2str(glow / 3));
        svg = _concat(svg, '"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>');
        // Legendary: gold aura filter
        if (stage == 3) {
            svg = _concat(svg, '<filter id="gold" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="');
            svg = _concat(svg, _uint2str(glow / 2));
            svg = _concat(svg, '"/></filter>');
        }
        svg = _concat(svg, '</defs>');
        
        // Background
        svg = _concat(svg, '<rect width="400" height="400" fill="#050a14"/>');
        
        // Particles (more with higher stage)
        uint256 particleCount = 5 + stage * 4;
        for (uint256 i = 0; i < particleCount; i++) {
            svg = _concat(svg, '<circle cx="');
            svg = _concat(svg, _uint2str((_random(seed, 100 + i) % 360) + 20));
            svg = _concat(svg, '" cy="');
            svg = _concat(svg, _uint2str((_random(seed, 200 + i) % 360) + 20));
            svg = _concat(svg, '" r="');
            svg = _concat(svg, _uint2str((_random(seed, 300 + i) % 3) + 1));
            svg = _concat(svg, '" fill="#7df9ff" opacity="0.');
            svg = _concat(svg, _uint2str((_random(seed, 400 + i) % 40) + 20));
            svg = _concat(svg, '"/>');
        }
        
        // Legendary: outer gold aura ring
        if (stage == 3) {
            svg = _concat(svg, '<circle cx="200" cy="200" r="');
            svg = _concat(svg, _uint2str(base + 60));
            svg = _concat(svg, '" fill="none" stroke="#ffd700" stroke-width="1.5" opacity="0.15" filter="url(#gold)"/>');
            svg = _concat(svg, '<circle cx="200" cy="200" r="');
            svg = _concat(svg, _uint2str(base + 45));
            svg = _concat(svg, '" fill="none" stroke="#ffd700" stroke-width="1" opacity="0.25" filter="url(#gold)"/>');
        }
        
        // --- Left organism (geometric/teal) ---
        uint256 lr = base + (_random(seed, 10) % 10);
        uint256 lb = base + (_random(seed, 11) % 15);
        svg = _addEllipse(svg, 130, 200, lr, lb, bc, op);
        svg = _addEllipse(svg, 130, 200, lr * 6 / 10, lb * 6 / 10, gc, op);
        
        // --- Right organism (fluid/cyan) ---
        uint256 rr = base + (_random(seed, 12) % 10);
        uint256 rb = base + (_random(seed, 13) % 15);
        svg = _addEllipse(svg, 270, 200, rr, rb, bc, op);
        svg = _addEllipse(svg, 270, 200, rr * 6 / 10, rb * 6 / 10, gc, op);
        
        // --- Tentacles (2/4/6/8 based on stage) ---
        uint256 tentacleCount = 2 + (stage * 2); // Common=2, Rare=4, Epic=6, Legendary=8
        for (uint256 i = 0; i < tentacleCount; i++) {
            uint256 sy = 160 + (i * 80 / tentacleCount);
            uint256 sx = 130 + (_random(seed, 50 + i) % 20);
            uint256 ey = sy + (_random(seed, 60 + i) % 10);
            uint256 ex = 270 - (_random(seed, 70 + i) % 20);
            
            svg = _concat(svg, '<path d="M');
            svg = _concat(svg, _uint2str(sx));
            svg = _concat(svg, ",");
            svg = _concat(svg, _uint2str(sy));
            svg = _concat(svg, " C");
            svg = _concat(svg, _uint2str(160 + (_random(seed, 80 + i) % 30)));
            svg = _concat(svg, ",");
            svg = _concat(svg, _uint2str(sy + (_random(seed, 90 + i) % 40)));
            svg = _concat(svg, " ");
            svg = _concat(svg, _uint2str(240 - (_random(seed, 100 + i) % 30)));
            svg = _concat(svg, ",");
            svg = _concat(svg, _uint2str(ey + (_random(seed, 110 + i) % 40)));
            svg = _concat(svg, " ");
            svg = _concat(svg, _uint2str(ex));
            svg = _concat(svg, ",");
            svg = _concat(svg, _uint2str(ey));
            svg = _concat(svg, '" stroke="');
            svg = _concat(svg, tc);
            svg = _concat(svg, '" stroke-width="');
            svg = _concat(svg, _uint2str(2 + stage));
            svg = _concat(svg, '" fill="none" opacity="');
            svg = _concat(svg, op);
            svg = _concat(svg, '" stroke-linecap="round"/>');
        }
        
        // --- Central membrane (Epic+) ---
        if (stage >= 2) {
            svg = _addEllipse(svg, 200, 200, 40, 20 + stage * 10, tc, _concat("0.", _uint2str(glow / 4)));
        }
        
        // Legendary: double membrane
        if (stage >= 3) {
            svg = _addEllipse(svg, 200, 200, 55, 35, "#ffd700", _concat("0.", _uint2str(glow / 6)));
        }
        
        // --- Labels ---
        string memory sn;
        if (stage == 3) sn = "Transcendent";
        else if (stage == 2) sn = "Evolved";
        else if (stage == 1) sn = "Symbiotic";
        else sn = "Primitive";
        
        string memory rn;
        if (rarityTier == 3) rn = "Legendary";
        else if (rarityTier == 2) rn = "Epic";
        else if (rarityTier == 1) rn = "Rare";
        else rn = "Common";
        
        // Token ID
        svg = _concat(svg, '<text x="15" y="25" fill="#7df9ff" font-family="monospace" font-size="12" opacity="0.7">#');
        svg = _concat(svg, _uint2str(tokenId));
        svg = _concat(svg, '</text>');
        
        // Rarity label (gold for legendary)
        string memory rarityColor = stage == 3 ? "#ffd700" : "#00e5c7";
        svg = _concat(svg, '<text x="385" y="25" fill="');
        svg = _concat(svg, rarityColor);
        svg = _concat(svg, '" font-family="monospace" font-size="12" text-anchor="end" opacity="0.7">');
        svg = _concat(svg, rn);
        svg = _concat(svg, '</text>');
        
        // Stage label
        svg = _concat(svg, '<text x="200" y="380" fill="#7df9ff" font-family="monospace" font-size="14" text-anchor="middle" opacity="0.8">');
        svg = _concat(svg, sn);
        svg = _concat(svg, '</text>');
        
        // Health bar background
        svg = _concat(svg, '<rect x="120" y="390" width="160" height="4" rx="2" fill="#050a14" opacity="0.5"/>');
        // Health bar fill
        svg = _concat(svg, '<rect x="120" y="390" width="');
        svg = _concat(svg, _uint2str(health * 160 / 100));
        svg = _concat(svg, '" height="4" rx="2" fill="');
        svg = _concat(svg, stage == 3 ? "#ffd700" : "#00e5c7");
        svg = _concat(svg, '" opacity="0.6"/>');
        
        svg = _concat(svg, '</svg>');
        return svg;
    }
    
    function _addEllipse(string memory svg, uint256 cx, uint256 cy, uint256 rx, uint256 ry, string memory fill, string memory opacity) internal pure returns (string memory) {
        svg = _concat(svg, '<ellipse cx="');
        svg = _concat(svg, _uint2str(cx));
        svg = _concat(svg, '" cy="');
        svg = _concat(svg, _uint2str(cy));
        svg = _concat(svg, '" rx="');
        svg = _concat(svg, _uint2str(rx));
        svg = _concat(svg, '" ry="');
        svg = _concat(svg, _uint2str(ry));
        svg = _concat(svg, '" fill="');
        svg = _concat(svg, fill);
        svg = _concat(svg, '" opacity="');
        svg = _concat(svg, opacity);
        svg = _concat(svg, '" filter="url(#g)"/>');
        return svg;
    }
    
    function _concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
    
    function _random(uint256 seed, uint256 index) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, index)));
    }
    
    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
