// SPDX-License-Identifier: MIT

library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV
    }

    function _throwError(RecoverError error) private pure {
        if (error == RecoverError.NoError) {
            return;
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSA: invalid signature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSA: invalid signature length");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSA: invalid signature 's' value");
        }
    }

    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // Extract r, s, v from signature bytes without assembly
            r = bytesToBytes32(signature, 0);
            s = bytesToBytes32(signature, 32);
            v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength);
        }
    }

    function bytesToBytes32(bytes memory b, uint offset) private pure returns (bytes32 out) {
        for (uint i = 0; i < 32; i++) {
            out |= bytes32(uint(b[offset + i])) >> (i * 8);
        }
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, signature);
        _throwError(error);
        return recovered;
    }

    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address, RecoverError) {
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }

        // Solana does not have ecrecover builtin.
        // We use the Solana syscall for secp256k1 signature verification.
        // The signature is verified by calling the secp256k1 program.
        // For simplicity, we return a placeholder; actual verification requires
        // calling the secp256k1 program via CPI, which is not expressible in pure Solidity.
        // This function is kept for interface compatibility.
        // In practice, signature recovery on Solana requires off-chain computation
        // or using the secp256k1 precompile via external call.
        revert("ECDSA: ecrecover not available on Solana");
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 message) {
        // Construct the Ethereum signed message prefix manually
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory combined = new bytes(prefix.length + 32);
        for (uint i = 0; i < prefix.length; i++) {
            combined[i] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            combined[prefix.length + i] = hash[i];
        }
        message = keccak256(combined);
    }

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

    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        string memory lenStr = toString(s.length);
        bytes memory prefix = "\x19Ethereum Signed Message:\n";
        bytes memory combined = new bytes(prefix.length + bytes(lenStr).length + s.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            combined[offset++] = prefix[i];
        }
        bytes memory lenBytes = bytes(lenStr);
        for (uint i = 0; i < lenBytes.length; i++) {
            combined[offset++] = lenBytes[i];
        }
        for (uint i = 0; i < s.length; i++) {
            combined[offset++] = s[i];
        }
        return keccak256(combined);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 data) {
        bytes memory combined = new bytes(66);
        combined[0] = 0x19;
        combined[1] = 0x01;
        for (uint i = 0; i < 32; i++) {
            combined[2 + i] = domainSeparator[i];
        }
        for (uint i = 0; i < 32; i++) {
            combined[34 + i] = structHash[i];
        }
        data = keccak256(combined);
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        bytes memory prefix = "\x19\x00";
        bytes memory combined = new bytes(prefix.length + 32 + data.length);
        uint offset = 0;
        for (uint i = 0; i < prefix.length; i++) {
            combined[offset++] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            combined[offset++] = bytes32(uint256(uint160(validator)))[i];
        }
        for (uint i = 0; i < data.length; i++) {
            combined[offset++] = data[i];
        }
        return keccak256(combined);
    }
}