// SPDX-License-Identifier: MIT

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Initializable} from "../../../proxy/utils/Initializable.sol";

abstract contract ERC20PermitUpgradeable is Initializable {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) private _nonces;

    bytes32 private _domainSeparator;

    function __ERC20Permit_init(string memory name) internal onlyInitializing {
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                uint256(0),
                address(this)
            )
        );
    }

    function __ERC20Permit_init_unchained(string memory) internal onlyInitializing {}

    function _useNonce(address owner) internal returns (uint256 current) {
        current = _nonces[owner];
        _nonces[owner] = current + 1;
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));
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

        address signer = recoverSigner(hash, v, r, s);
        if (signer != owner) {
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes memory signature = new bytes(65);
        bytes32 r_temp = r;
        bytes32 s_temp = s;
        uint8 v_temp = v;
        for (uint i = 0; i < 32; i++) {
            signature[i] = bytes1(uint8(r_temp & 0xff));
            r_temp = r_temp >> 8;
        }
        for (uint i = 0; i < 32; i++) {
            signature[32 + i] = bytes1(uint8(s_temp & 0xff));
            s_temp = s_temp >> 8;
        }
        signature[64] = bytes1(v_temp);
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        return address(uint160(uint256(keccak256(abi.encodePacked(message, signature)))));
    }

    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparator;
    }

    function _approve(address owner, address spender, uint256 value) internal virtual;
}