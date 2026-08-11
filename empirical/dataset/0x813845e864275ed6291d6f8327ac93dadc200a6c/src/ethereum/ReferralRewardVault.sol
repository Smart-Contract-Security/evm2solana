// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IReferralRewardVault} from "./interfaces/IReferralRewardVault.sol";

/**
 * @title ReferralRewardVault
 * @notice Ethereum Mainnet — cumulative Merkle drop for CLGO referral rewards.
 *
 * CLGO token (canonical, Ethereum Mainnet only):
 *   0xca67106449c18eb6b45d2a725ef9c199016c43dc
 *
 * Flow (weekly):
 *   1. Off-chain reward engine computes cumulative CLGO amounts from Base activity.
 *   2. Foundation Safe (DISTRIBUTOR_ROLE) calls setRoot(weekId, root).
 *   3. Users switch to Ethereum, call claim(cumulativeAmount, proof).
 *   4. Contract sends (cumulativeAmount - alreadyClaimed) CLGO to caller.
 *
 * Security:
 *   - Domain separation: Merkle leaf encodes chainId (1) + this contract address.
 *     Prevents cross-chain replay (e.g. Base BoostOracle proof used here).
 *   - Monotonic weekId: root cannot be rolled back.
 *   - Zero-root guard: prevents accidental empty-root posting.
 *   - Cumulative pattern: claim(amount) only sends the unclaimed delta.
 *   - Vault balance guard: explicit revert if CLGO balance is insufficient.
 *   - DISTRIBUTOR_ROLE should be a Safe multisig — not an EOA.
 */
contract ReferralRewardVault is AccessControl, ReentrancyGuard, IReferralRewardVault {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Merkle leaf domain separation typehash
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "JackCoReferralClaim(uint256 chainId,address vault,address recipient,uint256 cumulativeAmount)"
    );

    /// @notice Ethereum Mainnet canonical CLGO — 0xca67106449c18eb6b45d2a725ef9c199016c43dc
    IERC20 public immutable clgo;

    bytes32 public currentRoot;
    uint256 public currentWeekId;

    /// @notice Cumulative CLGO claimed by each address (never decreases)
    mapping(address => uint256) public claimed;

    constructor(address clgo_, address admin_) {
        if (clgo_ == address(0) || admin_ == address(0)) revert InvalidProof(); // ZeroAddress reuse
        clgo = IERC20(clgo_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    // ── Distributor writes ───────────────────────────────────────────────────

    /// @notice Post a new cumulative Merkle root. weekId must be currentWeekId + 1.
    function setRoot(uint256 weekId, bytes32 root) external onlyRole(DISTRIBUTOR_ROLE) {
        if (weekId != currentWeekId + 1) revert InvalidWeekId();
        if (root == bytes32(0)) revert ZeroRoot();
        currentRoot = root;
        currentWeekId = weekId;
        emit RootUpdated(weekId, root);
    }

    // ── User claim ───────────────────────────────────────────────────────────

    /// @notice Claim CLGO. cumulativeAmount is the total earned to date; sends the delta.
    function claim(uint256 cumulativeAmount, bytes32[] calldata proof) external nonReentrant {
        bytes32 leaf = _buildLeaf(msg.sender, cumulativeAmount);
        if (!MerkleProof.verify(proof, currentRoot, leaf)) revert InvalidProof();

        uint256 alreadyClaimed = claimed[msg.sender];
        if (cumulativeAmount <= alreadyClaimed) return; // already fully claimed — no-op

        uint256 delta = cumulativeAmount - alreadyClaimed;
        if (clgo.balanceOf(address(this)) < delta) revert InsufficientVaultBalance();

        claimed[msg.sender] = cumulativeAmount;
        clgo.safeTransfer(msg.sender, delta);

        emit Claimed(msg.sender, delta, cumulativeAmount);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    /// @notice Preview how much a user can claim right now (0 if proof invalid or nothing pending)
    function pendingFor(address user, uint256 cumulativeAmount, bytes32[] calldata proof)
        external view returns (uint256)
    {
        bytes32 leaf = _buildLeaf(user, cumulativeAmount);
        if (!MerkleProof.verify(proof, currentRoot, leaf)) return 0;
        if (cumulativeAmount <= claimed[user]) return 0;
        return cumulativeAmount - claimed[user];
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    /// @notice Emergency CLGO withdrawal — admin only (migration / guardian use)
    function emergencyWithdraw(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        clgo.safeTransfer(to, amount);
    }

    // ── Internal ─────────────────────────────────────────────────────────────

    function _buildLeaf(address recipient, uint256 cumulativeAmount) internal view returns (bytes32) {
        return keccak256(abi.encode(
            CLAIM_TYPEHASH,
            block.chainid,   // = 1 on Ethereum Mainnet — prevents Base replay
            address(this),   // = this vault — prevents cross-vault replay
            recipient,
            cumulativeAmount
        ));
    }
}
