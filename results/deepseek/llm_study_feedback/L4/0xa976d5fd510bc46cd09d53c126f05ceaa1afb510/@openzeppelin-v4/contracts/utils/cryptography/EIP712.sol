// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

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

library ShortStrings {
    struct ShortString {
        bytes32 value;
    }

    function toShortStringWithFallback(string memory str, string storage fallbackStr) internal returns (ShortString memory) {
        bytes memory b = bytes(str);
        require(b.length <= 31, "String too long");
        bytes32 val;
        for (uint i = 0; i < b.length; i++) {
            val |= bytes32(uint256(uint8(b[i]))) >> (i * 8);
        }
        fallbackStr = str;
        return ShortString(val);
    }

    function toStringWithFallback(ShortString memory s, string storage fallbackStr) internal view returns (string memory) {
        return fallbackStr;
    }
}

library ECDSA {
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

abstract contract EIP712 is IERC5267 {
    using ShortStrings for *;

    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private _cachedDomainSeparator;
    uint256 private _cachedChainId;
    address private _cachedThis;

    bytes32 private _hashedName;
    bytes32 private _hashedVersion;

    ShortStrings.ShortString private _name;
    ShortStrings.ShortString private _version;
    string private _nameFallback;
    string private _versionFallback;

    function _chainId() internal view virtual returns (uint256) {
        return 1;
    }

    constructor(string memory name, string memory version) {
        _name = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = _chainId();
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && _chainId() == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, _chainId(), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function eip712Domain()
        public
        view
        virtual
        override
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
            _name.toStringWithFallback(_nameFallback),
            _version.toStringWithFallback(_versionFallback),
            _chainId(),
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }
}