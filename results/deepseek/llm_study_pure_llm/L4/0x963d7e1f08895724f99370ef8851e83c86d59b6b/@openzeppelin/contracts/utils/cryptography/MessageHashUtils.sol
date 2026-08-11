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
        string memory lenStr = Strings.toString(message.length);
        bytes memory prefix1 = "\x19Ethereum Signed Message:\n";
        bytes memory prefix2 = bytes(lenStr);
        bytes memory data = new bytes(prefix1.length + prefix2.length + message.length);
        uint offset = 0;
        for (uint i = 0; i < prefix1.length; i++) {
            data[offset++] = prefix1[i];
        }
        for (uint i = 0; i < prefix2.length; i++) {
            data[offset++] = prefix2[i];
        }
        for (uint i = 0; i < message.length; i++) {
            data[offset++] = message[i];
        }
        return keccak256(data);
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
            for (uint i = 0; i < 12; i++) {
                data[offset++] = 0;
            }
            for (uint i = 0; i < 20; i++) {
                data[offset++] = addrBytes[i];
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
        string memory s = "EIP712Domain(";
        if (f & 0x01 != 0) s = string(abi.encodePacked(s, "string name,"));
        if (f & 0x02 != 0) s = string(abi.encodePacked(s, "string version,"));
        if (f & 0x04 != 0) s = string(abi.encodePacked(s, "uint256 chainId,"));
        if (f & 0x08 != 0) s = string(abi.encodePacked(s, "address verifyingContract,"));
        if (f & 0x10 != 0) s = string(abi.encodePacked(s, "bytes32 salt,"));

        bytes memory b = bytes(s);
        if (f & 0x1f != 0) {
            // remove trailing comma
            bytes memory trimmed = new bytes(b.length - 1);
            for (uint i = 0; i < trimmed.length; i++) {
                trimmed[i] = b[i];
            }
            b = trimmed;
        }
        // add closing brace
        bytes memory withBrace = new bytes(b.length + 1);
        for (uint i = 0; i < b.length; i++) {
            withBrace[i] = b[i];
        }
        withBrace[b.length] = 0x29;
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