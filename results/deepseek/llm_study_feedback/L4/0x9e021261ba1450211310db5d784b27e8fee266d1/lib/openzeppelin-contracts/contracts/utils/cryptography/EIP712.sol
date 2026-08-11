// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract EIP712 {
    struct ShortString {
        bytes32 value;
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private _cachedDomainSeparator;
    uint256 private _cachedChainId;
    address private _cachedThis;

    bytes32 private _hashedName;
    bytes32 private _hashedVersion;

    ShortString private _name;
    ShortString private _version;
    string private _nameFallback;
    string private _versionFallback;

    uint256 private constant CHAIN_ID = 1;

    function toShortStringWithFallback(string memory str, string storage fallbackStr) internal returns (ShortString memory) {
        bytes memory b = bytes(str);
        if (b.length < 32) {
            bytes32 value = bytes32(b);
            return ShortString(value);
        } else {
            fallbackStr = str;
            return ShortString(keccak256(b));
        }
    }

    function toStringWithFallback(ShortString memory value, string storage fallbackStr) internal view returns (string memory) {
        if (bytes(fallbackStr).length > 0) {
            return fallbackStr;
        } else {
            bytes32 val = value.value;
            bytes memory short = new bytes(32);
            for (uint256 i = 0; i < 32; i++) {
                short[i] = val[i];
            }
            uint256 len = 0;
            for (uint256 i = 0; i < 32; i++) {
                if (short[i] != 0) {
                    len++;
                } else {
                    break;
                }
            }
            bytes memory result = new bytes(len);
            for (uint256 i = 0; i < len; i++) {
                result[i] = short[i];
            }
            return string(result);
        }
    }

    constructor(string memory name, string memory version) {
        _name = toShortStringWithFallback(name, _nameFallback);
        _version = toShortStringWithFallback(version, _versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = CHAIN_ID;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && CHAIN_ID == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, CHAIN_ID, address(this)));
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
            CHAIN_ID,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    function _EIP712Name() internal view returns (string memory) {
        return toStringWithFallback(_name, _nameFallback);
    }

    function _EIP712Version() internal view returns (string memory) {
        return toStringWithFallback(_version, _versionFallback);
    }
}