// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

library DepositDataLib {
    bytes32 private constant UPPER_128_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;

    bytes32 private constant ZERO_SIGNATURE_ROOT =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    function computeTopUpDepositDataRoot(
        bytes memory _pubkey,
        uint256 _amount,
        bytes32 _wc
    ) internal view returns (bytes32 result) {
        bytes32 pubkeyRoot = computePubkeyRoot(_pubkey);
        bytes32 amountRoot = toLittleEndian64(uint64(_amount / 1 gwei));
        bytes32 zsr = ZERO_SIGNATURE_ROOT;

        bytes32 left = sha256(abi.encodePacked(pubkeyRoot, _wc));
        bytes32 right = sha256(abi.encodePacked(amountRoot, zsr));
        result = sha256(abi.encodePacked(left, right));
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

        bytes32 left = sha256(abi.encodePacked(pubkeyRoot, _wc));
        bytes32 right = sha256(abi.encodePacked(amountRoot, signatureRoot));
        result = sha256(abi.encodePacked(left, right));
    }

    function computePubkeyRoot(bytes memory _pubkey) internal view returns (bytes32 result) {
        bytes32 part1;
        bytes32 part2;
        assembly {
            part1 := mload(add(_pubkey, 0x20))
            part2 := and(mload(add(_pubkey, 0x40)), UPPER_128_MASK)
        }
        result = sha256(abi.encodePacked(part1, part2));
    }

    function computeSignatureRoot(bytes memory _signature) internal view returns (bytes32 result) {
        bytes32 hash1;
        bytes32 hash2;
        assembly {
            let sigData := add(_signature, 0x20)
            hash1 := mload(sigData)
            hash2 := mload(add(sigData, 64))
        }
        bytes32 left = sha256(abi.encodePacked(hash1, hash2));
        bytes32 right = sha256(abi.encodePacked(hash2, bytes32(0)));
        result = sha256(abi.encodePacked(left, right));
    }

    function toLittleEndian64(uint64 _value) internal pure returns (bytes32) {
        _value = ((_value & 0xFF00FF00FF00FF00) >> 8) | ((_value & 0x00FF00FF00FF00FF) << 8);
        _value = ((_value & 0xFFFF0000FFFF0000) >> 16) | ((_value & 0x0000FFFF0000FFFF) << 16);
        _value = (_value >> 32) | (_value << 32);
        return bytes32(uint256(_value) << 192);
    }
}