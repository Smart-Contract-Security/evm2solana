// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.6.0) (utils/cryptography/MessageHashUtils.sol)

library MessageHashUtils {
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory data = new bytes(0x3c);
        for (uint64 i = 0; i < 0x1c; i++) {
            data[i] = prefix[i];
        }
        for (uint64 i = 0; i < 0x20; i++) {
            data[0x1c + i] = messageHash[i];
        }
        digest = keccak256(data);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return
            keccak256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(uintToString(message.length)), message));
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"19_00", validator, data));
    }

    function toDataWithIntendedValidatorHash(
        address validator,
        bytes32 messageHash
    ) internal pure returns (bytes32 digest) {
        bytes memory data = new bytes(0x36);
        data[0] = 0x19;
        data[1] = 0x00;
        for (uint64 i = 0; i < 0x14; i++) {
            data[2 + i] = bytes32(uint256(uint160(validator)))[12 + i];
        }
        for (uint64 i = 0; i < 0x20; i++) {
            data[0x16 + i] = messageHash[i];
        }
        digest = keccak256(data);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        bytes memory data = new bytes(0x42);
        data[0] = 0x19;
        data[1] = 0x01;
        for (uint64 i = 0; i < 0x20; i++) {
            data[2 + i] = domainSeparator[i];
        }
        for (uint64 i = 0; i < 0x20; i++) {
            data[0x22 + i] = structHash[i];
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
        uint64 size = 0x20;
        if (f & 0x01 != 0) size += 0x20;
        if (f & 0x02 != 0) size += 0x20;
        if (f & 0x04 != 0) size += 0x20;
        if (f & 0x08 != 0) size += 0x20;
        if (f & 0x10 != 0) size += 0x20;

        bytes memory data = new bytes(size);
        uint64 ptr = 0;
        for (uint64 i = 0; i < 0x20; i++) {
            data[ptr + i] = domainTypeHash[i];
        }
        ptr += 0x20;
        if (f & 0x01 != 0) {
            for (uint64 i = 0; i < 0x20; i++) {
                data[ptr + i] = nameHash[i];
            }
            ptr += 0x20;
        }
        if (f & 0x02 != 0) {
            for (uint64 i = 0; i < 0x20; i++) {
                data[ptr + i] = versionHash[i];
            }
            ptr += 0x20;
        }
        if (f & 0x04 != 0) {
            for (uint64 i = 0; i < 0x20; i++) {
                data[ptr + i] = bytes32(chainId)[i];
            }
            ptr += 0x20;
        }
        if (f & 0x08 != 0) {
            for (uint64 i = 0; i < 0x20; i++) {
                data[ptr + i] = bytes32(uint256(uint160(verifyingContract)))[i];
            }
            ptr += 0x20;
        }
        if (f & 0x10 != 0) {
            for (uint64 i = 0; i < 0x20; i++) {
                data[ptr + i] = salt[i];
            }
            ptr += 0x20;
        }

        hash = keccak256(data);
    }

    function toDomainTypeHash(bytes1 fields) internal pure returns (bytes32 hash) {
        if (fields & 0x20 == 0x20) {
            // ERC5267ExtensionsNotSupported - revert with a panic instead
            assert(false);
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
        if (f & 0x1f != 0) {
            bytes memory tmp = bytes(typeString);
            bytes memory trimmed = new bytes(tmp.length - 1);
            for (uint64 i = 0; i < trimmed.length; i++) {
                trimmed[i] = tmp[i];
            }
            typeString = string(trimmed);
        }
        typeString = string(abi.encodePacked(typeString, ")"));
        hash = keccak256(bytes(typeString));
    }

    function uintToString(uint256 value) internal pure returns (string memory) {
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