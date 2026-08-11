// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/ECDSA.sol)

import 'solana';

library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS
    }

    function tryRecover(
        bytes32 hash,
        bytes memory signature
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // Manual extraction without mload
            for (uint64 i = 0; i < 32; i++) {
                r |= bytes32(uint256(uint64(signature[i])) << (8 * (31 - i)));
            }
            for (uint64 j = 0; j < 32; j++) {
                s |= bytes32(uint256(uint64(signature[32 + j])) << (8 * (31 - j)));
            }
            v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint256(signature.length)));
        }
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        _throwError(error, errorArg);
        return recovered;
    }

    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint64(uint256(vs) >> 255)) + 27);
        return tryRecover(hash, v, r, s);
    }

    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, r, vs);
        _throwError(error, errorArg);
        return recovered;
    }

    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS, s);
        }

        // Solana does not have secp256k1_recover built-in.
        // We use the Solana syscall for secp256k1 signature verification.
        // The syscall expects the hash, signature, and public key in specific layouts.
        // We construct the input data and call the syscall.
        bytes memory sigData = new bytes(64);
        // Manual write without mstore
        for (uint64 i = 0; i < 32; i++) {
            sigData[i] = bytes1(uint8(uint256(r) >> (8 * (31 - i))));
        }
        for (uint64 j = 0; j < 32; j++) {
            sigData[32 + j] = bytes1(uint8(uint256(s) >> (8 * (31 - j))));
        }
        uint8 recoveryId = v - 27;

        // Prepare the input for the secp256k1_recover syscall
        // The syscall expects: hash (32 bytes), recovery_id (1 byte), signature (64 bytes)
        bytes memory input = new bytes(97);
        // Manual write without mstore
        for (uint64 k = 0; k < 32; k++) {
            input[k] = bytes1(uint8(uint256(hash) >> (8 * (31 - k))));
        }
        input[32] = bytes1(recoveryId);
        for (uint64 l = 0; l < 64; l++) {
            input[33 + l] = sigData[l];
        }

        // Call the Solana secp256k1_recover syscall
        // The syscall returns the public key (64 bytes) or an error code
        bytes memory publicKey = new bytes(64);
        uint64 result = secp256k1_recover(input, publicKey);

        if (result != 0) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }

        // Derive the address from the public key
        // Ethereum address is the last 20 bytes of keccak256(publicKey)
        bytes32 hashPubKey = keccak256(abi.encodePacked(publicKey));
        address signer = address(bytes20(hashPubKey));
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }

        return (signer, RecoverError.NoError, bytes32(0));
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
        _throwError(error, errorArg);
        return recovered;
    }

    function _throwError(RecoverError error, bytes32 errorArg) private pure {
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
}