// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/MessageHashUtils.sol)

library MessageHashUtils {
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

    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory data = new bytes(0x3c);
        for (uint i = 0; i < 0x1c; i++) {
            data[i] = prefix[i];
        }
        for (uint i = 0; i < 0x20; i++) {
            data[0x1c + i] = messageHash[i];
        }
        digest = keccak256(data);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return
            keccak256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(toString(message.length)), message));
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
        bytes memory validatorBytes = abi.encodePacked(validator);
        for (uint i = 0; i < 0x14; i++) {
            data[2 + i] = validatorBytes[i];
        }
        for (uint i = 0; i < 0x20; i++) {
            data[0x16 + i] = messageHash[i];
        }
        digest = keccak256(data);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        bytes memory data = new bytes(0x42);
        data[0] = 0x19;
        data[1] = 0x01;
        for (uint i = 0; i < 0x20; i++) {
            data[2 + i] = domainSeparator[i];
        }
        for (uint i = 0; i < 0x20; i++) {
            data[0x22 + i] = structHash[i];
        }
        digest = keccak256(data);
    }
}