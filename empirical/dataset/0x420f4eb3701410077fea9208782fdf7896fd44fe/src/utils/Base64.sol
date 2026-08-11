// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal base64 encoder for metadata and SVG data URIs.
library Base64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) {
            return "";
        }

        string memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);

        assembly ("memory-safe") {
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
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }
        }

        return result;
    }

    /// @notice Decode a standard base64 ASCII string. Assumes well-formed input
    ///         (chars A-Z, a-z, 0-9, +, /, optional `=` padding). Invalid chars
    ///         are silently treated as 0.
    function decode(string memory data) internal pure returns (bytes memory) {
        bytes memory input = bytes(data);
        uint256 inLen = input.length;
        if (inLen == 0) return new bytes(0);

        // Trim padding to compute exact output length.
        uint256 pad = 0;
        if (input[inLen - 1] == "=") pad = 1;
        if (inLen >= 2 && input[inLen - 2] == "=") pad = 2;
        uint256 outLen = (inLen / 4) * 3 - pad;

        bytes memory result = new bytes(outLen);
        uint256 outIdx = 0;
        for (uint256 i = 0; i < inLen; i += 4) {
            uint256 c0 = _b64char(uint8(input[i]));
            uint256 c1 = _b64char(uint8(input[i + 1]));
            uint256 c2 = _b64char(uint8(input[i + 2]));
            uint256 c3 = _b64char(uint8(input[i + 3]));
            uint256 triple = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;
            if (outIdx < outLen) { result[outIdx] = bytes1(uint8(triple >> 16)); outIdx++; }
            if (outIdx < outLen) { result[outIdx] = bytes1(uint8((triple >> 8) & 0xFF)); outIdx++; }
            if (outIdx < outLen) { result[outIdx] = bytes1(uint8(triple & 0xFF)); outIdx++; }
        }
        return result;
    }

    function _b64char(uint8 c) private pure returns (uint256) {
        // A-Z: 0..25
        if (c >= 65 && c <= 90) return c - 65;
        // a-z: 26..51
        if (c >= 97 && c <= 122) return c - 71;
        // 0-9: 52..61
        if (c >= 48 && c <= 57) return c + 4;
        // '+': 62
        if (c == 43) return 62;
        // '/': 63
        if (c == 47) return 63;
        return 0;
    }
}
