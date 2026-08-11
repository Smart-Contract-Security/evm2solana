// SPDX-License-Identifier: MIT

import "./DaemonToken.sol";

/**
 * @title DAEMONS Renderer
 * @author DAEMONSv4
 * @notice Onchain SVG renderer for frozen and live DAEMON artifacts
 *
 * Website: https://daemons.life
 * Twitter: https://x.com/DAEMONSv4
 *
 * Renders compact 24x24 artifact SVGs directly from packed traits,
 * corruption, aura, and freeze state. The wrapper uses this contract
 * for ERC721 metadata after a holder wraps 1 whole DAEMON.
 */

contract DaemonRenderer {
    uint64 public constant CONTRACT_REVISION = 5;

    DaemonToken public immutable token;

    constructor(DaemonToken daemonToken) {
        token = daemonToken;
    }

    function tokenURI(uint64 id, address host, uint64 traits, uint64 corruption, uint64 aura, bool frozen)
        external
        pure
        returns (string memory)
    {
        string memory name = string.concat("DAEMON #", _toString(id));
        string memory image = _svg(traits, corruption, aura, frozen);
        return string.concat(
            "data:application/json;utf8,{\"name\":\"",
            name,
            "\",\"description\":\"ERC20 onchain art object powered by Uniswap v4 hooks.\",\"image\":\"data:image/svg+xml;utf8,",
            image,
            "\",\"attributes\":[{\"trait_type\":\"Host\",\"value\":\"",
            _addressString(host),
            "\"},{\"trait_type\":\"Corruption\",\"value\":\"",
            _toString(corruption),
            "\"},{\"trait_type\":\"Aura\",\"value\":\"",
            _toString(aura),
            "\"},{\"trait_type\":\"Frozen\",\"value\":\"",
            frozen ? "true" : "false",
            "\"}]}"
        );
    }

    function renderLive(address host, uint64 index) external view returns (string memory) {
        DaemonToken.ArtifactState memory state = token.getArtifactState(host);
        uint64 traits = token.deriveArtifactTraits(host, index);
        return _svg(traits, state.corruption, state.aura, false);
    }

    function _svg(uint64 traits, uint64 corruption, uint64 aura, bool frozen) internal pure returns (string memory) {
        uint64 body = traits & 0xff;
        uint64 eyes = (traits >> 8) & 0xff;
        uint64 sigil = (traits >> 16) & 0xff;
        uint64 palette = (traits >> 24) & 0xff;
        string memory c0 = _color((palette + body) % 24);
        string memory c1 = _color((palette + eyes + corruption / 25) % 24);
        string memory c2 = _color((palette + sigil + aura * 3) % 24);
        string memory anim = aura == 0 || frozen
            ? ""
            : "<animate attributeName='opacity' values='0.35;1;0.35' dur='1.6s' repeatCount='indefinite'/>";

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' shape-rendering='crispEdges'>",
            "<rect width='24' height='24' fill='#050505'/>",
            "<rect x='4' y='3' width='16' height='18' fill='",
            c0,
            "'/>",
            "<rect x='7' y='7' width='3' height='3' fill='",
            c1,
            "'/><rect x='14' y='7' width='3' height='3' fill='",
            c1,
            "'/>",
            "<rect x='10' y='12' width='4' height='2' fill='",
            c2,
            "'/>",
            "<rect x='5' y='20' width='14' height='1' fill='",
            frozen ? "#d8d8d8" : c2,
            "'/>",
            aura == 0
                ? ""
                : string.concat(
                    "<rect x='2' y='2' width='20' height='20' fill='none' stroke='", c2, "'>", anim, "</rect>"
                ),
            "</svg>"
        );
    }

    function _color(uint64 index) internal pure returns (string memory) {
        string[24] memory colors = [
            "#f5f5f5",
            "#d8ff3d",
            "#39ff88",
            "#39d7ff",
            "#8b5cff",
            "#ff4fd8",
            "#ff4655",
            "#ffa23a",
            "#ffe66d",
            "#93ffed",
            "#c084fc",
            "#fb7185",
            "#94a3b8",
            "#22c55e",
            "#06b6d4",
            "#a3e635",
            "#e879f9",
            "#f97316",
            "#facc15",
            "#2dd4bf",
            "#60a5fa",
            "#f472b6",
            "#e5e7eb",
            "#84cc16"
        ];
        return colors[index % 24];
    }

    function _toString(uint64 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint64 temp = value;
        uint64 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _addressString(address account) internal pure returns (string memory) {
        bytes20 value = bytes20(account);
        bytes16 alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint64 i; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }
}