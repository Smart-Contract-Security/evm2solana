// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Solang does not support block.chainid, ShortStrings, IERC5267, or MessageHashUtils.
// We inline the necessary functionality and replace block.chainid with a constant or configurable value.
// For Solana, chain ID is not natively available; we use a fixed chain ID (e.g., 1) or make it configurable.
// We also remove the IERC5267 interface dependency and implement the domain separator logic directly.

abstract contract EIP712 {
    // Type hash for EIP-712 domain separator
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // Cached domain separator and related values
    bytes32 private immutable _cachedDomainSeparator;
    uint256 private immutable _cachedChainId;
    address private immutable _cachedThis;

    // Hashed name and version
    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    // Name and version strings (stored as bytes for simplicity, since ShortStrings is unavailable)
    string private _name;
    string private _version;

    // Solana does not have block.chainid; we use a constant chain ID (e.g., 1) for domain separator.
    // If needed, this can be made configurable via constructor parameter.
    uint256 private constant SOLANA_CHAIN_ID = 1;

    constructor(string memory name, string memory version) {
        _name = name;
        _version = version;
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = SOLANA_CHAIN_ID;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && SOLANA_CHAIN_ID == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, SOLANA_CHAIN_ID, address(this)));
    }

    // Inline MessageHashUtils.toTypedDataHash logic
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
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (
            hex"0f",
            _name,
            _version,
            SOLANA_CHAIN_ID,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    // These functions are kept for compatibility but now just return the stored strings.
    function _EIP712Name() internal view returns (string memory) {
        return _name;
    }

    function _EIP712Version() internal view returns (string memory) {
        return _version;
    }
}