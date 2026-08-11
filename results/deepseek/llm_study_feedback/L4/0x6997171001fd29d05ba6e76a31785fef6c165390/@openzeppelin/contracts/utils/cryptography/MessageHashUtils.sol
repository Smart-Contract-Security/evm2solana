// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
        bytes memory prefix = "\x19Ethereum Signed Message:\n";
        bytes memory lenStr = bytes(uint2str(message.length));
        bytes memory data = new bytes(prefix.length + lenStr.length + message.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            data[offset++] = prefix[i];
        }
        for (uint i = 0; i < lenStr.length; i++) {
            data[offset++] = lenStr[i];
        }
        for (uint i = 0; i < message.length; i++) {
            data[offset++] = message[i];
        }
        return keccak256(data);
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        bytes memory prefix = hex"1900";
        bytes memory encoded = new bytes(prefix.length + 20 + data.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            encoded[offset++] = prefix[i];
        }
        bytes20 addrBytes = bytes20(bytes.concat(bytes32(uint256(uint160(validator)))));
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
        bytes memory data = new bytes(54);
        data[0] = 0x19;
        data[1] = 0x00;
        bytes20 addrBytes = bytes20(bytes.concat(bytes32(uint256(uint160(validator)))));
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

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}