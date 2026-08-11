// SPDX-License-Identifier: MIT

// Solana port: Inline ShortString functionality since library not available
// Solana port: Inline IERC5267 interface since not available
// Solana port: Inline ECDSA since not available

interface IERC5267 {
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint64 chainId,
            address verifyingContract,
            bytes32 salt,
            uint64[] memory extensions
        );
}

abstract contract EIP712 is IERC5267 {
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint64 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    string private _name;
    string private _version;

    constructor(string memory name, string memory version) {
        _name = name;
        _version = version;
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        // Solana: block.chainid not available, use 0 or a constant
        _cachedChainId = 0;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && uint64(0) == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
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
            _name,
            _version,
            uint64(0),
            address(this),
            bytes32(0),
            new uint64[](0)
        );
    }
}