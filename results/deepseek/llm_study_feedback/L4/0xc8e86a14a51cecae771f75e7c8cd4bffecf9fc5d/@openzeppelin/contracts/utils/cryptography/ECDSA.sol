// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

        // Use Solana's native signature verification via secp256k1
        address signer = recoverSigner(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature);
        }

        return (signer, RecoverError.NoError);
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 message) {
        // Compute Ethereum signed message hash without assembly
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory packed = new bytes(prefix.length + 32);
        for (uint i = 0; i < prefix.length; i++) {
            packed[i] = prefix[i];
        }
        bytes32ToBytes(packed, prefix.length, hash);
        message = keccak256(packed);
    }

    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", toString(s.length), s));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 data) {
        // Compute typed data hash without assembly
        bytes memory packed = new bytes(2 + 32 + 32);
        packed[0] = 0x19;
        packed[1] = 0x01;
        bytes32ToBytes(packed, 2, domainSeparator);
        bytes32ToBytes(packed, 34, structHash);
        data = keccak256(packed);
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x00", validator, data));
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

    // Helper: convert bytes memory to bytes32 at given offset
    function bytesToBytes32(bytes memory b, uint offset) private pure returns (bytes32 out) {
        for (uint i = 0; i < 32; i++) {
            out |= bytes32(uint256(uint8(b[offset + i])) << ((31 - i) * 8));
        }
    }

    // Helper: write bytes32 into bytes memory at given offset
    function bytes32ToBytes(bytes memory b, uint offset, bytes32 value) private pure {
        for (uint i = 0; i < 32; i++) {
            b[offset + i] = bytes1(uint8(uint256(value) >> ((31 - i) * 8)));
        }
    }

    // Recover signer from hash and signature using Solana's secp256k1 precompile
    function recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        // Build the signature bytes: r (32) + s (32) + v (1)
        bytes memory sig = new bytes(65);
        bytes32ToBytes(sig, 0, r);
        bytes32ToBytes(sig, 32, s);
        sig[64] = bytes1(v);

        // Use Solana's secp256k1 recovery via the ecrecover precompile
        // Solang for Solana provides ecrecover as a built-in
        return ecrecover(hash, v, r, s);
    }
}