// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.6.0) (utils/cryptography/ECDSA.sol)

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
            bytes32 r = signature.read32(0);
            bytes32 s = signature.read32(32);
            uint8 v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint64(signature.length)));
        }
    }

    function tryRecoverCalldata(
        bytes32 hash,
        bytes calldata signature
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        if (signature.length == 65) {
            bytes32 r = signature.read32(0);
            bytes32 s = signature.read32(32);
            uint8 v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint64(signature.length)));
        }
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        _throwError(error, errorArg);
        return recovered;
    }

    function recoverCalldata(bytes32 hash, bytes calldata signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecoverCalldata(hash, signature);
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

        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        address signer = recover_ecdsa(message, v, r, s);
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

    function parse(bytes memory signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        if (signature.length == 65) {
            r = signature.read32(0);
            s = signature.read32(32);
            v = uint8(signature[64]);
        } else if (signature.length == 64) {
            r = signature.read32(0);
            bytes32 vs = signature.read32(32);
            s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            v = uint8((uint256(vs) >> 255) + 27);
        } else {
            r = bytes32(0);
            s = bytes32(0);
            v = 0;
        }
    }

    function parseCalldata(bytes calldata signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        if (signature.length == 65) {
            r = signature.read32(0);
            s = signature.read32(32);
            v = uint8(signature[64]);
        } else if (signature.length == 64) {
            r = signature.read32(0);
            bytes32 vs = signature.read32(32);
            s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            v = uint8((uint256(vs) >> 255) + 27);
        } else {
            r = bytes32(0);
            s = bytes32(0);
            v = 0;
        }
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

    function recover_ecdsa(bytes32 hash, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        bytes32[64] memory signature;
        signature[0] = r;
        signature[1] = s;
        signature[32] = bytes32(uint256(v));
        return recover_ecdsa(hash, signature);
    }
}