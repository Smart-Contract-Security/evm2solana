// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ConstantLib} from "./ConstantLib.sol";

/// @title DepositDataLib - SSZ deposit data root computation utilities
/// @notice Pure functions for computing Beacon Chain deposit data Merkle roots
///         following the SSZ (Simple Serialize) specification.
///         Uses inline assembly for memory-efficient sha256 precompile calls,
///         eliminating repeated `new bytes()` allocations and byte-by-byte copy loops.
/// @dev Memory-safety model (applies to every `assembly ("memory-safe")` block below):
///      - Each function only writes to the 64-byte scratch region starting at
///        `mload(0x40)` and reads the result back from the same region.
///      - The free memory pointer at `0x40` is INTENTIONALLY NOT advanced: the
///        scratch data is ephemeral and no longer needed once `result` has been
///        returned, so it is safe for Solidity to overwrite this region on
///        subsequent allocations.
///      - This pattern is explicitly permitted by the Solidity memory-safe
///        assembly specification (scratch use below the free memory pointer),
///        and enables better memory reuse / optimization under via-IR.
library DepositDataLib {
    /// @dev Upper-128-bit mask: keeps pubkey[32:48], zeroes padding bytes.
    ///      Declared locally (not in ConstantLib) because it is only consumed
    ///      from within inline assembly, which cannot resolve dotted library
    ///      constant paths.
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

    /// @notice Compute the deposit data root for a topUp (zero-signature) deposit
    /// @dev root = sha256(sha256(pubkeyRoot || wc), sha256(amountRoot || ZERO_SIGNATURE_ROOT))
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

    /// @notice Compute the SSZ hash tree root of a 48-byte BLS public key
    /// @dev Pads pubkey to 64 bytes via assembly and calls sha256 precompile
    ///      without allocating new memory.
    function computePubkeyRoot(bytes memory _pubkey) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            let buf := mload(0x40)
            mstore(buf, mload(add(_pubkey, 0x20)))
            mstore(add(buf, 0x20), and(mload(add(_pubkey, 0x40)), UPPER_128_MASK))
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            result := mload(buf)
        }
    }

    /// @notice Compute the SSZ hash tree root of a 96-byte BLS signature
    /// @dev SSZ merkleization: sha256(sha256(sig[0:64]) || sha256(sig[64:96] ++ zeros(32)))
    ///      Reads signature data directly from memory, reuses a single scratch buffer.
    function computeSignatureRoot(bytes memory _signature) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            let buf := mload(0x40)
            let sigData := add(_signature, 0x20)

            // sha256(sig[0:64]) — input read directly from _signature memory
            if iszero(staticcall(gas(), 0x02, sigData, 64, buf, 32)) { revert(0, 0) }
            let hash1 := mload(buf)

            // sha256(sig[64:96] ++ zeros(32))
            mstore(buf, mload(add(sigData, 64)))
            mstore(add(buf, 0x20), 0)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            let hash2 := mload(buf)

            // sha256(hash1 || hash2)
            mstore(buf, hash1)
            mstore(add(buf, 0x20), hash2)
            if iszero(staticcall(gas(), 0x02, buf, 64, buf, 32)) { revert(0, 0) }
            result := mload(buf)
        }
    }

    /// @notice Convert uint64 to little-endian encoded bytes32
    function toLittleEndian64(uint64 _value) internal pure returns (bytes32) {
        _value = ((_value & 0xFF00FF00FF00FF00) >> 8) | ((_value & 0x00FF00FF00FF00FF) << 8);
        _value = ((_value & 0xFFFF0000FFFF0000) >> 16) | ((_value & 0x0000FFFF0000FFFF) << 16);
        _value = (_value >> 32) | (_value << 32);
        return bytes32(uint256(_value) << 192);
    }
}
