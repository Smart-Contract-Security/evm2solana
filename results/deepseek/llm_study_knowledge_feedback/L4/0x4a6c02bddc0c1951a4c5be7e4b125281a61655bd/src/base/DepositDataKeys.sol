// SPDX-License-Identifier: GPL-3.0

/// @title DepositDataKeys - Solana-adapted deposit data storage
/// @notice Stores validator deposit data (pubkey + signature) in deterministic consecutive
///         account data bytes, replacing EVM storage slots with Solana account data.
///         Each entry occupies 5 * 32 = 160 bytes:
///           offset+0:   pubkey[0:32]
///           offset+32:  pubkey[32:48] (upper 128 bits, lower 128 bits zeroed)
///           offset+64:  signature[0:32]
///           offset+96:  signature[32:64]
///           offset+128: signature[64:96]
///         depositDataRoot is NOT stored; it is recomputed at deposit time.
library DepositDataKeys {
    uint64 private constant PUBLIC_KEY_LENGTH = 48;
    uint64 private constant SIGNATURE_LENGTH = 96;
    uint64 private constant ENTRY_SIZE = 160; // 5 * 32 bytes

    /// @dev Compute the deterministic base offset for an entry within account data
    function _entryOffset(
        bytes32 _position,
        uint64 _vaultIndex,
        uint64 _entryIndex
    ) private pure returns (uint64 offset) {
        // Use keccak256 to derive a deterministic offset, then scale to entry size
        bytes memory buf = new bytes(96);
        // Manually pack _position, _vaultIndex, _entryIndex into buf
        for (uint64 i = 0; i < 32; i++) {
            buf[i] = _position[i];
        }
        for (uint64 j = 0; j < 8; j++) {
            buf[32 + j] = bytes1(uint8((_vaultIndex >> (8 * (7 - j))) & 0xFF));
        }
        for (uint64 k = 0; k < 8; k++) {
            buf[40 + k] = bytes1(uint8((_entryIndex >> (8 * (7 - k))) & 0xFF));
        }
        bytes32 hash = keccak256(buf);
        // Use uint64 modulus to avoid overflow; 1 << 48 is 281474976710656 which fits in uint64
        offset = (uint64(uint256(hash) % 281474976710656)) * ENTRY_SIZE;
    }

    /// @notice Store a deposit data entry (pubkey + signature) into account data
    /// @param _dataAccount The account data to write into
    /// @param _position Base storage namespace
    /// @param _vaultIndex Vault index
    /// @param _entryIndex Entry index within the vault
    /// @param _pubkey 48-byte BLS public key (memory)
    /// @param _signature 96-byte BLS signature (memory)
    function saveEntry(
        bytes memory _dataAccount,
        bytes32 _position,
        uint64 _vaultIndex,
        uint64 _entryIndex,
        bytes memory _pubkey,
        bytes memory _signature
    ) internal pure {
        uint64 base = _entryOffset(_position, _vaultIndex, _entryIndex);

        // Write pubkey[0:32]
        for (uint64 i = 0; i < 32; i++) {
            _dataAccount[base + i] = _pubkey[i];
        }

        // Write pubkey[32:48] with upper 128-bit mask
        for (uint64 j = 0; j < 16; j++) {
            _dataAccount[base + 32 + j] = _pubkey[32 + j];
        }
        for (uint64 k = 16; k < 32; k++) {
            _dataAccount[base + 32 + k] = 0;
        }

        // Write signature[0:96]
        for (uint64 s = 0; s < 96; s++) {
            _dataAccount[base + 64 + s] = _signature[s];
        }
    }

    /// @notice Load a full deposit data entry (pubkey + signature) from account data
    /// @return pubkey 48-byte BLS public key
    /// @return signature 96-byte BLS signature
    function loadEntry(
        bytes memory _dataAccount,
        bytes32 _position,
        uint64 _vaultIndex,
        uint64 _entryIndex
    ) internal pure returns (bytes memory pubkey, bytes memory signature) {
        uint64 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(PUBLIC_KEY_LENGTH);
        signature = new bytes(SIGNATURE_LENGTH);

        // Read pubkey[0:48]
        for (uint64 i = 0; i < 48; i++) {
            pubkey[i] = _dataAccount[base + i];
        }

        // Read signature[0:96]
        for (uint64 j = 0; j < 96; j++) {
            signature[j] = _dataAccount[base + 64 + j];
        }
    }

    /// @notice Load only the pubkey from a deposit data entry
    /// @return pubkey 48-byte BLS public key
    function loadPubkey(
        bytes memory _dataAccount,
        bytes32 _position,
        uint64 _vaultIndex,
        uint64 _entryIndex
    ) internal pure returns (bytes memory pubkey) {
        uint64 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(PUBLIC_KEY_LENGTH);

        for (uint64 i = 0; i < 48; i++) {
            pubkey[i] = _dataAccount[base + i];
        }
    }

    /// @notice Zero-out all 160 bytes for a deposit data entry
    function clearEntry(
        bytes memory _dataAccount,
        bytes32 _position,
        uint64 _vaultIndex,
        uint64 _entryIndex
    ) internal pure {
        uint64 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        for (uint64 i = 0; i < ENTRY_SIZE; i++) {
            _dataAccount[base + i] = 0;
        }
    }
}