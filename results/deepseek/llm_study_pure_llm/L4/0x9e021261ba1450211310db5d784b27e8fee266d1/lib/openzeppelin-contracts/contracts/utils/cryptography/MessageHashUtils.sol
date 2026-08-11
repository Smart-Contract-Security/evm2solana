// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library MessageHashUtils {
    error ERC5267ExtensionsNotSupported();

    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory data = new bytes(prefix.length + 32);
        for (uint i = 0; i < prefix.length; i++) {
            data[i] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            data[prefix.length + i] = messageHash[i];
        }
        digest = keccak256(data);
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
        bytes20 addrBytes = bytes20(validator);
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
        bytes memory data = new bytes(2 + 20 + 32);
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
        bytes memory data = new bytes(2 + 32 + 32);
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

    function toDomainSeparator(
        bytes1 fields,
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract,
        bytes32 salt
    ) internal pure returns (bytes32 hash) {
        return
            toDomainSeparator(
                fields,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract,
                salt
            );
    }

    function toDomainSeparator(
        bytes1 fields,
        bytes32 nameHash,
        bytes32 versionHash,
        uint256 chainId,
        address verifyingContract,
        bytes32 salt
    ) internal pure returns (bytes32 hash) {
        bytes32 domainTypeHash = toDomainTypeHash(fields);

        uint8 f = uint8(fields);
        uint size = 32; // domainTypeHash
        if (f & 0x01 != 0) size += 32;
        if (f & 0x02 != 0) size += 32;
        if (f & 0x04 != 0) size += 32;
        if (f & 0x08 != 0) size += 32;
        if (f & 0x10 != 0) size += 32;

        bytes memory data = new bytes(size);
        uint offset = 0;
        for (uint i = 0; i < 32; i++) {
            data[offset++] = domainTypeHash[i];
        }
        if (f & 0x01 != 0) {
            for (uint i = 0; i < 32; i++) {
                data[offset++] = nameHash[i];
            }
        }
        if (f & 0x02 != 0) {
            for (uint i = 0; i < 32; i++) {
                data[offset++] = versionHash[i];
            }
        }
        if (f & 0x04 != 0) {
            for (uint i = 0; i < 32; i++) {
                data[offset++] = bytes32(chainId)[i];
            }
        }
        if (f & 0x08 != 0) {
            bytes20 addrBytes = bytes20(verifyingContract);
            for (uint i = 0; i < 20; i++) {
                data[offset++] = addrBytes[i];
            }
            for (uint i = 0; i < 12; i++) {
                data[offset++] = 0;
            }
        }
        if (f & 0x10 != 0) {
            for (uint i = 0; i < 32; i++) {
                data[offset++] = salt[i];
            }
        }
        hash = keccak256(data);
    }

    function toDomainTypeHash(bytes1 fields) internal pure returns (bytes32 hash) {
        if (fields & 0x20 == 0x20) revert ERC5267ExtensionsNotSupported();

        uint8 f = uint8(fields);
        string memory typeStr = "EIP712Domain(";
        if (f & 0x01 != 0) typeStr = string(abi.encodePacked(typeStr, "string name,"));
        if (f & 0x02 != 0) typeStr = string(abi.encodePacked(typeStr, "string version,"));
        if (f & 0x04 != 0) typeStr = string(abi.encodePacked(typeStr, "uint256 chainId,"));
        if (f & 0x08 != 0) typeStr = string(abi.encodePacked(typeStr, "address verifyingContract,"));
        if (f & 0x10 != 0) typeStr = string(abi.encodePacked(typeStr, "bytes32 salt,"));

        bytes memory typeBytes = bytes(typeStr);
        if (f & 0x1f != 0) {
            // remove trailing comma
            uint len = typeBytes.length;
            bytes memory trimmed = new bytes(len - 1);
            for (uint i = 0; i < len - 1; i++) {
                trimmed[i] = typeBytes[i];
            }
            typeBytes = trimmed;
        }
        // add closing brace
        bytes memory withBrace = new bytes(typeBytes.length + 1);
        for (uint i = 0; i < typeBytes.length; i++) {
            withBrace[i] = typeBytes[i];
        }
        withBrace[typeBytes.length] = 0x29;
        hash = keccak256(withBrace);
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