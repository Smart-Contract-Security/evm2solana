// SPDX-License-Identifier: MIT

// Solana port: Inline ShortStrings, IERC5267, MessageHashUtils functionality
// Remove block.chainid (not available on Solana), use slot or fixed chain id

abstract contract EIP712 {
    // ShortString inline implementation
    struct ShortString {
        bytes32 value;
    }

    // IERC5267 inline
    event EIP712DomainChanged();

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint64 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    ShortString private immutable _name;
    ShortString private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    // ShortStrings helper: convert string to ShortString with fallback
    function toShortStringWithFallback(string memory str, string storage fallbackStr) internal returns (ShortString memory) {
        bytes memory b = bytes(str);
        if (b.length < 32) {
            bytes32 value;
            for (uint256 i = 0; i < b.length; i++) {
                value |= bytes32(uint256(uint8(b[i]))) >> (i * 8);
            }
            return ShortString(value);
        } else {
            fallbackStr = str;
            return ShortString(keccak256(b));
        }
    }

    // ShortStrings helper: convert ShortString back to string
    function toStringWithFallback(ShortString memory sstr, string storage fallbackStr) internal view returns (string memory) {
        bytes32 value = sstr.value;
        if (value & 0x8000000000000000000000000000000000000000000000000000000000000000 != 0) {
            return fallbackStr;
        } else {
            bytes memory b = new bytes(32);
            for (uint256 i = 0; i < 32; i++) {
                b[i] = bytes1(uint8(uint256(value) >> (i * 8)));
            }
            // Find actual length by trimming trailing zeros
            uint256 len = 32;
            while (len > 0 && b[len - 1] == 0) {
                len--;
            }
            bytes memory result = new bytes(len);
            for (uint256 i = 0; i < len; i++) {
                result[i] = b[i];
            }
            return string(result);
        }
    }

    // MessageHashUtils inline
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    constructor(string memory name, string memory version) {
        ShortString memory nameSS = toShortStringWithFallback(name, _nameFallback);
        ShortString memory versionSS = toShortStringWithFallback(version, _versionFallback);
        _name = nameSS;
        _version = versionSS;
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        // Solana: use fixed chain id 0 or derive from slot; here we use 0 as placeholder
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
        return toTypedDataHash(_domainSeparatorV4(), structHash);
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
            0,
            address(this),
            bytes32(0),
            new uint64[](0)
        );
    }

    function _EIP712Name() internal view returns (string memory) {
        return toStringWithFallback(_name, _nameFallback);
    }

    function _EIP712Version() internal view returns (string memory) {
        return toStringWithFallback(_version, _versionFallback);
    }
}