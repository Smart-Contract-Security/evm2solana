// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./base64.sol";

/// @notice Monochrome animated side-window starfield SVG renderer.
/// @dev Designed to visually approximate the simplified vanilla canvas sketch:
///      - 16:9 canvas
///      - black space
///      - large rounded side window mask
///      - sideways drifting stars that recycle from the right
///      - positions are deterministic from tokenId + block.number
///
/// This intentionally returns raw SVG. Wrap it in your tokenURI renderer as:
/// image: "data:image/svg+xml;base64,..."
contract The_Long_Drift_SVG {
    uint256 internal constant W = 1600;
    uint256 internal constant H = 900;

    // From the JS sketch:
    // windowScale = 0.869
    // window height = H * windowScale * 0.66
    uint256 internal constant WIN_W = 1390;
    uint256 internal constant WIN_H = 516;
    uint256 internal constant WIN_X = (W - WIN_W) / 2; // 105
    uint256 internal constant WIN_Y = (H - WIN_H) / 2; // 192
    uint256 internal constant WIN_R = 64;

    uint256 internal constant STAR_COUNT = 48; // JS used 260. 180 is already a large SVG.

    uint256 internal constant CYCLE = 1800; // width + offscreen recycle buffer
    uint256 internal constant STAR_DUR_BASE = 42; // seconds; larger = slower
    uint256 internal constant CLOUD_DUR_BASE = 130; // seconds; very slow nebula drift

    function render() external view returns (string memory) {
        return svg();
    }

    function svg() public view returns (string memory) {
        bytes memory out = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" width="600" height="600" shape-rendering="geometricPrecision">',
            '<defs>',
                '<clipPath id="win"><rect x="105" y="192" width="1390" height="516" rx="64" ry="64"/></clipPath>',
                '<radialGradient id="bg" cx="46%" cy="48%" r="86%">',
                    '<stop offset="0%" stop-color="#202020" stop-opacity=".16"/>',
                    '<stop offset="38%" stop-color="#111" stop-opacity=".08"/>',
                    '<stop offset="100%" stop-color="#030304" stop-opacity="1"/>',
                '</radialGradient>',
                '<filter id="soft"><feGaussianBlur stdDeviation="18"/></filter>',
            '</defs>',
            '<rect width="1600" height="900" fill="#030304"/>',
            '<rect width="1600" height="900" fill="url(#bg)"/>',
            '<g clip-path="url(#win)">',
                '<rect width="1600" height="900" fill="#030304"/>'
        );

        out = abi.encodePacked(out, stars());

        out = abi.encodePacked(
            out,
            '</g>',
            // Black outside-window mask, matching the simplified canvas version.
            '<path fill="#000" fill-rule="evenodd" d="M0 0H1600V900H0Z M105 256Q105 192 169 192H1431Q1495 192 1495 256V644Q1495 708 1431 708H169Q105 708 105 644Z"/>',
            '</svg>'
        );

        return Base64.encode(out);
    }

    function stars() internal view returns (bytes memory out) {
        out = '<g>';

        for (uint256 i; i < STAR_COUNT; ++i) {
            uint256 z = 25 + (rand(block.number, i, 10) % 475); // JS z: 0.25..5.0 scaled by 100

            uint256 y = WIN_Y + 24 + (rand(block.number, i, 11) % (WIN_H - 48));
            uint256 baseX = WIN_X + (rand(block.number, i, 12) % WIN_W);
            uint256 grey = pickTone(rand(block.number, i, 13));

            // Close stars are brighter/larger/faster, matching parallax feel.
            uint256 radiusTimes10 = mapInv(z, 25, 500, 20, 4); // 2.0px to 0.4px, x10
            uint256 opacity = mapInv(z, 25, 500, 95, 26); // percent
            uint256 dur = STAR_DUR_BASE + ((z * 70) / 100); // far stars drift slower
            uint256 delay = rand(block.number, i, 14) % dur;

            uint256 phase = ((block.number + (rand(block.number, i, 15) % 10_000)) % dur) * CYCLE / dur;
            uint256 start = baseX + phase;

            // Slight vertical offset gives gentle non-mechanical drift.
            int256 dy = int256(rand(block.number, i, 16) % 15) - 7;
            uint256 y2 = addSigned(y, dy);

            out = abi.encodePacked(
                out,
                '<g><animateTransform attributeName="transform" type="translate" from="0 0" to="-1800 0" dur="',
                u(dur),
                's" begin="-',
                u(delay),
                's" repeatCount="indefinite"/>',
                    circle(start, y2, radiusTimes10, grey, opacity),
                    circle(start + CYCLE, y2, radiusTimes10, 240, opacity),
                '</g>'
            );
        }

        out = abi.encodePacked(out, '</g>');
    }

    function circle(
        uint256 cx,
        uint256 cy,
        uint256 rTimes10,
        uint256 grey,
        uint256 opacity
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '<circle cx="', u(cx),
            '" cy="', u(cy),
            '" r="', decimal1(rTimes10),
            '" fill="rgb(', u(grey), ',', u(grey), ',', u(grey), ')" opacity=".', pad2(opacity), '"/>'
        );
    }

    function pickTone(uint256 r) internal pure returns (uint256) {
        uint256 v = r % 5;
        if (v == 0) return 175;
        if (v == 1) return 200;
        if (v == 2) return 225;
        if (v == 3) return 245;
        return 255;
    }

    function mapInv(
        uint256 v,
        uint256 inMin,
        uint256 inMax,
        uint256 outMax,
        uint256 outMin
    ) internal pure returns (uint256) {
        if (v <= inMin) return outMax;
        if (v >= inMax) return outMin;
        return outMax - ((v - inMin) * (outMax - outMin)) / (inMax - inMin);
    }

    function addSigned(uint256 x, int256 y) internal pure returns (uint256) {
        if (y < 0) return x - uint256(-y);
        return x + uint256(y);
    }

    function rand(uint256 tokenId, uint256 i, uint256 salt) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenId, i, salt, block.number / 8)));
    }

    function decimal1(uint256 n) internal pure returns (string memory) {
        return string(abi.encodePacked(u(n / 10), '.', u(n % 10)));
    }

    function pad2(uint256 n) internal pure returns (string memory) {
        if (n >= 100) return '99';
        if (n < 10) return string(abi.encodePacked('0', u(n)));
        return u(n);
    }

    function pad3(uint256 n) internal pure returns (string memory) {
        if (n >= 1000) return '999';
        if (n < 10) return string(abi.encodePacked('00', u(n)));
        if (n < 100) return string(abi.encodePacked('0', u(n)));
        return u(n);
    }

    function u(uint256 value) internal pure returns (string memory) {
        if (value == 0) return '0';
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
