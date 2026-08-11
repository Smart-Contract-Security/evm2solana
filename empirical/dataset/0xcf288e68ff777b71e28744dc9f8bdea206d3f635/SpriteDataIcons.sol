// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SpriteDataIcons
 * @notice The 5 one-of-one bespoke sprites: Doge, Shib, WIF, Pepe, Moodeng.
 *         Each is a complete full-canvas 24x24 SVG returned wrapped in <svg> tags
 *         by oneOfOneFullSVG() — these are NOT composed with other traits,
 *         they're standalone images.
 */
contract SpriteDataIcons {

    /// @notice Full standalone SVG for a 1/1 (includes svg root + background)
    function oneOfOneFullSVG(uint256 slot) external pure returns (string memory) {
        if (slot == 0) return _doge();
        if (slot == 1) return _shib();
        if (slot == 2) return _wif();
        if (slot == 3) return _pepe();
        return _moodeng();
    }

    function _doge() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="#FFE34D"/>',
            '<rect x="1" y="1" width="1" height="1" fill="#FF3D5C"/><rect x="3" y="2" width="1" height="1" fill="#FF3D5C"/>',
            '<rect x="20" y="1" width="1" height="1" fill="#22C55E"/><rect x="22" y="2" width="1" height="1" fill="#22C55E"/>',
            '<rect x="4" y="3" width="3" height="1" fill="#A87D4A"/><rect x="17" y="3" width="3" height="1" fill="#A87D4A"/>',
            '<rect x="5" y="3" width="1" height="1" fill="#F4D9A8"/><rect x="18" y="3" width="1" height="1" fill="#F4D9A8"/>',
            '<rect x="4" y="4" width="4" height="1" fill="#A87D4A"/><rect x="16" y="4" width="4" height="1" fill="#A87D4A"/>',
            '<rect x="5" y="4" width="2" height="1" fill="#F4D9A8"/><rect x="17" y="4" width="2" height="1" fill="#F4D9A8"/>',
            '<rect x="8" y="4" width="8" height="1" fill="#D4A574"/>',
            '<rect x="3" y="5" width="18" height="1" fill="#D4A574"/>',
            '<rect x="3" y="6" width="18" height="1" fill="#D4A574"/>',
            '<rect x="2" y="7" width="20" height="1" fill="#D4A574"/>',
            '<rect x="6" y="7" width="3" height="1" fill="#fff"/><rect x="15" y="7" width="3" height="1" fill="#fff"/>',
            '<rect x="8" y="7" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="7" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="2" y="8" width="20" height="1" fill="#D4A574"/>',
            '<rect x="9" y="8" width="6" height="1" fill="#F4D9A8"/>',
            '<rect x="2" y="9" width="20" height="1" fill="#D4A574"/>',
            '<rect x="7" y="9" width="10" height="1" fill="#F4D9A8"/>',
            '<rect x="11" y="9" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="2" y="10" width="20" height="1" fill="#D4A574"/>',
            '<rect x="6" y="10" width="12" height="1" fill="#F4D9A8"/>',
            '<rect x="3" y="11" width="18" height="1" fill="#D4A574"/>',
            '<rect x="6" y="11" width="12" height="1" fill="#F4D9A8"/>',
            '<rect x="10" y="11" width="4" height="1" fill="#3D2817"/>',
            '<rect x="4" y="12" width="16" height="1" fill="#D4A574"/>',
            '<rect x="7" y="12" width="10" height="1" fill="#F4D9A8"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#D4A574"/>',
            '<rect x="9" y="13" width="6" height="1" fill="#F4D9A8"/>',
            '<rect x="7" y="14" width="10" height="1" fill="#F4D9A8"/>',
            '<rect x="2" y="18" width="2" height="1" fill="#8B5CF6"/><rect x="5" y="18" width="1" height="1" fill="#8B5CF6"/><rect x="7" y="18" width="1" height="1" fill="#8B5CF6"/>',
            '<rect x="19" y="18" width="1" height="1" fill="#0EA5E9"/><rect x="21" y="18" width="2" height="1" fill="#0EA5E9"/>',
            '<rect x="3" y="20" width="1" height="1" fill="#FF3D5C"/><rect x="5" y="20" width="1" height="1" fill="#FF3D5C"/><rect x="7" y="20" width="2" height="1" fill="#FF3D5C"/>',
            '<rect x="14" y="20" width="2" height="1" fill="#22C55E"/><rect x="17" y="20" width="1" height="1" fill="#22C55E"/><rect x="19" y="20" width="1" height="1" fill="#22C55E"/>',
            '<rect x="3" y="22" width="1" height="1" fill="#F97316"/><rect x="5" y="22" width="2" height="1" fill="#F97316"/><rect x="19" y="22" width="2" height="1" fill="#F97316"/>',
            '</svg>'
        ));
    }

    function _shib() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="#1A0A0A"/>',
            '<rect x="8" y="1" width="8" height="1" fill="#D9532F"/><rect x="5" y="2" width="14" height="1" fill="#D9532F"/>',
            '<rect x="3" y="3" width="18" height="1" fill="#D9532F"/><rect x="2" y="4" width="20" height="1" fill="#D9532F"/>',
            '<rect x="2" y="5" width="20" height="1" fill="#D9532F"/><rect x="1" y="6" width="22" height="1" fill="#D9532F"/>',
            '<rect x="1" y="7" width="22" height="1" fill="#D9532F"/><rect x="0" y="8" width="24" height="7" fill="#D9532F"/>',
            '<rect x="1" y="15" width="22" height="1" fill="#D9532F"/><rect x="1" y="16" width="22" height="1" fill="#D9532F"/>',
            '<rect x="2" y="17" width="20" height="1" fill="#D9532F"/><rect x="2" y="18" width="20" height="1" fill="#D9532F"/>',
            '<rect x="3" y="19" width="18" height="1" fill="#D9532F"/><rect x="5" y="20" width="14" height="1" fill="#D9532F"/>',
            '<rect x="8" y="21" width="8" height="1" fill="#D9532F"/>',
            '<rect x="5" y="4" width="3" height="1" fill="#E8843D"/><rect x="16" y="4" width="3" height="1" fill="#E8843D"/>',
            '<rect x="6" y="4" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="4" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="4" y="5" width="5" height="1" fill="#E8843D"/><rect x="15" y="5" width="5" height="1" fill="#E8843D"/>',
            '<rect x="4" y="6" width="16" height="1" fill="#E8843D"/><rect x="3" y="7" width="18" height="2" fill="#E8843D"/>',
            '<rect x="5" y="8" width="3" height="1" fill="#1A0A0A"/><rect x="16" y="8" width="3" height="1" fill="#1A0A0A"/>',
            '<rect x="3" y="9" width="18" height="1" fill="#E8843D"/>',
            '<rect x="6" y="9" width="3" height="1" fill="#FFD700"/><rect x="15" y="9" width="3" height="1" fill="#FFD700"/>',
            '<rect x="7" y="9" width="1" height="1" fill="#1A0A0A"/><rect x="16" y="9" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="3" y="10" width="18" height="1" fill="#E8843D"/><rect x="6" y="10" width="12" height="1" fill="#F8C9B5"/>',
            '<rect x="3" y="11" width="18" height="1" fill="#E8843D"/><rect x="5" y="11" width="14" height="1" fill="#F8C9B5"/>',
            '<rect x="11" y="11" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="4" y="12" width="16" height="1" fill="#E8843D"/><rect x="6" y="12" width="12" height="1" fill="#F8C9B5"/>',
            '<rect x="11" y="12" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#E8843D"/><rect x="7" y="13" width="10" height="1" fill="#F8C9B5"/>',
            '<rect x="11" y="13" width="1" height="1" fill="#fff"/>',
            '<rect x="6" y="14" width="12" height="1" fill="#E8843D"/><rect x="8" y="14" width="8" height="1" fill="#F8C9B5"/>',
            '</svg>'
        ));
    }

    function _wif() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="#FCE8D4"/>',
            '<rect x="9" y="0" width="6" height="1" fill="#FF8FA3"/><rect x="8" y="1" width="8" height="1" fill="#FF8FA3"/>',
            '<rect x="7" y="2" width="10" height="1" fill="#FF8FA3"/><rect x="6" y="3" width="12" height="3" fill="#FF8FA3"/>',
            '<rect x="5" y="6" width="14" height="2" fill="#E8758F"/>',
            '<rect x="6" y="8" width="12" height="1" fill="#D4A574"/>',
            '<rect x="5" y="9" width="14" height="1" fill="#D4A574"/>',
            '<rect x="4" y="10" width="16" height="4" fill="#D4A574"/>',
            '<rect x="5" y="14" width="14" height="1" fill="#D4A574"/>',
            '<rect x="6" y="15" width="12" height="1" fill="#D4A574"/>',
            '<rect x="6" y="9" width="2" height="1" fill="#fff"/><rect x="16" y="9" width="2" height="1" fill="#fff"/>',
            '<rect x="7" y="9" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="9" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="6" y="10" width="2" height="1" fill="#fff"/><rect x="16" y="10" width="2" height="1" fill="#fff"/>',
            '<rect x="7" y="10" width="1" height="1" fill="#1A0A0A"/><rect x="17" y="10" width="1" height="1" fill="#1A0A0A"/>',
            '<rect x="5" y="11" width="1" height="1" fill="#FFAFC2"/><rect x="18" y="11" width="1" height="1" fill="#FFAFC2"/>',
            '<rect x="7" y="11" width="10" height="1" fill="#F4D9A8"/><rect x="11" y="11" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="6" y="12" width="12" height="2" fill="#F4D9A8"/>',
            '<rect x="10" y="13" width="4" height="1" fill="#3D2817"/>',
            '<rect x="8" y="14" width="8" height="1" fill="#F4D9A8"/>',
            '<rect x="9" y="15" width="6" height="1" fill="#F4D9A8"/>',
            '<rect x="3" y="16" width="18" height="2" fill="#D4A574"/>',
            '<rect x="8" y="16" width="8" height="1" fill="#F4D9A8"/>',
            '<rect x="7" y="17" width="10" height="1" fill="#F4D9A8"/>',
            '<rect x="2" y="18" width="20" height="5" fill="#D4A574"/>',
            '<rect x="6" y="18" width="12" height="1" fill="#F4D9A8"/>',
            '<rect x="5" y="19" width="14" height="1" fill="#F4D9A8"/>',
            '<rect x="4" y="20" width="16" height="2" fill="#F4D9A8"/>',
            '<rect x="5" y="22" width="14" height="1" fill="#F4D9A8"/>',
            '</svg>'
        ));
    }

    function _pepe() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="#3B82F6"/>',
            '<rect x="5" y="2" width="14" height="1" fill="#5BB041"/>',
            '<rect x="3" y="3" width="18" height="1" fill="#5BB041"/>',
            '<rect x="2" y="4" width="20" height="11" fill="#5BB041"/>',
            '<rect x="3" y="15" width="18" height="1" fill="#5BB041"/>',
            '<rect x="4" y="16" width="16" height="1" fill="#5BB041"/>',
            '<rect x="4" y="5" width="6" height="1" fill="#3D7A2D"/><rect x="14" y="5" width="6" height="1" fill="#3D7A2D"/>',
            '<rect x="3" y="6" width="7" height="2" fill="#fff"/><rect x="14" y="6" width="7" height="2" fill="#fff"/>',
            '<rect x="4" y="8" width="6" height="1" fill="#fff"/><rect x="14" y="8" width="6" height="1" fill="#fff"/>',
            '<rect x="5" y="7" width="2" height="1" fill="#1A0A0A"/><rect x="17" y="7" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="6" y="11" width="12" height="1" fill="#7C4A1F"/>',
            '<rect x="5" y="12" width="14" height="1" fill="#7C4A1F"/>',
            '<rect x="7" y="12" width="10" height="1" fill="#5C3A18"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#7C4A1F"/>',
            '<rect x="7" y="13" width="10" height="1" fill="#3D2817"/>',
            '<rect x="0" y="17" width="24" height="7" fill="#DC2626"/>',
            '<rect x="0" y="17" width="24" height="1" fill="#991B1B"/>',
            '<rect x="11" y="17" width="2" height="1" fill="#fff"/>',
            '<rect x="11" y="20" width="1" height="1" fill="#FFD700"/>',
            '<rect x="11" y="22" width="1" height="1" fill="#FFD700"/>',
            '</svg>'
        ));
    }

    function _moodeng() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">',
            '<rect width="24" height="24" fill="#FBD4DA"/>',
            '<rect x="4" y="3" width="2" height="1" fill="#A8A4BA"/><rect x="18" y="3" width="2" height="1" fill="#A8A4BA"/>',
            '<rect x="4" y="4" width="2" height="1" fill="#7D788F"/><rect x="18" y="4" width="2" height="1" fill="#7D788F"/>',
            '<rect x="6" y="4" width="12" height="1" fill="#A8A4BA"/>',
            '<rect x="5" y="5" width="14" height="1" fill="#A8A4BA"/>',
            '<rect x="4" y="6" width="16" height="1" fill="#A8A4BA"/>',
            '<rect x="4" y="7" width="3" height="1" fill="#A8A4BA"/>',
            '<rect x="7" y="7" width="1" height="1" fill="#fff"/><rect x="8" y="7" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="10" y="7" width="4" height="1" fill="#A8A4BA"/>',
            '<rect x="14" y="7" width="2" height="1" fill="#1A0A0A"/><rect x="16" y="7" width="1" height="1" fill="#fff"/>',
            '<rect x="17" y="7" width="3" height="1" fill="#A8A4BA"/>',
            '<rect x="4" y="8" width="16" height="1" fill="#A8A4BA"/>',
            '<rect x="3" y="9" width="18" height="1" fill="#A8A4BA"/>',
            '<rect x="6" y="9" width="2" height="1" fill="#FF8FA3"/><rect x="16" y="9" width="2" height="1" fill="#FF8FA3"/>',
            '<rect x="3" y="10" width="18" height="1" fill="#A8A4BA"/>',
            '<rect x="9" y="10" width="2" height="1" fill="#1A0A0A"/><rect x="13" y="10" width="2" height="1" fill="#1A0A0A"/>',
            '<rect x="3" y="11" width="18" height="1" fill="#A8A4BA"/>',
            '<rect x="7" y="11" width="10" height="1" fill="#FF7A95"/>',
            '<rect x="9" y="11" width="2" height="1" fill="#fff"/><rect x="13" y="11" width="2" height="1" fill="#fff"/>',
            '<rect x="3" y="12" width="18" height="1" fill="#A8A4BA"/>',
            '<rect x="8" y="12" width="8" height="1" fill="#D14A6A"/>',
            '<rect x="3" y="13" width="18" height="1" fill="#A8A4BA"/>',
            '<rect x="5" y="13" width="14" height="1" fill="#C9C6D4"/>',
            '<rect x="2" y="14" width="20" height="3" fill="#A8A4BA"/>',
            '<rect x="4" y="14" width="16" height="3" fill="#C9C6D4"/>',
            '<rect x="3" y="17" width="18" height="1" fill="#A8A4BA"/>',
            '<rect x="3" y="18" width="3" height="2" fill="#7D788F"/><rect x="8" y="18" width="3" height="2" fill="#7D788F"/>',
            '<rect x="13" y="18" width="3" height="2" fill="#7D788F"/><rect x="18" y="18" width="3" height="2" fill="#7D788F"/>',
            '</svg>'
        ));
    }
}
