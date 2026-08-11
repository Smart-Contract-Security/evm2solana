// SPDX-License-Identifier: MIT

/**
 * @dev Implementation of the ERC-20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPs/eip-2612[ERC-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC-20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on `{IERC20-approve}`, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
abstract contract ERC20PermitUpgradeable {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /**
     * @dev Permit deadline has expired.
     */
    // Revert with custom errors not supported on Solana. Using require instead.

    /**
     * @dev Mismatched signature.
     */

    // Nonces mapping
    mapping(address => uint256) private _nonces;

    // Domain separator cache
    bytes32 private _domainSeparator;
    string private _name;
    string private _version;

    // Initialization flag to replace Initializable and onlyInitializing
    bool private _initialized;

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC-20 token name.
     */
    function __ERC20Permit_init(string memory name) internal {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _name = name;
        _version = "1";
        // block.chainid is not available on Solana. Using a placeholder chain ID.
        // In a real deployment, this should be set to the appropriate chain identifier.
        uint64 chainId = 0;
        _domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            chainId,
            address(this)
        ));
    }

    function __ERC20Permit_init_unchained(string memory) internal {
        require(!_initialized, "Already initialized");
    }

    /**
     * @dev See {IERC20Permit-permit}.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(block.timestamp <= deadline, "ERC2612ExpiredSignature");

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        // Solana does not have ecrecover builtin. Use the imported signature verification.
        address signer = recoverSigner(hash, v, r, s);
        require(signer == owner, "ERC2612InvalidSigner");

        _approve(owner, spender, value);
    }

    /**
     * @dev Recovers the signer address from the signature.
     * On Solana, ecrecover is not available. This function should be implemented
     * using Solana's native signature verification syscalls or by calling the
     * secp256k1 program. For simplicity, this is a stub that must be replaced
     * with actual Solana-compatible signature verification.
     */
    function recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // Placeholder: In a real implementation, use Solana's secp256k1_recover syscall
        // or call the Secp256k1 program to recover the public key and derive the address.
        return address(0);
    }

    /**
     * @dev See {IERC20Permit-nonces}.
     */
    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Consumes a nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256) {
        uint256 current = _nonces[owner];
        _nonces[owner] = current + 1;
        return current;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view virtual returns (bytes32) {
        return _domainSeparator;
    }

    /**
     * @dev Hashes the typed data.
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    /**
     * @dev Approve function stub - must be implemented by the inheriting contract.
     */
    function _approve(address owner, address spender, uint256 value) internal virtual;
}