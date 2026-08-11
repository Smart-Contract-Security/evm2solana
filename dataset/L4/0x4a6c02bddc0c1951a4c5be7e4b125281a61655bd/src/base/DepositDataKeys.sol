// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ConstantLib} from "./ConstantLib.sol";

/// @title DepositDataKeys - Assembly-optimized deposit data storage (Lido SigningKeys-style)
/// @notice Stores validator deposit data (pubkey + signature) in deterministic consecutive
///         storage slots via inline assembly, bypassing Solidity's dynamic bytes overhead.
///         Each entry occupies 5 consecutive slots:
///           slot+0: pubkey[0:32]
///           slot+1: pubkey[32:48] (upper 128 bits, lower 128 bits zeroed)
///           slot+2: signature[0:32]
///           slot+3: signature[32:64]
///           slot+4: signature[64:96]
///         depositDataRoot is NOT stored; it is recomputed at deposit time.
library DepositDataKeys {
    /// @dev Upper-128-bit mask used to isolate pubkey[32:48] from a 32-byte word.
    ///      Declared locally (not in ConstantLib) because it is only consumed from
    ///      within inline assembly, which cannot resolve dotted library constant paths.
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

    /// @dev Compute the deterministic base storage slot for an entry
    function _entryOffset(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) private pure returns (uint256 offset) {
        assembly {
            let buf := mload(0x40)
            mstore(buf, _position)
            mstore(add(buf, 0x20), _vaultIndex)
            mstore(add(buf, 0x40), _entryIndex)
            offset := keccak256(buf, 0x60)
        }
    }

    /// @notice Store a deposit data entry (pubkey + signature) into deterministic slots
    /// @param _position Base storage namespace
    /// @param _vaultIndex Vault index
    /// @param _entryIndex Entry index within the vault
    /// @param _pubkey 48-byte BLS public key (memory)
    /// @param _signature 96-byte BLS signature (memory)
    function saveEntry(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex,
        bytes memory _pubkey,
        bytes memory _signature
    ) internal {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        assembly {
            sstore(base, mload(add(_pubkey, 0x20)))
            sstore(
                add(base, 1),
                and(mload(add(_pubkey, 0x40)), UPPER_128_MASK)
            )

            let sig := add(_signature, 0x20)
            sstore(add(base, 2), mload(sig))
            sstore(add(base, 3), mload(add(sig, 0x20)))
            sstore(add(base, 4), mload(add(sig, 0x40)))
        }
    }

    /// @notice Load a full deposit data entry (pubkey + signature) from storage
    /// @return pubkey 48-byte BLS public key
    /// @return signature 96-byte BLS signature
    function loadEntry(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) internal view returns (bytes memory pubkey, bytes memory signature) {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(ConstantLib.PUBLIC_KEY_LENGTH);
        signature = new bytes(ConstantLib.SIGNATURE_LENGTH);
        assembly {
            // Lido trick: write slot+1 (shifted) at data+16, then slot+0 at data+0.
            // The second mstore overwrites the zero-pad left by the first at data[16:32].
            mstore(add(pubkey, 0x30), shr(128, sload(add(base, 1))))
            mstore(add(pubkey, 0x20), sload(base))

            let sig := add(signature, 0x20)
            mstore(sig, sload(add(base, 2)))
            mstore(add(sig, 0x20), sload(add(base, 3)))
            mstore(add(sig, 0x40), sload(add(base, 4)))
        }
    }

    /// @notice Load only the pubkey from a deposit data entry (used by removeDepositData)
    /// @return pubkey 48-byte BLS public key
    function loadPubkey(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) internal view returns (bytes memory pubkey) {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(ConstantLib.PUBLIC_KEY_LENGTH);
        assembly {
            mstore(add(pubkey, 0x30), shr(128, sload(add(base, 1))))
            mstore(add(pubkey, 0x20), sload(base))
        }
    }

    /// @notice Zero-out all 5 storage slots for a deposit data entry
    function clearEntry(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) internal {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        assembly {
            sstore(base, 0)
            sstore(add(base, 1), 0)
            sstore(add(base, 2), 0)
            sstore(add(base, 3), 0)
            sstore(add(base, 4), 0)
        }
    }
}
