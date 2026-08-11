// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ConstantLib} from "./ConstantLib.sol";

library DepositDataLib {
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

    function computeTopUpDepositDataRoot(
        bytes memory _pubkey,
        uint256 _amount,
        bytes32 _wc
    ) internal view returns (bytes32 result) {
        bytes32 pubkeyRoot = computePubkeyRoot(_pubkey);
        bytes32 amountRoot = toLittleEndian64(uint64(_amount / 1 gwei));
        bytes32 zsr = ConstantLib.ZERO_SIGNATURE_ROOT;
        assembly ("memory-safe") {
            let buf := mload(0x40)
            mstore(buf, pubkeyRoot)
            mstore(add(buf, 0x20), _wc)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            let left := mload(buf)

            mstore(buf, amountRoot)
            mstore(add(buf, 0x20), zsr)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            let right := mload(buf)

            mstore(buf, left)
            mstore(add(buf, 0x20), right)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            result := mload(buf)
        }
    }

    function computeActivationDepositDataRoot(
        bytes memory _pubkey,
        uint256 _amount,
        bytes32 _wc,
        bytes memory _signature
    ) internal view returns (bytes32 result) {
        bytes32 pubkeyRoot = computePubkeyRoot(_pubkey);
        bytes32 signatureRoot = computeSignatureRoot(_signature);
        bytes32 amountRoot = toLittleEndian64(uint64(_amount / 1 gwei));
        assembly ("memory-safe") {
            let buf := mload(0x40)
            mstore(buf, pubkeyRoot)
            mstore(add(buf, 0x20), _wc)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            let left := mload(buf)

            mstore(buf, amountRoot)
            mstore(add(buf, 0x20), signatureRoot)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            let right := mload(buf)

            mstore(buf, left)
            mstore(add(buf, 0x20), right)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            result := mload(buf)
        }
    }

    function computePubkeyRoot(bytes memory _pubkey) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            let buf := mload(0x40)
            mstore(buf, mload(add(_pubkey, 0x20)))
            mstore(add(buf, 0x20), and(mload(add(_pubkey, 0x40)), UPPER_128_MASK))
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            result := mload(buf)
        }
    }

    function computeSignatureRoot(bytes memory _signature) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            let buf := mload(0x40)
            let sigData := add(_signature, 0x20)

            if iszero(staticcall(gas(), 0x02, sigData, 64, buf, 32)) { revert(0, 0) }
            let hash1 := mload(buf)

            mstore(buf, mload(add(sigData, 64)))
            mstore(add(buf, 0x20), 0)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            let hash2 := mload(buf)

            mstore(buf, hash1)
            mstore(add(buf, 0x20), hash2)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            result := mload(buf)
        }
    }

    function toLittleEndian64(uint64 _value) internal pure returns (bytes32) {
        _value = ((_value & 0xFF00FF00FF00FF00) >> 8) | ((_value & 0x00FF00FF00FF00FF) << 8);
        _value = ((_value & 0xFFFF0000FFFF0000) >> 16) | ((_value & 0x0000FFFF0000FFFF) << 16);
        _value = (_value >> 32) | (_value << 32);
        return bytes32(uint256(_value) << 192);
    }
}