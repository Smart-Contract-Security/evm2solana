// SPDX-License-Identifier: MIT

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Initializable} from "../../../proxy/utils/Initializable.sol";

abstract contract ERC20PermitUpgradeable is Initializable, IERC20Permit {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private _HASHED_NAME;
    bytes32 private _HASHED_VERSION;
    bytes32 private _CACHED_DOMAIN_SEPARATOR;
    uint64 private _CACHED_CHAIN_ID;
    address private _CACHED_THIS;

    mapping(address => uint256) private _nonces;

    function __ERC20Permit_init(string memory name) internal onlyInitializing {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes("1"));
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(hashedName, hashedVersion);
        _CACHED_CHAIN_ID = 0;
        _CACHED_THIS = address(this);
    }

    function __ERC20Permit_init_unchained(string memory) internal onlyInitializing {}

    function _useNonce(address owner) internal returns (uint256) {
        uint256 current = _nonces[owner];
        _nonces[owner] = current + 1;
        return current;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) {
            revert("ERC2612ExpiredSignature");
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = _recover(hash, v, r, s);
        if (signer != owner) {
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual override returns (uint256) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _CACHED_THIS && 0 == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _buildDomainSeparator(bytes32 nameHash, bytes32 versionHash) private view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, nameHash, versionHash, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert("ECDSAInvalidSignatureS");
        }
        if (v != 27 && v != 28) {
            revert("ECDSAInvalidSignatureV");
        }

        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));

        address signer = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff - 0x1b + v),
            r,
            s,
            message
        )))));

        return signer;
    }

    function _approve(address owner, address spender, uint256 value) internal virtual;
}