// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
            bytes32 r = readBytes32(signature, 0);
            bytes32 s = readBytes32(signature, 32);
            uint8 v = uint8(signature[64]);
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
        uint8 v = uint8((uint256(vs) >> 255) + 27);
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

        // Solang does not support ecrecover precompile on Solana.
        // We provide a stub that always returns address(0) and InvalidSignature.
        // A proper Solana implementation would use the secp256k1 program.
        address signer = address(0);
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

    function readBytes32(bytes memory b, uint256 offset) private pure returns (bytes32 result) {
        require(b.length >= offset + 32, "ECDSA: out of bounds");
        // Solang does not support inline assembly with mload.
        // Manually extract bytes32 from memory array.
        result = bytes32(
            (uint256(uint8(b[offset])) << 248) |
            (uint256(uint8(b[offset + 1])) << 240) |
            (uint256(uint8(b[offset + 2])) << 232) |
            (uint256(uint8(b[offset + 3])) << 224) |
            (uint256(uint8(b[offset + 4])) << 216) |
            (uint256(uint8(b[offset + 5])) << 208) |
            (uint256(uint8(b[offset + 6])) << 200) |
            (uint256(uint8(b[offset + 7])) << 192) |
            (uint256(uint8(b[offset + 8])) << 184) |
            (uint256(uint8(b[offset + 9])) << 176) |
            (uint256(uint8(b[offset + 10])) << 168) |
            (uint256(uint8(b[offset + 11])) << 160) |
            (uint256(uint8(b[offset + 12])) << 152) |
            (uint256(uint8(b[offset + 13])) << 144) |
            (uint256(uint8(b[offset + 14])) << 136) |
            (uint256(uint8(b[offset + 15])) << 128) |
            (uint256(uint8(b[offset + 16])) << 120) |
            (uint256(uint8(b[offset + 17])) << 112) |
            (uint256(uint8(b[offset + 18])) << 104) |
            (uint256(uint8(b[offset + 19])) << 96) |
            (uint256(uint8(b[offset + 20])) << 88) |
            (uint256(uint8(b[offset + 21])) << 80) |
            (uint256(uint8(b[offset + 22])) << 72) |
            (uint256(uint8(b[offset + 23])) << 64) |
            (uint256(uint8(b[offset + 24])) << 56) |
            (uint256(uint8(b[offset + 25])) << 48) |
            (uint256(uint8(b[offset + 26])) << 40) |
            (uint256(uint8(b[offset + 27])) << 32) |
            (uint256(uint8(b[offset + 28])) << 24) |
            (uint256(uint8(b[offset + 29])) << 16) |
            (uint256(uint8(b[offset + 30])) << 8) |
            uint256(uint8(b[offset + 31]))
        );
    }
}