// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SpriteDataWeapons
 * @notice All 18 weapon sprites. Positioned at left side of body (cols 0-4, rows 6-19).
 *         Index 0 = None. Indices 8 (Dragon Dagger) + 11 (Dragon Spear) are hard-coded items.
 */
contract SpriteDataWeapons {

    function weaponSVG(uint8 idx) external pure returns (string memory) {
        if (idx == 0) return "";

        // Tier 0
        if (idx == 1) return _ironScim();
        if (idx == 2) return _bronzeScim();
        // Tier 1
        if (idx == 3) return _yoyo();
        if (idx == 4) return _tinderbox();
        if (idx == 5) return _magicShortbow();
        // Tier 2
        if (idx == 6) return _adamantScim();
        if (idx == 7) return _runeScim();
        if (idx == 8) return _dragonDagger();
        if (idx == 9) return _graniteMaul();
        if (idx == 10) return _pickaxe();
        // Tier 3
        if (idx == 11) return _dragonSpear();
        if (idx == 12) return _dragonClaws();
        if (idx == 13) return _bandosGodsword();
        if (idx == 14) return _abyssalWhip();
        if (idx == 15) return _saradominSword();
        // Tier 4
        if (idx == 16) return _dragonScim();
        if (idx == 17) return _twistedBow();
        return _scytheOfVitur();
    }

    function _ironScim() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#9CA3AF"/><rect x="2" y="12" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="13" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="14" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="15" width="2" height="1" fill="#9CA3AF"/><rect x="1" y="16" width="3" height="1" fill="#475569"/><rect x="2" y="17" width="2" height="1" fill="#7C4A1F"/><rect x="2" y="18" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _bronzeScim() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#B45309"/><rect x="2" y="12" width="2" height="1" fill="#B45309"/><rect x="2" y="13" width="2" height="1" fill="#B45309"/><rect x="2" y="14" width="2" height="1" fill="#B45309"/><rect x="2" y="15" width="2" height="1" fill="#B45309"/><rect x="1" y="16" width="3" height="1" fill="#475569"/><rect x="2" y="17" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _yoyo() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="12" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="13" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="14" width="1" height="1" fill="#7C4A1F"/><rect x="2" y="15" width="3" height="1" fill="#DC2626"/><rect x="1" y="16" width="5" height="2" fill="#DC2626"/><rect x="3" y="16" width="1" height="2" fill="#fff"/><rect x="2" y="18" width="3" height="1" fill="#991B1B"/>';
    }

    function _tinderbox() private pure returns (string memory) {
        return '<rect x="1" y="17" width="4" height="1" fill="#7C4A1F"/><rect x="1" y="18" width="4" height="1" fill="#7C4A1F"/><rect x="1" y="19" width="4" height="1" fill="#92400E"/><rect x="2" y="16" width="1" height="1" fill="#FBBF24"/>';
    }

    function _magicShortbow() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#3B82F6"/><rect x="2" y="12" width="1" height="1" fill="#3B82F6"/><rect x="2" y="13" width="1" height="1" fill="#3B82F6"/><rect x="2" y="14" width="1" height="1" fill="#3B82F6"/><rect x="2" y="15" width="1" height="1" fill="#3B82F6"/><rect x="2" y="16" width="1" height="1" fill="#3B82F6"/><rect x="3" y="17" width="1" height="1" fill="#3B82F6"/><rect x="3" y="12" width="1" height="1" fill="#E0E7FF"/><rect x="3" y="13" width="1" height="1" fill="#E0E7FF"/><rect x="3" y="14" width="1" height="1" fill="#E0E7FF"/><rect x="3" y="15" width="1" height="1" fill="#E0E7FF"/><rect x="3" y="16" width="1" height="1" fill="#E0E7FF"/>';
    }

    function _adamantScim() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#22C55E"/><rect x="2" y="12" width="2" height="1" fill="#22C55E"/><rect x="2" y="13" width="2" height="1" fill="#22C55E"/><rect x="2" y="14" width="2" height="1" fill="#22C55E"/><rect x="2" y="15" width="2" height="1" fill="#22C55E"/><rect x="1" y="16" width="3" height="1" fill="#475569"/><rect x="2" y="17" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _runeScim() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#06B6D4"/><rect x="2" y="12" width="2" height="1" fill="#06B6D4"/><rect x="2" y="13" width="2" height="1" fill="#06B6D4"/><rect x="2" y="14" width="2" height="1" fill="#06B6D4"/><rect x="2" y="15" width="2" height="1" fill="#06B6D4"/><rect x="1" y="16" width="3" height="1" fill="#475569"/><rect x="2" y="17" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _dragonDagger() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#DC2626"/><rect x="2" y="12" width="2" height="1" fill="#DC2626"/><rect x="2" y="13" width="2" height="1" fill="#DC2626"/><rect x="1" y="14" width="3" height="1" fill="#475569"/><rect x="2" y="15" width="2" height="1" fill="#7C4A1F"/><rect x="2" y="16" width="2" height="1" fill="#7C4A1F"/><rect x="3" y="12" width="1" height="1" fill="#22C55E"/>';
    }

    function _graniteMaul() private pure returns (string memory) {
        return '<rect x="1" y="11" width="4" height="2" fill="#6B7280"/><rect x="2" y="13" width="2" height="1" fill="#6B7280"/><rect x="3" y="14" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="15" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="16" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="17" width="1" height="1" fill="#7C4A1F"/>';
    }

    function _pickaxe() private pure returns (string memory) {
        return '<rect x="0" y="11" width="4" height="2" fill="#475569"/><rect x="3" y="13" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="14" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="15" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="16" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="17" width="1" height="1" fill="#7C4A1F"/>';
    }

    function _dragonSpear() private pure returns (string memory) {
        return '<rect x="3" y="6" width="1" height="1" fill="#DC2626"/><rect x="2" y="7" width="2" height="1" fill="#DC2626"/><rect x="2" y="8" width="2" height="1" fill="#DC2626"/><rect x="3" y="9" width="1" height="1" fill="#DC2626"/><rect x="3" y="10" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="11" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="12" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="13" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="14" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="15" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="16" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="17" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="18" width="1" height="1" fill="#7C4A1F"/>';
    }

    function _dragonClaws() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#DC2626"/><rect x="2" y="12" width="2" height="1" fill="#DC2626"/><rect x="2" y="13" width="2" height="1" fill="#DC2626"/><rect x="1" y="14" width="3" height="1" fill="#DC2626"/><rect x="2" y="15" width="2" height="1" fill="#7C4A1F"/><rect x="2" y="16" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _bandosGodsword() private pure returns (string memory) {
        return '<rect x="3" y="9" width="1" height="1" fill="#9CA3AF"/><rect x="2" y="10" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="11" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="12" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="13" width="2" height="1" fill="#9CA3AF"/><rect x="2" y="14" width="2" height="1" fill="#9CA3AF"/><rect x="1" y="15" width="3" height="1" fill="#FBBF24"/><rect x="2" y="16" width="2" height="1" fill="#7C4A1F"/><rect x="2" y="17" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _abyssalWhip() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#DC2626"/><rect x="2" y="12" width="1" height="1" fill="#F97316"/><rect x="3" y="13" width="1" height="1" fill="#F97316"/><rect x="2" y="14" width="1" height="1" fill="#F97316"/><rect x="3" y="15" width="1" height="1" fill="#F97316"/><rect x="1" y="16" width="3" height="1" fill="#F97316"/><rect x="2" y="17" width="2" height="1" fill="#DC2626"/>';
    }

    function _saradominSword() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#3B82F6"/><rect x="2" y="12" width="2" height="1" fill="#3B82F6"/><rect x="2" y="13" width="2" height="1" fill="#3B82F6"/><rect x="2" y="14" width="2" height="1" fill="#3B82F6"/><rect x="2" y="15" width="2" height="1" fill="#3B82F6"/><rect x="1" y="16" width="3" height="1" fill="#FFD700"/><rect x="2" y="17" width="2" height="1" fill="#fff"/><rect x="2" y="18" width="2" height="1" fill="#fff"/>';
    }

    function _dragonScim() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#DC2626"/><rect x="2" y="12" width="2" height="1" fill="#DC2626"/><rect x="2" y="13" width="2" height="1" fill="#DC2626"/><rect x="2" y="14" width="2" height="1" fill="#DC2626"/><rect x="2" y="15" width="2" height="1" fill="#DC2626"/><rect x="1" y="16" width="3" height="1" fill="#FFD700"/><rect x="2" y="17" width="2" height="1" fill="#7C4A1F"/>';
    }

    function _twistedBow() private pure returns (string memory) {
        return '<rect x="3" y="11" width="1" height="1" fill="#A78BFA"/><rect x="2" y="12" width="1" height="1" fill="#A78BFA"/><rect x="3" y="13" width="1" height="1" fill="#A78BFA"/><rect x="2" y="14" width="1" height="1" fill="#fff"/><rect x="3" y="15" width="1" height="1" fill="#A78BFA"/><rect x="2" y="16" width="1" height="1" fill="#A78BFA"/><rect x="3" y="17" width="1" height="1" fill="#A78BFA"/>';
    }

    function _scytheOfVitur() private pure returns (string memory) {
        return '<rect x="2" y="9" width="2" height="1" fill="#06B6D4"/><rect x="1" y="10" width="3" height="1" fill="#06B6D4"/><rect x="1" y="11" width="3" height="1" fill="#06B6D4"/><rect x="3" y="12" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="13" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="14" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="15" width="1" height="1" fill="#7C4A1F"/><rect x="3" y="16" width="1" height="1" fill="#7C4A1F"/>';
    }
}
