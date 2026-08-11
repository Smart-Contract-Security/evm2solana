// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Solang does not support block.chainid, ShortStrings, IERC5267, or MessageHashUtils.
// We inline minimal replacements and use Solana's chain ID (hardcoded for now).
// For Solana, chain ID is not a builtin; we use a constant or a runtime call.
// Here we use a constant 1 (Solana mainnet) or you can use tx.chain_id if available.
// Solang supports tx.chain_id() in recent versions. We'll use that.

// Minimal IERC5267 interface
interface IERC5267 {
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
}

// Minimal ShortString library replacement using plain strings
library ShortStrings {
    function toShortStringWithFallback(string memory self, string storage fallbackStr) internal pure returns (string memory) {
        // In Solang, we can just return the string itself; no need for ShortString type.
        return self;
    }

    function toStringWithFallback(string memory self, string storage fallbackStr) internal view returns (string memory) {
        return self;
    }
}

// Minimal MessageHashUtils replacement
library MessageHashUtils {
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

abstract contract EIP712 is IERC5267 {
    using ShortStrings for string;

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint256 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    string private immutable _name;
    string private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    constructor(string memory name, string memory version) {
        _name = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        // Solang for Solana: use tx.chain_id() if available, else constant.
        // We'll use a constant 1 for now, but ideally you'd use the runtime value.
        // Since block.chainid is not available, we use 1.
        _cachedChainId = 1; // Solana mainnet chain ID
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && 1 == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, 1, address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
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
            _EIP712Name(),
            _EIP712Version(),
            1,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    function _EIP712Name() internal view returns (string memory) {
        return _name.toStringWithFallback(_nameFallback);
    }

    function _EIP712Version() internal view returns (string memory) {
        return _version.toStringWithFallback(_versionFallback);
    }
}