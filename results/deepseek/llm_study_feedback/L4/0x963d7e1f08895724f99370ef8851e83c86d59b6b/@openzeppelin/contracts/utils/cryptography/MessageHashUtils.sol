// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library MessageHashUtils {
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
        bytes memory data = new bytes(2 + 20 + 32);
        data[0] = 0x19;
        data[1] = 0x00;
        bytes20 addrBytes = bytes20(uint160(validator));
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
        uint totalLen = 32; // domainTypeHash
        if (f & 0x01 != 0) totalLen += 32;
        if (f & 0x02 != 0) totalLen += 32;
        if (f & 0x04 != 0) totalLen += 32;
        if (f & 0x08 != 0) totalLen += 32;
        if (f & 0x10 != 0) totalLen += 32;

        bytes memory buffer = new bytes(totalLen);
        uint offset = 0;
        for (uint i = 0; i < 32; i++) {
            buffer[offset++] = domainTypeHash[i];
        }
        if (f & 0x01 != 0) {
            for (uint i = 0; i < 32; i++) {
                buffer[offset++] = nameHash[i];
            }
        }
        if (f & 0x02 != 0) {
            for (uint i = 0; i < 32; i++) {
                buffer[offset++] = versionHash[i];
            }
        }
        if (f & 0x04 != 0) {
            for (uint i = 0; i < 32; i++) {
                buffer[offset++] = bytes32(chainId)[i];
            }
        }
        if (f & 0x08 != 0) {
            bytes20 addrBytes = bytes20(uint160(verifyingContract));
            for (uint i = 0; i < 12; i++) {
                buffer[offset++] = 0;
            }
            for (uint i = 0; i < 20; i++) {
                buffer[offset++] = addrBytes[i];
            }
        }
        if (f & 0x10 != 0) {
            for (uint i = 0; i < 32; i++) {
                buffer[offset++] = salt[i];
            }
        }
        hash = keccak256(buffer);
    }

    function toDomainTypeHash(bytes1 fields) internal pure returns (bytes32 hash) {
        if (fields & 0x20 == 0x20) {
            // revert with custom errors not supported on Solana, use string revert
            revert("ERC5267ExtensionsNotSupported");
        }

        uint8 f = uint8(fields);
        string memory typeString = "EIP712Domain(";
        if (f & 0x01 != 0) {
            typeString = string(abi.encodePacked(typeString, "string name,"));
        }
        if (f & 0x02 != 0) {
            typeString = string(abi.encodePacked(typeString, "string version,"));
        }
        if (f & 0x04 != 0) {
            typeString = string(abi.encodePacked(typeString, "uint256 chainId,"));
        }
        if (f & 0x08 != 0) {
            typeString = string(abi.encodePacked(typeString, "address verifyingContract,"));
        }
        if (f & 0x10 != 0) {
            typeString = string(abi.encodePacked(typeString, "bytes32 salt,"));
        }
        // Remove trailing comma if any field was added
        if (f & 0x1f != 0) {
            bytes memory tmp = bytes(typeString);
            bytes memory trimmed = new bytes(tmp.length - 1);
            for (uint i = 0; i < trimmed.length; i++) {
                trimmed[i] = tmp[i];
            }
            typeString = string(trimmed);
        }
        typeString = string(abi.encodePacked(typeString, ")"));
        hash = keccak256(bytes(typeString));
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