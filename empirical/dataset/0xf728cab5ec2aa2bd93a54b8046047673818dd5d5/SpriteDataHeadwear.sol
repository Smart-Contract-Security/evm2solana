// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SpriteDataHeadwear
 * @notice All 27 headwear sprites for Onchainimals.
 *         Index 0 = None (empty). Indices 21-26 = the 6 partyhats (mythic).
 */
contract SpriteDataHeadwear {

    function headwearSVG(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "";

        // ─── Tier 0 Commons ───
        if (idx == 1) return _redBandana();
        if (idx == 2) return _blueBandana();
        if (idx == 3) return _greenBandana();
        if (idx == 4) return _hardHat();
        if (idx == 5) return _bronzeMedHelm();

        // ─── Tier 1 Rares ───
        if (idx == 6) return _pumpkinHelmet();
        if (idx == 7) return _sleepingCap();
        if (idx == 8) return _wizardHatG();

        // ─── Tier 2 Epics ───
        if (idx == 9) return _pirateTricorne();
        if (idx == 10) return _robinHoodHat();
        if (idx == 11) return _bunnyEars();
        if (idx == 12) return _helmOfNeitiznot();
        if (idx == 13) return _dragonMedHelm();
        if (idx == 14) return _blackMask();

        // ─── Tier 3 Legendaries ───
        if (idx == 15) return _halo();
        if (idx == 16) return _santaHat();
        if (idx == 17) return _redHweenMask();
        if (idx == 18) return _blueHweenMask();
        if (idx == 19) return _greenHweenMask();
        if (idx == 20) return _blackHweenMask();

        // ─── Tier 4 Mythics (Partyhats) ───
        if (idx == 21) return _partyhat("#8B5CF6", "#6B21A8");  // Purple
        if (idx == 22) return _partyhat("#fff", "#E5E7EB");      // White
        if (idx == 23) return _partyhat("#DC2626", "#991B1B");   // Red
        if (idx == 24) return _partyhat("#3B82F6", "#1E40AF");   // Blue
        if (idx == 25) return _partyhat("#22C55E", "#15803D");   // Green
        return _partyhat("#FBBF24", "#D97706");                  // Yellow
    }

    // ============ TIER 0 ============

    function _redBandana() private pure returns (string memory) {
        return '<rect x="5" y="4" width="14" height="1" fill="#DC2626"/><rect x="5" y="5" width="14" height="1" fill="#991B1B"/><rect x="19" y="5" width="2" height="1" fill="#DC2626"/><rect x="18" y="6" width="3" height="1" fill="#991B1B"/>';
    }

    function _blueBandana() private pure returns (string memory) {
        return '<rect x="5" y="4" width="14" height="1" fill="#3B82F6"/><rect x="5" y="5" width="14" height="1" fill="#1E40AF"/><rect x="19" y="5" width="2" height="1" fill="#3B82F6"/><rect x="18" y="6" width="3" height="1" fill="#1E40AF"/>';
    }

    function _greenBandana() private pure returns (string memory) {
        return '<rect x="5" y="4" width="14" height="1" fill="#22C55E"/><rect x="5" y="5" width="14" height="1" fill="#15803D"/><rect x="19" y="5" width="2" height="1" fill="#22C55E"/><rect x="18" y="6" width="3" height="1" fill="#15803D"/>';
    }

    function _hardHat() private pure returns (string memory) {
        return '<rect x="8" y="3" width="8" height="1" fill="#FBBF24"/><rect x="7" y="4" width="10" height="1" fill="#FBBF24"/><rect x="6" y="5" width="12" height="1" fill="#D97706"/>';
    }

    function _bronzeMedHelm() private pure returns (string memory) {
        return '<rect x="7" y="2" width="10" height="1" fill="#92400E"/><rect x="6" y="3" width="12" height="1" fill="#92400E"/><rect x="6" y="4" width="12" height="1" fill="#DC2626"/><rect x="6" y="5" width="12" height="1" fill="#92400E"/><rect x="11" y="3" width="2" height="1" fill="#1A0A0A"/><rect x="11" y="4" width="2" height="1" fill="#1A0A0A"/><rect x="11" y="5" width="2" height="1" fill="#1A0A0A"/>';
    }

    // ============ TIER 1 ============

    function _pumpkinHelmet() private pure returns (string memory) {
        return '<rect x="11" y="0" width="2" height="1" fill="#22C55E"/><rect x="10" y="1" width="3" height="1" fill="#15803D"/><rect x="7" y="2" width="10" height="1" fill="#F97316"/><rect x="6" y="3" width="12" height="1" fill="#F97316"/><rect x="6" y="4" width="12" height="1" fill="#F97316"/><rect x="9" y="4" width="2" height="1" fill="#1A0A0A"/><rect x="13" y="4" width="2" height="1" fill="#1A0A0A"/><rect x="6" y="5" width="12" height="1" fill="#C2410C"/><rect x="10" y="5" width="4" height="1" fill="#1A0A0A"/>';
    }

    function _sleepingCap() private pure returns (string memory) {
        return '<rect x="14" y="0" width="2" height="1" fill="#fff"/><rect x="13" y="1" width="2" height="1" fill="#A855F7"/><rect x="12" y="2" width="3" height="1" fill="#A855F7"/><rect x="11" y="3" width="4" height="1" fill="#A855F7"/><rect x="10" y="4" width="6" height="1" fill="#A855F7"/><rect x="9" y="5" width="8" height="1" fill="#7C2D92"/>';
    }

    function _wizardHatG() private pure returns (string memory) {
        return '<rect x="12" y="0" width="1" height="1" fill="#2D4FB8"/><rect x="11" y="1" width="3" height="1" fill="#2D4FB8"/><rect x="10" y="2" width="5" height="1" fill="#2D4FB8"/><rect x="12" y="2" width="1" height="1" fill="#FFD700"/><rect x="9" y="3" width="7" height="1" fill="#2D4FB8"/><rect x="8" y="4" width="9" height="1" fill="#2D4FB8"/><rect x="7" y="5" width="11" height="1" fill="#1E3A8A"/>';
    }

    // ============ TIER 2 ============

    function _pirateTricorne() private pure returns (string memory) {
        return '<rect x="11" y="1" width="2" height="1" fill="#1A0A0A"/><rect x="10" y="2" width="4" height="1" fill="#1A0A0A"/><rect x="8" y="3" width="8" height="1" fill="#1A0A0A"/><rect x="11" y="3" width="2" height="1" fill="#fff"/><rect x="6" y="4" width="12" height="1" fill="#1A0A0A"/><rect x="10" y="4" width="1" height="1" fill="#fff"/><rect x="13" y="4" width="1" height="1" fill="#fff"/><rect x="11" y="4" width="2" height="1" fill="#1A0A0A"/><rect x="5" y="5" width="14" height="1" fill="#1A0A0A"/>';
    }

    function _robinHoodHat() private pure returns (string memory) {
        return '<rect x="13" y="0" width="1" height="1" fill="#fff"/><rect x="13" y="1" width="1" height="1" fill="#fff"/><rect x="12" y="2" width="2" height="1" fill="#15803D"/><rect x="13" y="2" width="1" height="1" fill="#fff"/><rect x="11" y="3" width="4" height="1" fill="#15803D"/><rect x="10" y="4" width="6" height="1" fill="#15803D"/><rect x="9" y="5" width="8" height="1" fill="#166534"/>';
    }

    function _bunnyEars() private pure returns (string memory) {
        return '<rect x="10" y="0" width="1" height="1" fill="#fff"/><rect x="14" y="0" width="1" height="1" fill="#fff"/><rect x="10" y="1" width="2" height="1" fill="#fff"/><rect x="13" y="1" width="2" height="1" fill="#fff"/><rect x="10" y="2" width="2" height="1" fill="#fff"/><rect x="13" y="2" width="2" height="1" fill="#fff"/><rect x="11" y="2" width="1" height="1" fill="#FFB6C7"/><rect x="13" y="2" width="1" height="1" fill="#FFB6C7"/><rect x="10" y="3" width="2" height="1" fill="#fff"/><rect x="13" y="3" width="2" height="1" fill="#fff"/><rect x="11" y="3" width="1" height="1" fill="#FFB6C7"/><rect x="13" y="3" width="1" height="1" fill="#FFB6C7"/><rect x="10" y="4" width="2" height="1" fill="#fff"/><rect x="13" y="4" width="2" height="1" fill="#fff"/><rect x="10" y="5" width="2" height="1" fill="#fff"/><rect x="13" y="5" width="2" height="1" fill="#fff"/>';
    }

    function _helmOfNeitiznot() private pure returns (string memory) {
        return '<rect x="7" y="0" width="1" height="2" fill="#E5E7EB"/><rect x="16" y="0" width="1" height="2" fill="#E5E7EB"/><rect x="7" y="2" width="10" height="1" fill="#FBBF24"/><rect x="6" y="3" width="12" height="1" fill="#FBBF24"/><rect x="6" y="4" width="12" height="1" fill="#FBBF24"/><rect x="5" y="5" width="14" height="1" fill="#D97706"/>';
    }

    function _dragonMedHelm() private pure returns (string memory) {
        return '<rect x="6" y="0" width="1" height="1" fill="#9CA3AF"/><rect x="17" y="0" width="1" height="1" fill="#9CA3AF"/><rect x="6" y="1" width="2" height="1" fill="#E5E7EB"/><rect x="16" y="1" width="2" height="1" fill="#E5E7EB"/><rect x="7" y="2" width="10" height="1" fill="#991B1B"/><rect x="6" y="3" width="12" height="1" fill="#991B1B"/><rect x="6" y="4" width="12" height="1" fill="#7F1D1D"/><rect x="6" y="5" width="12" height="1" fill="#991B1B"/><rect x="11" y="3" width="2" height="1" fill="#1A0A0A"/><rect x="11" y="4" width="2" height="1" fill="#1A0A0A"/><rect x="11" y="5" width="2" height="1" fill="#1A0A0A"/>';
    }

    function _blackMask() private pure returns (string memory) {
        return '<rect x="8" y="0" width="8" height="1" fill="#1A0A0A"/><rect x="7" y="1" width="10" height="1" fill="#1A0A0A"/><rect x="6" y="2" width="12" height="1" fill="#1A0A0A"/><rect x="5" y="3" width="14" height="1" fill="#1A0A0A"/><rect x="7" y="3" width="2" height="1" fill="#fff"/><rect x="15" y="3" width="2" height="1" fill="#fff"/><rect x="5" y="4" width="14" height="1" fill="#1A0A0A"/><rect x="7" y="4" width="2" height="1" fill="#fff"/><rect x="15" y="4" width="2" height="1" fill="#fff"/><rect x="6" y="5" width="12" height="1" fill="#1A0A0A"/><rect x="7" y="6" width="10" height="1" fill="#1A0A0A"/><rect x="9" y="6" width="2" height="1" fill="#fff"/><rect x="13" y="6" width="2" height="1" fill="#fff"/>';
    }

    // ============ TIER 3 ============

    function _halo() private pure returns (string memory) {
        return '<rect x="8" y="0" width="8" height="1" fill="#FFD700"/><rect x="7" y="1" width="2" height="1" fill="#FFD700"/><rect x="15" y="1" width="2" height="1" fill="#FFD700"/><rect x="8" y="2" width="8" height="1" fill="#FBBF24"/>';
    }

    function _santaHat() private pure returns (string memory) {
        return '<rect x="14" y="0" width="2" height="1" fill="#fff"/><rect x="14" y="1" width="1" height="1" fill="#DC2626"/><rect x="15" y="1" width="1" height="1" fill="#fff"/><rect x="12" y="2" width="3" height="1" fill="#DC2626"/><rect x="11" y="3" width="4" height="1" fill="#DC2626"/><rect x="10" y="4" width="6" height="1" fill="#DC2626"/><rect x="9" y="5" width="8" height="1" fill="#fff"/>';
    }

    function _redHweenMask() private pure returns (string memory) {
        return '<rect x="5" y="7" width="14" height="1" fill="#DC2626"/><rect x="4" y="8" width="16" height="1" fill="#DC2626"/><rect x="6" y="8" width="2" height="1" fill="#fff"/><rect x="16" y="8" width="2" height="1" fill="#fff"/><rect x="7" y="8" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="8" width="1" height="1" fill="#1A0A0A"/><rect x="4" y="9" width="16" height="1" fill="#DC2626"/>';
    }

    function _blueHweenMask() private pure returns (string memory) {
        return '<rect x="5" y="7" width="14" height="1" fill="#3B82F6"/><rect x="4" y="8" width="16" height="1" fill="#3B82F6"/><rect x="6" y="8" width="2" height="1" fill="#fff"/><rect x="16" y="8" width="2" height="1" fill="#fff"/><rect x="7" y="8" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="8" width="1" height="1" fill="#1A0A0A"/><rect x="4" y="9" width="16" height="1" fill="#3B82F6"/>';
    }

    function _greenHweenMask() private pure returns (string memory) {
        return '<rect x="5" y="7" width="14" height="1" fill="#15803D"/><rect x="4" y="8" width="16" height="1" fill="#15803D"/><rect x="6" y="8" width="2" height="1" fill="#fff"/><rect x="16" y="8" width="2" height="1" fill="#fff"/><rect x="7" y="8" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="8" width="1" height="1" fill="#1A0A0A"/><rect x="4" y="9" width="16" height="1" fill="#15803D"/>';
    }

    function _blackHweenMask() private pure returns (string memory) {
        return '<rect x="5" y="7" width="14" height="1" fill="#1A0A0A"/><rect x="4" y="8" width="16" height="1" fill="#1A0A0A"/><rect x="6" y="8" width="2" height="1" fill="#fff"/><rect x="16" y="8" width="2" height="1" fill="#fff"/><rect x="7" y="8" width="1" height="1" fill="#DC2626"/><rect x="17" y="8" width="1" height="1" fill="#DC2626"/><rect x="4" y="9" width="16" height="1" fill="#1A0A0A"/>';
    }

    // ============ TIER 4 PARTYHATS (parameterized by color) ============

    function _partyhat(string memory main, string memory dark) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="8" y="0" width="1" height="1" fill="', main, '"/>',
            '<rect x="12" y="0" width="1" height="1" fill="', main, '"/>',
            '<rect x="16" y="0" width="1" height="1" fill="', main, '"/>',
            '<rect x="7" y="1" width="3" height="1" fill="', main, '"/>',
            '<rect x="11" y="1" width="3" height="1" fill="', main, '"/>',
            '<rect x="15" y="1" width="3" height="1" fill="', main, '"/>',
            '<rect x="7" y="2" width="11" height="1" fill="', main, '"/>',
            '<rect x="7" y="3" width="11" height="1" fill="', main, '"/>',
            '<rect x="7" y="4" width="11" height="1" fill="', main, '"/>',
            '<rect x="6" y="5" width="13" height="1" fill="', dark, '"/>'
        ));
    }
}
