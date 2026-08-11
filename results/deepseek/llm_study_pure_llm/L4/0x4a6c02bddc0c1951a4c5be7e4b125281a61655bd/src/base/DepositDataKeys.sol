// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ConstantLib} from "./ConstantLib.sol";

library DepositDataKeys {
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

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

    function loadEntry(
        bytes32 _position,
        uint256 _vaultIndex,
        uint256 _entryIndex
    ) internal view returns (bytes memory pubkey, bytes memory signature) {
        uint256 base = _entryOffset(_position, _vaultIndex, _entryIndex);
        pubkey = new bytes(ConstantLib.PUBLIC_KEY_LENGTH);
        signature = new bytes(ConstantLib.SIGNATURE_LENGTH);
        assembly {
            mstore(add(pubkey, 0x30), shr(128, sload(add(base, 1))))
            mstore(add(pubkey, 0x20), sload(base))

            let sig := add(signature, 0x20)
            mstore(sig, sload(add(base, 2)))
            mstore(add(sig, 0x20), sload(add(base, 3)))
            mstore(add(sig, 0x40), sload(add(base, 4)))
        }
    }

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