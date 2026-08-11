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
            bytes32 r = readBytes32(signature, 0);
            bytes32 s = readBytes32(signature, 32);
            uint8 v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint256(uint64(signature.length))));
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
        unchecked {
            bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            uint8 v = uint8((uint64(uint256(vs) >> 255)) + 27);
            return tryRecover(hash, v, r, s);
        }
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

        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (bool valid, address signer) = signatureVerify(message, r, s, v);
        if (!valid || signer == address(0)) {
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

    function readBytes32(bytes memory b, uint64 offset) private pure returns (bytes32 result) {
        for (uint64 i = 0; i < 32; i++) {
            result |= bytes32(uint256(uint8(b[offset + i])) << (8 * (31 - i)));
        }
    }

    function signatureVerify(
        bytes32 message,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure returns (bool, address) {
        bytes32 tx_hash = keccak256(abi.encodePacked(message));
        address recovered = address(0);
        bool success = false;

        if (v == 27 || v == 28) {
            uint8 recoveryId = v - 27;
            bytes memory sig = new bytes(65);
            for (uint64 i = 0; i < 32; i++) {
                sig[i] = bytes1(uint8(uint256(r) >> (8 * (31 - i))));
            }
            for (uint64 i = 0; i < 32; i++) {
                sig[32 + i] = bytes1(uint8(uint256(s) >> (8 * (31 - i))));
            }
            sig[64] = bytes1(recoveryId);

            (success, recovered) = recoverPublicKey(tx_hash, sig);
        }

        return (success, recovered);
    }

    function recoverPublicKey(bytes32 hash, bytes memory signature) internal pure returns (bool, address) {
        bytes32 r = readBytes32(signature, 0);
        bytes32 s = readBytes32(signature, 32);
        uint8 v = uint8(signature[64]);

        if (v < 27) {
            v += 27;
        }

        bytes memory pubkey = new bytes(33);
        pubkey[0] = bytes1(0x02 | (v & 0x01));

        bytes32 x = r;
        for (uint64 i = 0; i < 32; i++) {
            pubkey[i + 1] = bytes1(uint8(uint256(x) >> (8 * (31 - i))));
        }

        bytes20 hashResult = ripemd160(keccak256(pubkey));
        address recovered = address(bytes32(uint256(uint160(hashResult))));
        return (true, recovered);
    }
}