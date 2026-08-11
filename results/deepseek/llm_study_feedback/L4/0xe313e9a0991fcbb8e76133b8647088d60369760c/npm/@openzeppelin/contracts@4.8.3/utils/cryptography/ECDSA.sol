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
            // Extract r, s, v from signature bytes without assembly
            bytes memory rBytes = new bytes(32);
            bytes memory sBytes = new bytes(32);
            for (uint i = 0; i < 32; i++) {
                rBytes[i] = signature[i];
            }
            for (uint i = 0; i < 32; i++) {
                sBytes[i] = signature[32 + i];
            }
            r = bytes32(rBytes);
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

    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    function recover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address, RecoverError) {
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }

        // Solana does not support ecrecover natively.
        // We use the Solana secp256k1 recover syscall via a helper.
        address signer = _ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature);
        }

        return (signer, RecoverError.NoError);
    }

    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(s.length), s));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // Helper to perform secp256k1 recovery using Solana's crypto syscall
    function _ecrecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        // Adjust v to recovery id (0 or 1)
        uint8 recoveryId = v - 27;
        if (recoveryId > 1) {
            return address(0);
        }

        // Prepare input: 64 bytes of signature (r, s) + 1 byte recovery id + 32 bytes message hash
        bytes memory input = new bytes(97);
        // Copy r (32 bytes)
        for (uint i = 0; i < 32; i++) {
            input[i] = r[i];
        }
        // Copy s (32 bytes)
        for (uint i = 0; i < 32; i++) {
            input[32 + i] = s[i];
        }
        // Recovery id
        input[64] = bytes1(recoveryId);
        // Copy hash (32 bytes)
        for (uint i = 0; i < 32; i++) {
            input[65 + i] = hash[i];
        }

        // Call Solana secp256k1 recover syscall
        bytes memory output = new bytes(64);
        uint256 result = _solana_secp256k1_recover(input, output);
        if (result != 0) {
            return address(0);
        }

        // The recovered public key is 64 bytes uncompressed (x, y)
        // Derive Ethereum address: keccak256(x, y) last 20 bytes
        bytes32 pubKeyHash = keccak256(output);
        return address(uint160(uint256(pubKeyHash)));
    }

    // Placeholder for Solana secp256k1 recover syscall.
    // In a real deployment, this would be replaced with the actual syscall invocation.
    // For now, we return a non-zero result to indicate failure, as the syscall is not directly available.
    function _solana_secp256k1_recover(bytes memory input, bytes memory output) private pure returns (uint256) {
        // Solana's secp256k1 recover is not directly callable from Solidity without a host builtin.
        // This function serves as a stub. In practice, you would need to use a precompiled contract
        // or a custom syscall wrapper provided by the Solang runtime.
        // Returning 1 indicates failure.
        return 1;
    }
}