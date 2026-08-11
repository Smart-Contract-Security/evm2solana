// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library MessageHashUtils {
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory result = new bytes(60);
        for (uint i = 0; i < 28; i++) {
            result[i] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            result[28 + i] = messageHash[i];
        }
        digest = keccak256(result);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n";
        bytes memory lenStr = bytes(Strings.toString(message.length));
        bytes memory combined = new bytes(prefix.length + lenStr.length + message.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            combined[offset++] = prefix[i];
        }
        for (uint i = 0; i < lenStr.length; i++) {
            combined[offset++] = lenStr[i];
        }
        for (uint i = 0; i < message.length; i++) {
            combined[offset++] = message[i];
        }
        return keccak256(combined);
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        bytes memory prefix = hex"1900";
        bytes memory encoded = new bytes(prefix.length + 20 + data.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            encoded[offset++] = prefix[i];
        }
        bytes20 addrBytes = bytes20(uint160(validator));
        for (uint i = 0; i < 20; i++) {
            encoded[offset++] = addrBytes[i];
        }
        for (uint i = 0; i < data.length; i++) {
            encoded[offset++] = data[i];
        }
        return keccak256(encoded);
    }

    function toDataWithIntendedValidatorHash(
        address validator,
        bytes32 messageHash
    ) internal pure returns (bytes32 digest) {
        bytes memory result = new bytes(54);
        result[0] = 0x19;
        result[1] = 0x00;
        bytes20 addrBytes = bytes20(uint160(validator));
        for (uint i = 0; i < 20; i++) {
            result[2 + i] = addrBytes[i];
        }
        for (uint i = 0; i < 32; i++) {
            result[22 + i] = messageHash[i];
        }
        digest = keccak256(result);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        bytes memory result = new bytes(66);
        result[0] = 0x19;
        result[1] = 0x01;
        for (uint i = 0; i < 32; i++) {
            result[2 + i] = domainSeparator[i];
        }
        for (uint i = 0; i < 32; i++) {
            result[34 + i] = structHash[i];
        }
        digest = keccak256(result);
    }
}

library Strings {
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
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