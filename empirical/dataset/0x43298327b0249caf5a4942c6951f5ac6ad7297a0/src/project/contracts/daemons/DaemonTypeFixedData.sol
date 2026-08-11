// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library DaemonTypeFixedData {
    function etColor(uint8 color) public pure returns (string memory) {
        if (color == 0) return "#4e4e4e";
        if (color == 1) return "#000000";
        if (color == 2) return "#0f0f0f";
        revert();
    }

    function etRows(uint8 color) public pure returns (uint24[24] memory rows) {
        return _rows(
            hex"0000000000000000000100400600300c1e180cff1807ffb00301e00200c00200c00600600400600400600400600400600200600100c0008180006380001b800005c00002e00002f000000000000000000000000000000000000000000000000000fe00018300010100010180030080020080020080020080010080008100006200001c00000400000200000100000100000000000000000000000000000000000000000000000000000000007c0000fe0000fe0000ff0001ff0001ff0001ff0000ff00007e00001c00000000000000000000000000000000",
            color,
            3
        );
    }

    function _rows(bytes memory data, uint8 id, uint8 count) private pure returns (uint24[24] memory rows) {
        if (id >= count) revert();
        uint256 offset = uint256(id) * 72;
        for (uint8 y = 0; y < 24; ++y) {
            uint256 cursor = offset + uint256(y) * 3;
            rows[y] = (uint24(uint8(data[cursor])) << 16) | (uint24(uint8(data[cursor + 1])) << 8)
                | uint24(uint8(data[cursor + 2]));
        }
    }
}
