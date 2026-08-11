// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PermissionVault is ReentrancyGuard, Pausable, Ownable, EIP712 {
    using ECDSA for bytes32;

    struct Permission {
        address user;
        address beneficiary;
        uint256 maxPerInterval;
        uint256 intervalSeconds;
        uint256 validUntil;
        uint256 nonce;
    }

    struct SpendRecord {
        uint256 spent;
        uint256 windowStart;
    }

    bytes32 private constant PERMISSION_TYPEHASH = keccak256(
        "Permission(address user,address beneficiary,uint256 maxPerInterval,uint256 intervalSeconds,uint256 validUntil,uint256 nonce)"
    );

    mapping(address => uint256)     public balances;
    mapping(address => uint256)     public nonces;
    mapping(address => SpendRecord) public spendRecords;
    mapping(address => bool)        public operators;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event PermissionExecuted(address indexed user, address indexed beneficiary, uint256 amount);
    event PermissionRevoked(address indexed user);
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);

    error InsufficientBalance(uint256 available, uint256 requested);
    error PermissionExpired(uint256 validUntil);
    error InvalidNonce(uint256 expected, uint256 provided);
    error InvalidBeneficiary(address expected, address provided);
    error InvalidSignature();
    error IntervalLimitExceeded(uint256 remaining, uint256 requested);
    error NativeTransferFailed();
    error NotOperator();

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert NotOperator();
        _;
    }

    constructor(string memory name, string memory version)
        Ownable(msg.sender)
        EIP712(name, version)
    {}

    // ── User-facing ──────────────────────────────────────────────────────────

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function depositFor(address user) external payable {
        balances[user] += msg.value;
        emit Deposited(user, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (balances[msg.sender] < amount)
            revert InsufficientBalance(balances[msg.sender], amount);
        balances[msg.sender] -= amount;
        nonces[msg.sender]++;  // invalidate outstanding permissions
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    function revokePermissions() external {
        nonces[msg.sender]++;
        emit PermissionRevoked(msg.sender);
    }

    // ── Operator-facing ──────────────────────────────────────────────────────

    function executePermission(
        Permission calldata perm,
        bytes calldata sig,
        uint256 amount
    ) external onlyOperator nonReentrant whenNotPaused {
        if (block.timestamp > perm.validUntil)
            revert PermissionExpired(perm.validUntil);
        if (nonces[perm.user] != perm.nonce)
            revert InvalidNonce(nonces[perm.user], perm.nonce);
        if (perm.beneficiary != msg.sender && perm.beneficiary != address(0)) {
            // address(0) means any operator is allowed
            revert InvalidBeneficiary(perm.beneficiary, msg.sender);
        }

        // Verify EIP-712 signature
        bytes32 structHash = keccak256(abi.encode(
            PERMISSION_TYPEHASH,
            perm.user,
            perm.beneficiary,
            perm.maxPerInterval,
            perm.intervalSeconds,
            perm.validUntil,
            perm.nonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(sig);
        if (signer != perm.user) revert InvalidSignature();

        // Reset interval if elapsed
        SpendRecord storage record = spendRecords[perm.user];
        if (block.timestamp >= record.windowStart + perm.intervalSeconds) {
            record.spent = 0;
            record.windowStart = block.timestamp;
        }

        uint256 remaining = perm.maxPerInterval - record.spent;
        if (amount > remaining) revert IntervalLimitExceeded(remaining, amount);
        if (balances[perm.user] < amount)
            revert InsufficientBalance(balances[perm.user], amount);

        record.spent       += amount;
        balances[perm.user] -= amount;

        (bool ok,) = perm.beneficiary == address(0)
            ? msg.sender.call{value: amount}("")
            : perm.beneficiary.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();

        emit PermissionExecuted(perm.user, perm.beneficiary == address(0) ? msg.sender : perm.beneficiary, amount);
    }

    // ── Views ────────────────────────────────────────────────────────────────

    function verifyPermission(Permission calldata perm, bytes calldata sig)
        external view returns (bool valid, string memory reason)
    {
        if (block.timestamp > perm.validUntil)
            return (false, "Permission expired");
        if (nonces[perm.user] != perm.nonce)
            return (false, "Invalid nonce");

        bytes32 structHash = keccak256(abi.encode(
            PERMISSION_TYPEHASH,
            perm.user,
            perm.beneficiary,
            perm.maxPerInterval,
            perm.intervalSeconds,
            perm.validUntil,
            perm.nonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(sig);
        if (signer != perm.user)
            return (false, "Invalid signature");

        return (true, "");
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function remainingThisInterval(address user) external view returns (uint256) {
        // Without a permission object we can't know maxPerInterval — returns raw spent
        return spendRecords[user].spent;
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    function addOperator(address op) external onlyOwner {
        operators[op] = true;
        emit OperatorAdded(op);
    }

    function removeOperator(address op) external onlyOwner {
        operators[op] = false;
        emit OperatorRemoved(op);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
