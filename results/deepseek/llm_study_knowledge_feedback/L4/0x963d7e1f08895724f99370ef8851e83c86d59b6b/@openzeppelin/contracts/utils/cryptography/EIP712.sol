// SPDX-License-Identifier: MIT

// Solana port: ShortStrings and IERC5267 are not available.
// We inline the necessary functionality directly.

abstract contract EIP712 {
    // ShortString is represented as a bytes32 with length encoded in the last byte.
    // Fallback strings are stored separately.

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint64 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    bytes32 private immutable _nameShort;
    bytes32 private immutable _versionShort;
    string private _nameFallback;
    string private _versionFallback;

    constructor(string memory name, string memory version) {
        (_nameShort, _nameFallback) = _toShortStringWithFallback(name);
        (_versionShort, _versionFallback) = _toShortStringWithFallback(version);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = 0;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && 0 == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return _toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function _toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function eip712Domain()
        public
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint64 chainId,
            address verifyingContract,
            bytes32 salt,
            uint64[] memory extensions
        )
    {
        return (
            hex"0f",
            _EIP712Name(),
            _EIP712Version(),
            uint64(0),
            address(this),
            bytes32(0),
            new uint64[](0)
        );
    }

    function _EIP712Name() internal view returns (string memory) {
        return _toStringWithFallback(_nameShort, _nameFallback);
    }

    function _EIP712Version() internal view returns (string memory) {
        return _toStringWithFallback(_versionShort, _versionFallback);
    }

    // --- Inlined ShortStrings logic ---

    function _toShortStringWithFallback(string memory value) private pure returns (bytes32 shortStr, string memory fallbackStr) {
        bytes memory b = bytes(value);
        if (b.length < 32) {
            // Store in bytes32 with length in last byte
            bytes32 result;
            // Manually copy bytes into bytes32 without assembly mload
            for (uint256 i = 0; i < b.length; i++) {
                result |= bytes32(uint256(uint8(b[i]))) >> (i * 8);
            }
            // Mask to clear the last byte, then set length
            result = result & bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00);
            result = result | bytes32(uint256(b.length * 2) & 0xFF);
            return (result, "");
        } else {
            return (keccak256(b) | bytes32(uint256(b.length * 2 + 1) & 0xFF), value);
        }
    }

    function _toStringWithFallback(bytes32 shortStr, string memory fallbackStr) private pure returns (string memory) {
        uint256 len = uint256(uint8(shortStr[31]));
        if (len & 1 == 0) {
            // Short string
            len = len / 2;
            bytes memory result = new bytes(len);
            bytes32 val = shortStr & bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00);
            // Manually copy bytes32 into bytes without assembly mstore
            for (uint256 i = 0; i < len; i++) {
                result[i] = bytes1(uint8(uint256(val >> (i * 8)) & 0xFF));
            }
            return string(result);
        } else {
            return fallbackStr;
        }
    }
}