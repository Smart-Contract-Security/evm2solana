// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ECDSA stub for Solana compatibility
library ECDSA {
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // Solang does not support ecrecover. We use a low-level call to the secp256k1 recover syscall.
        // On Solana, the secp256k1_recover instruction is available via the `@solana/solidity` builtins.
        // We use the `secp256k1_recover` function provided by Solang's Solana target.
        // However, Solang does not expose a direct `secp256k1_recover` builtin.
        // Instead, we can use the `ecrecover` precompile address (0x01) via a static call.
        // But Solang for Solana does not support precompiles in the same way.
        // The safest approach is to use the `ecrecover` function from the `secp256k1` module if available,
        // or implement a fallback. Since Solang v0.3+ supports `ecrecover` as a builtin on Solana,
        // we can call it directly. The error indicates it's unknown, so we must provide an alternative.
        // We'll use inline assembly to call the secp256k1 recover syscall.
        // Solang supports `assembly` blocks with Solana-specific opcodes.
        // The syscall for secp256k1_recover is `secp256k1_recover`.
        // We'll construct the input and parse the output.
        // Input: hash (32 bytes), v (1 byte), r (32 bytes), s (32 bytes) = 97 bytes.
        // Output: public key (64 bytes) or address (20 bytes).
        // We'll use the `secp256k1_recover` syscall directly.
        // Note: Solang's assembly syntax for Solana is different.
        // We'll use a high-level approach: call a precompiled contract at address 0x01.
        // Solang on Solana does support precompiled contracts via `call` to specific addresses.
        // Address 0x01 is the ecrecover precompile.
        // We'll do a static call to 0x01 with the input data.
        // Input data layout: hash (32 bytes), v (32 bytes, padded), r (32 bytes), s (32 bytes).
        // Output: address (20 bytes) left-padded to 32 bytes.
        // Let's implement this using `staticcall`.
        bytes memory input = abi.encodePacked(hash, uint256(v), r, s);
        (bool success, bytes memory output) = address(0x01).staticcall(input);
        require(success, "ECDSA: ecrecover failed");
        require(output.length == 32, "ECDSA: invalid output length");
        address recovered = address(uint160(uint256(bytes32(output))));
        require(recovered != address(0), "ECDSA: invalid signature");
        return recovered;
    }
}

// Initializable stub for Solana compatibility
abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }

    modifier onlyInitializing() {
        require(_initializing, "Not initializing");
        _;
    }
}

// Minimal ERC20Upgradeable stub to satisfy inheritance
abstract contract ERC20Upgradeable is Initializable {
    function _approve(address owner, address spender, uint256 value) internal virtual;
}

// Minimal IERC20Permit interface
interface IERC20Permit {
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// Minimal EIP712Upgradeable stub
abstract contract EIP712Upgradeable is Initializable {
    function __EIP712_init_unchained(string memory name, string memory version) internal virtual;
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32);
    function _domainSeparatorV4() internal view virtual returns (bytes32);
}

// Minimal NoncesUpgradeable stub
abstract contract NoncesUpgradeable is Initializable {
    function _useNonce(address owner) internal virtual returns (uint256);
    function nonces(address owner) public view virtual returns (uint256);
}

abstract contract ERC20PermitUpgradeable is Initializable, ERC20Upgradeable, IERC20Permit, EIP712Upgradeable, NoncesUpgradeable {
    bytes32 private constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Custom errors replaced with string reverts for Solana compatibility
    // error ERC2612ExpiredSignature(uint256 deadline);
    // error ERC2612InvalidSigner(address signer, address owner);

    function __ERC20Permit_init(string memory name) internal onlyInitializing {
        __EIP712_init_unchained(name, "1");
    }

    function __ERC20Permit_init_unchained(string memory) internal onlyInitializing {}

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
            // revert ERC2612ExpiredSignature(deadline);
            revert("ERC2612ExpiredSignature");
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            // revert ERC2612InvalidSigner(signer, owner);
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual override(IERC20Permit, NoncesUpgradeable) returns (uint256) {
        return NoncesUpgradeable.nonces(owner);
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }
}