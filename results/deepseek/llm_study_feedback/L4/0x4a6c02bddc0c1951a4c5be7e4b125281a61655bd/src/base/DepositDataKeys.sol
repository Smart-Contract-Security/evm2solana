// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

library ConstantLib {
    uint256 constant PUBLIC_KEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
}

library DepositDataKeys {
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

    function _entryOffset(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) private pure returns (uint256 offset) {
        offset = uint256(keccak256(abi.encodePacked(_position, _vaultIndex, _entryIndex)));
    }

    function saveEntry(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex,
        bytes memory _pubkey,
        bytes memory _signature
    ) internal {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);

        bytes32 pubkeyWord1 = bytes32(_pubkey[0:32]);
        bytes32 pubkeyWord2 = bytes32(_pubkey[32:48]);

        bytes32 sigWord1 = bytes32(_signature[0:32]);
        bytes32 sigWord2 = bytes32(_signature[32:64]);
        bytes32 sigWord3 = bytes32(_signature[64:96]);

        assembly {
            sstore(base, pubkeyWord1)
            sstore(add(base, 1), and(pubkeyWord2, UPPER_128_MASK))
            sstore(add(base, 2), sigWord1)
            sstore(add(base, 3), sigWord2)
            sstore(add(base, 4), sigWord3)
        }
    }

    function loadEntry(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) internal view returns (bytes memory pubkey, bytes memory signature) {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(ConstantLib.PUBLIC_KEY_LENGTH);
        signature = new bytes(ConstantLib.SIGNATURE_LENGTH);

        bytes32 loadedPubkeyWord1;
        bytes32 loadedPubkeyWord2;
        bytes32 loadedSigWord1;
        bytes32 loadedSigWord2;
        bytes32 loadedSigWord3;

        assembly {
            loadedPubkeyWord1 := sload(base)
            loadedPubkeyWord2 := sload(add(base, 1))
            loadedSigWord1 := sload(add(base, 2))
            loadedSigWord2 := sload(add(base, 3))
            loadedSigWord3 := sload(add(base, 4))
        }

        // Write pubkey: first 32 bytes
        for (uint256 i = 0; i < 32; i++) {
            pubkey[i] = loadedPubkeyWord1[i];
        }
        // Write pubkey: next 16 bytes from upper 128 bits of loadedPubkeyWord2
        bytes32 shifted = bytes32(uint256(loadedPubkeyWord2) >> 128);
        for (uint256 i = 0; i < 16; i++) {
            pubkey[32 + i] = shifted[i];
        }

        // Write signature: first 32 bytes
        for (uint256 i = 0; i < 32; i++) {
            signature[i] = loadedSigWord1[i];
        }
        // Write signature: next 32 bytes
        for (uint256 i = 0; i < 32; i++) {
            signature[32 + i] = loadedSigWord2[i];
        }
        // Write signature: last 32 bytes
        for (uint256 i = 0; i < 32; i++) {
            signature[64 + i] = loadedSigWord3[i];
        }
    }

    function loadPubkey(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) internal view returns (bytes memory pubkey) {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(ConstantLib.PUBLIC_KEY_LENGTH);

        bytes32 loadedPubkeyWord1;
        bytes32 loadedPubkeyWord2;

        assembly {
            loadedPubkeyWord1 := sload(base)
            loadedPubkeyWord2 := sload(add(base, 1))
        }

        // Write pubkey: first 32 bytes
        for (uint256 i = 0; i < 32; i++) {
            pubkey[i] = loadedPubkeyWord1[i];
        }
        // Write pubkey: next 16 bytes from upper 128 bits of loadedPubkeyWord2
        bytes32 shifted = bytes32(uint256(loadedPubkeyWord2) >> 128);
        for (uint256 i = 0; i < 16; i++) {
            pubkey[32 + i] = shifted[i];
        }
    }

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