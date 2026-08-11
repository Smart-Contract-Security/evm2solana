// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
            // Extract r, s, v from signature without assembly
            // Solang does not support slices, so we copy manually
            bytes memory rBytes = new bytes(32);
            for (uint i = 0; i < 32; i++) {
                rBytes[i] = signature[i];
            }
            r = bytes32(rBytes);

            bytes memory sBytes = new bytes(32);
            for (uint i = 0; i < 32; i++) {
                sBytes[i] = signature[i + 32];
            }
            s = bytes32(sBytes);

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

        // Use Solana's secp256k1 ecrecover via the system call
        // Solang does not have ecrecover built-in, so we use the Solana syscall
        address signer = ecrecover_secp256k1(hash, v, r, s);
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
        // Use abi.encodePacked instead of assembly
        message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(s.length), s));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 data) {
        // Use abi.encodePacked instead of assembly
        data = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x00", validator, data));
    }

    // Solana secp256k1 ecrecover implementation using the Solana syscall
    function ecrecover_secp256k1(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        // Prepare the signature in the format expected by Solana's secp256k1_recover syscall
        // The signature is 64 bytes: r (32 bytes) || s (32 bytes)
        // The recovery id is v - 27 (0 or 1)
        uint8 recoveryId = v - 27;
        if (recoveryId > 1) {
            return address(0);
        }

        bytes memory signature = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            signature[i] = r[i];
        }
        for (uint i = 0; i < 32; i++) {
            signature[i + 32] = s[i];
        }

        // Call the Solana secp256k1_recover syscall
        // The syscall expects: hash (32 bytes), recovery_id (1 byte), signature (64 bytes)
        // It returns the public key (64 bytes) or fails
        bytes memory pubkey = new bytes(64);
        uint64 result = secp256k1_recover(hash, recoveryId, signature, pubkey);
        if (result != 0) {
            return address(0);
        }

        // Derive the Ethereum address from the public key
        // Ethereum address is the last 20 bytes of keccak256(pubkey)
        bytes32 hashPubkey = keccak256(pubkey);
        return address(uint160(uint256(hashPubkey)));
    }
}