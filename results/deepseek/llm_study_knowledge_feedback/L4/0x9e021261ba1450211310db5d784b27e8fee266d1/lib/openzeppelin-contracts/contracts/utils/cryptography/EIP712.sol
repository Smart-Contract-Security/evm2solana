// SPDX-License-Identifier: MIT

abstract contract EIP712 {
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint64 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    bytes32 private immutable _name;
    bytes32 private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    function _toShortStringWithFallback(string memory str, string storage fallbackStr) private returns (bytes32) {
        bytes memory b = bytes(str);
        if (b.length < 32) {
            bytes32 result = bytes32(0);
            for (uint256 i = 0; i < b.length; i++) {
                result |= bytes32(uint256(uint8(b[i]))) >> (i * 8);
            }
            uint256 len = b.length;
            result = result | bytes32((len << 1) & 0xFF);
            return result;
        } else {
            fallbackStr = str;
            return bytes32(uint256(0));
        }
    }

    function _toStringWithFallback(bytes32 value, string storage fallbackStr) internal view returns (string memory) {
        uint256 len = uint256(value) & 0xFF;
        len = len >> 1;
        if (len != 0) {
            bytes memory result = new bytes(len);
            bytes32 val = value & bytes32(~uint256(0xFF));
            for (uint256 i = 0; i < len; i++) {
                result[i] = bytes1(uint8(uint256(val) >> (i * 8)));
            }
            return string(result);
        } else {
            return fallbackStr;
        }
    }

    function _toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    constructor(string memory name, string memory version) {
        _name = _toShortStringWithFallback(name, _nameFallback);
        _version = _toShortStringWithFallback(version, _versionFallback);
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
        return _toStringWithFallback(_name, _nameFallback);
    }

    function _EIP712Version() internal view returns (string memory) {
        return _toStringWithFallback(_version, _versionFallback);
    }
}