// SPDX-License-Identifier: MIT

import {ERC20} from "../ERC20.sol";

abstract contract ERC20Permit is ERC20 {
    bytes32 private constant PERMIT_TYPEHASH = sha256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    mapping(address => uint64) private _nonces;

    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    constructor(string memory name) {
        bytes32 hashedName = sha256(bytes(name));
        bytes32 hashedVersion = sha256(bytes("1"));
        bytes32 typeHash = sha256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _TYPE_HASH = typeHash;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(typeHash, hashedName, hashedVersion);
    }

    function permit(
        address owner,
        address spender,
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) {
            revert("ERC2612ExpiredSignature");
        }

        bytes32 structHash = sha256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = recover(hash, v, r, s);
        if (signer != owner) {
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual returns (uint64) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _useNonce(address owner) internal returns (uint64) {
        uint64 current = _nonces[owner];
        _nonces[owner] = current + 1;
        return current;
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return _CACHED_DOMAIN_SEPARATOR;
    }

    function _buildDomainSeparator(bytes32 typeHash, bytes32 nameHash, bytes32 versionHash) private view returns (bytes32) {
        return sha256(abi.encode(typeHash, nameHash, versionHash, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return sha256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes memory signature = new bytes(65);
        for (uint64 i = 0; i < 32; i++) {
            signature[i] = r[i];
        }
        for (uint64 i = 0; i < 32; i++) {
            signature[32 + i] = s[i];
        }
        signature[64] = bytes1(v);
        bytes32 hashed = sha256(abi.encodePacked(hash, signature));
        bytes20 addrBytes = ripemd160(hashed);
        return address(uint160(uint256(keccak256(abi.encodePacked(addrBytes)))));
    }
}