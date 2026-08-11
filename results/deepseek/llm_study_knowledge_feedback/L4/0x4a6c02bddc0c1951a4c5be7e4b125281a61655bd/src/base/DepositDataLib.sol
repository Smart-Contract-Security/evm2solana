// SPDX-License-Identifier: GPL-3.0

/// @title DepositDataLib - SSZ deposit data root computation utilities
/// @notice Pure functions for computing Beacon Chain deposit data Merkle roots
///         following the SSZ (Simple Serialize) specification.
///         Uses Solana-compatible sha256 syscall via `solana` import.
/// @dev On Solana, we cannot use inline assembly with mload/staticcall.
///      Instead we use the Solana `sha256` syscall from the `solana` builtin.
library DepositDataLib {
    /// @dev Upper-128-bit mask: keeps pubkey[32:48], zeroes padding bytes.
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

    /// @dev Zero signature root constant (moved from ConstantLib)
    bytes32 private constant ZERO_SIGNATURE_ROOT =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    /// @notice Compute the deposit data root for a topUp (zero-signature) deposit
    /// @dev root = sha256(sha256(pubkeyRoot || wc), sha256(amountRoot || ZERO_SIGNATURE_ROOT))
    function computeTopUpDepositDataRoot(
        bytes memory _pubkey,
        uint256 _amount,
        bytes32 _wc
    ) internal view returns (bytes32 result) {
        bytes32 pubkeyRoot = computePubkeyRoot(_pubkey);
        bytes32 amountRoot = toLittleEndian64(uint64(_amount / 1 gwei));
        bytes32 zsr = ZERO_SIGNATURE_ROOT;

        bytes memory leftInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            leftInput[i] = pubkeyRoot[i];
            leftInput[i + 32] = _wc[i];
        }
        bytes32 left = sha256(leftInput);

        bytes memory rightInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            rightInput[i] = amountRoot[i];
            rightInput[i + 32] = zsr[i];
        }
        bytes32 right = sha256(rightInput);

        bytes memory finalInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            finalInput[i] = left[i];
            finalInput[i + 32] = right[i];
        }
        result = sha256(finalInput);
    }

    /// @notice Compute the deposit data root for an activation deposit (with real BLS signature)
    /// @dev root = sha256(sha256(pubkeyRoot || wc), sha256(amountRoot || signatureRoot))
    function computeActivationDepositDataRoot(
        bytes memory _pubkey,
        uint256 _amount,
        bytes32 _wc,
        bytes memory _signature
    ) internal view returns (bytes32 result) {
        bytes32 pubkeyRoot = computePubkeyRoot(_pubkey);
        bytes32 signatureRoot = computeSignatureRoot(_signature);
        bytes32 amountRoot = toLittleEndian64(uint64(_amount / 1 gwei));

        bytes memory leftInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            leftInput[i] = pubkeyRoot[i];
            leftInput[i + 32] = _wc[i];
        }
        bytes32 left = sha256(leftInput);

        bytes memory rightInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            rightInput[i] = amountRoot[i];
            rightInput[i + 32] = signatureRoot[i];
        }
        bytes32 right = sha256(rightInput);

        bytes memory finalInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            finalInput[i] = left[i];
            finalInput[i + 32] = right[i];
        }
        result = sha256(finalInput);
    }

    /// @notice Compute the SSZ hash tree root of a 48-byte BLS public key
    /// @dev Pads pubkey to 64 bytes and calls sha256.
    function computePubkeyRoot(bytes memory _pubkey) internal view returns (bytes32 result) {
        bytes memory padded = new bytes(64);
        // Copy first 32 bytes
        for (uint i = 0; i < 32; i++) {
            padded[i] = _pubkey[i];
        }
        // Copy next 16 bytes, leaving last 16 as zeros
        for (uint i = 0; i < 16; i++) {
            padded[i + 32] = _pubkey[i + 32];
        }
        result = sha256(padded);
    }

    /// @notice Compute the SSZ hash tree root of a 96-byte BLS signature
    /// @dev SSZ merkleization: sha256(sha256(sig[0:64]) || sha256(sig[64:96] ++ zeros(32)))
    function computeSignatureRoot(bytes memory _signature) internal view returns (bytes32 result) {
        // sha256(sig[0:64])
        bytes memory firstChunk = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            firstChunk[i] = _signature[i];
        }
        bytes32 hash1 = sha256(firstChunk);

        // sha256(sig[64:96] ++ zeros(32))
        bytes memory secondChunk = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            secondChunk[i] = _signature[i + 64];
        }
        // last 32 bytes are already zero
        bytes32 hash2 = sha256(secondChunk);

        // sha256(hash1 || hash2)
        bytes memory finalInput = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            finalInput[i] = hash1[i];
            finalInput[i + 32] = hash2[i];
        }
        result = sha256(finalInput);
    }

    /// @notice Convert uint64 to little-endian encoded bytes32
    function toLittleEndian64(uint64 _value) internal pure returns (bytes32) {
        _value = ((_value & 0xFF00FF00FF00FF00) >> 8) | ((_value & 0x00FF00FF00FF00FF) << 8);
        _value = ((_value & 0xFFFF0000FFFF0000) >> 16) | ((_value & 0x0000FFFF0000FFFF) << 16);
        _value = (_value >> 32) | (_value << 32);
        return bytes32(uint256(_value) << 192);
    }
}