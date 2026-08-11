// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

library MessageHashUtils {
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory data = new bytes(60);
        for (uint i = 0; i < 28; i++) {
            data[i] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            data[28 + i] = messageHash[i];
        }
        digest = keccak256(data);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        string memory lenStr = Strings.toString(message.length);
        bytes memory lenBytes = bytes(lenStr);
        bytes memory prefix = "\x19Ethereum Signed Message:\n";
        bytes memory result = new bytes(prefix.length + lenBytes.length + message.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            result[offset++] = prefix[i];
        }
        for (uint i = 0; i < lenBytes.length; i++) {
            result[offset++] = lenBytes[i];
        }
        for (uint i = 0; i < message.length; i++) {
            result[offset++] = message[i];
        }
        return keccak256(result);
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        bytes memory prefix = hex"1900";
        bytes memory result = new bytes(prefix.length + 20 + data.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            result[offset++] = prefix[i];
        }
        bytes20 addrBytes = bytes20(validator);
        for (uint i = 0; i < 20; i++) {
            result[offset++] = addrBytes[i];
        }
        for (uint i = 0; i < data.length; i++) {
            result[offset++] = data[i];
        }
        return keccak256(result);
    }

    function toDataWithIntendedValidatorHash(
        address validator,
        bytes32 messageHash
    ) internal pure returns (bytes32 digest) {
        bytes memory data = new bytes(54);
        data[0] = 0x19;
        data[1] = 0x00;
        bytes20 addrBytes = bytes20(validator);
        for (uint i = 0; i < 20; i++) {
            data[2 + i] = addrBytes[i];
        }
        for (uint i = 0; i < 32; i++) {
            data[22 + i] = messageHash[i];
        }
        digest = keccak256(data);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        bytes memory data = new bytes(66);
        data[0] = 0x19;
        data[1] = 0x01;
        for (uint i = 0; i < 32; i++) {
            data[2 + i] = domainSeparator[i];
        }
        for (uint i = 0; i < 32; i++) {
            data[34 + i] = structHash[i];
        }
        digest = keccak256(data);
    }
}