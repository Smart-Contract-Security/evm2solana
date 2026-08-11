// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SpriteDataShields
 * @notice All 13 shield names, weighted picks, and SVG sprites.
 *         13 shields total: None + 6 metals (Bronze→Rune) + Dragon Sq/Kite/Dragonfire + 3 Spirit Shields.
 *         Held in left hand (x=18-22), drawn after weapon, before effect.
 */
contract SpriteDataShields {

    function shieldName(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "None";
        if (idx == 1) return "Bronze Kiteshield";
        if (idx == 2) return "Iron Kiteshield";
        if (idx == 3) return "Steel Kiteshield";
        if (idx == 4) return "Mithril Kiteshield";
        if (idx == 5) return "Adamant Kiteshield";
        if (idx == 6) return "Rune Kiteshield";
        if (idx == 7) return "Dragon Square";
        if (idx == 8) return "Dragon Kiteshield";
        if (idx == 9) return "Dragonfire Shield";
        if (idx == 10) return "Spectral Spirit Shield";
        if (idx == 11) return "Arcane Spirit Shield";
        return "Elysian Spirit Shield";
    }

    function pickShield(uint256 seed) external pure returns (uint8 idx, uint8 tier) {
        // None 60 + Bronze 30 + Iron 25 + Steel 18 + Mithril 12 + Adamant 8 + Rune 5
        // + DragSq 3 + DragKite 2 + DFire 1 + Spectral 1 + Arcane 1 + Elysian 1 = 167
        uint256 r = seed % 167;
        if (r < 60)  return (0, 0);   // None
        if (r < 90)  return (1, 0);   // Bronze
        if (r < 115) return (2, 0);   // Iron
        if (r < 133) return (3, 0);   // Steel
        if (r < 145) return (4, 1);   // Mithril
        if (r < 153) return (5, 1);   // Adamant
        if (r < 158) return (6, 2);   // Rune
        if (r < 161) return (7, 2);   // Dragon Square
        if (r < 163) return (8, 3);   // Dragon Kiteshield
        if (r < 164) return (9, 3);   // Dragonfire Shield
        if (r < 165) return (10, 4);  // Spectral
        if (r < 166) return (11, 4);  // Arcane
        return (12, 4);               // Elysian
    }

    function shieldSVG(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "";
        if (idx == 1) return '<rect x="19" y="11" width="3" height="1" fill="#7C2D12"/><rect x="18" y="12" width="5" height="3" fill="#92400E"/><rect x="19" y="12" width="3" height="3" fill="#B45309"/><rect x="19" y="15" width="3" height="1" fill="#7C2D12"/><rect x="20" y="16" width="1" height="1" fill="#7C2D12"/><rect x="19" y="12" width="1" height="1" fill="#FBBF24"/>';
        if (idx == 2) return '<rect x="19" y="11" width="3" height="1" fill="#374151"/><rect x="18" y="12" width="5" height="3" fill="#4B5563"/><rect x="19" y="12" width="3" height="3" fill="#6B7280"/><rect x="19" y="15" width="3" height="1" fill="#374151"/><rect x="20" y="16" width="1" height="1" fill="#374151"/><rect x="19" y="12" width="1" height="1" fill="#fff"/>';
        if (idx == 3) return '<rect x="19" y="11" width="3" height="1" fill="#6B7280"/><rect x="18" y="12" width="5" height="3" fill="#9CA3AF"/><rect x="19" y="12" width="3" height="3" fill="#D1D5DB"/><rect x="19" y="15" width="3" height="1" fill="#6B7280"/><rect x="20" y="16" width="1" height="1" fill="#6B7280"/><rect x="19" y="12" width="1" height="1" fill="#fff"/>';
        if (idx == 4) return '<rect x="19" y="11" width="3" height="1" fill="#1E3A8A"/><rect x="18" y="12" width="5" height="3" fill="#1E40AF"/><rect x="19" y="12" width="3" height="3" fill="#3B82F6"/><rect x="19" y="15" width="3" height="1" fill="#1E3A8A"/><rect x="20" y="16" width="1" height="1" fill="#1E3A8A"/><rect x="19" y="12" width="1" height="1" fill="#93C5FD"/>';
        if (idx == 5) return '<rect x="19" y="11" width="3" height="1" fill="#14532D"/><rect x="18" y="12" width="5" height="3" fill="#15803D"/><rect x="19" y="12" width="3" height="3" fill="#22C55E"/><rect x="19" y="15" width="3" height="1" fill="#14532D"/><rect x="20" y="16" width="1" height="1" fill="#14532D"/><rect x="19" y="12" width="1" height="1" fill="#86EFAC"/>';
        if (idx == 6) return '<rect x="19" y="11" width="3" height="1" fill="#155E75"/><rect x="18" y="12" width="5" height="3" fill="#0E7490"/><rect x="19" y="12" width="3" height="3" fill="#06B6D4"/><rect x="19" y="15" width="3" height="1" fill="#155E75"/><rect x="20" y="16" width="1" height="1" fill="#155E75"/><rect x="19" y="12" width="1" height="1" fill="#67E8F9"/>';
        if (idx == 7) return '<rect x="18" y="11" width="5" height="1" fill="#7F1D1D"/><rect x="18" y="12" width="5" height="4" fill="#7F1D1D"/><rect x="19" y="12" width="3" height="4" fill="#DC2626"/><rect x="20" y="13" width="1" height="2" fill="#FBBF24"/><rect x="18" y="16" width="5" height="1" fill="#7F1D1D"/>';
        if (idx == 8) return '<rect x="19" y="11" width="3" height="1" fill="#7F1D1D"/><rect x="18" y="12" width="5" height="3" fill="#7F1D1D"/><rect x="19" y="12" width="3" height="3" fill="#DC2626"/><rect x="19" y="15" width="3" height="1" fill="#7F1D1D"/><rect x="20" y="16" width="1" height="1" fill="#7F1D1D"/><rect x="19" y="12" width="1" height="1" fill="#FBBF24"/><rect x="21" y="13" width="1" height="1" fill="#1A0A0A"/>';
        if (idx == 9) return '<rect x="19" y="11" width="3" height="1" fill="#7F1D1D"/><rect x="18" y="12" width="5" height="3" fill="#7F1D1D"/><rect x="19" y="12" width="3" height="3" fill="#DC2626"/><rect x="19" y="13" width="1" height="1" fill="#FBBF24"/><rect x="21" y="13" width="1" height="1" fill="#FBBF24"/><rect x="20" y="14" width="1" height="1" fill="#FBBF24"/><rect x="19" y="15" width="3" height="1" fill="#7F1D1D"/><rect x="20" y="16" width="1" height="1" fill="#F97316"/>';
        if (idx == 10) return '<rect x="19" y="11" width="3" height="1" fill="#9CA3AF"/><rect x="18" y="12" width="5" height="3" fill="#D1D5DB"/><rect x="19" y="12" width="3" height="3" fill="#E5E7EB"/><rect x="20" y="13" width="1" height="1" fill="#22C55E"/><rect x="19" y="15" width="3" height="1" fill="#9CA3AF"/><rect x="20" y="16" width="1" height="1" fill="#9CA3AF"/>';
        if (idx == 11) return '<rect x="19" y="11" width="3" height="1" fill="#9CA3AF"/><rect x="18" y="12" width="5" height="3" fill="#D1D5DB"/><rect x="19" y="12" width="3" height="3" fill="#E5E7EB"/><rect x="20" y="13" width="1" height="1" fill="#3B82F6"/><rect x="19" y="15" width="3" height="1" fill="#9CA3AF"/><rect x="20" y="16" width="1" height="1" fill="#9CA3AF"/>';
        return '<rect x="19" y="11" width="3" height="1" fill="#9CA3AF"/><rect x="18" y="12" width="5" height="3" fill="#D1D5DB"/><rect x="19" y="12" width="3" height="3" fill="#E5E7EB"/><rect x="20" y="13" width="1" height="1" fill="#DC2626"/><rect x="19" y="15" width="3" height="1" fill="#9CA3AF"/><rect x="20" y="16" width="1" height="1" fill="#9CA3AF"/>';
    }
}
