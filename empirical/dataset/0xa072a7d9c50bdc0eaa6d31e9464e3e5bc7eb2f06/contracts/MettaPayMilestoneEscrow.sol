// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IComplianceRegistry} from "./IComplianceRegistry.sol";

/**
 * @title MettaPayMilestoneEscrow
 * @notice Milestone escrow logic, identical in shape to MettaPayEscrowV2
 *         except:
 *           - There is one Deal per CLONE (not many per contract). The deal
 *             is created in `initialize()` by the factory at construction time.
 *           - The compliance officer allowlist is read from the parent factory
 *             (IComplianceRegistry), so a single addCompliance / removeCompliance
 *             call on the factory takes effect on every existing and future clone.
 *           - Fees and feeWallet are snapshotted from the factory at initialize()
 *             so the buyer's economics cannot be changed mid-flight.
 *           - `notifyOfficer` is a per-escrow UX hint stored on-chain so the
 *             backend can route notifications to a preferred officer first;
 *             it is NOT enforced (any allowlisted officer can act).
 *
 *         The on-chain action surface (markFulfilled / cosignerApproveMilestone /
 *         complianceReleaseMilestone / requestRecallMilestone / approveRecall /
 *         denyRecall / autoReleaseMilestone / requestDealRecall / approveDealRecall /
 *         denyDealRecall) matches V2 1:1, except every function drops the
 *         `bytes32 dealId` first argument (there is only one deal per clone).
 */
contract MettaPayMilestoneEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────

    uint8  public constant MAX_COSIGNERS = 10;
    uint8  public constant MAX_MILESTONES = 20;
    uint16 public constant BPS_DENOM = 10_000;

    // ─────────────────────────────────────────────────────────────────────
    // Immutable-ish state (set once in initialize)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Parent factory. Source of truth for the officer allowlist.
    address public factory;
    /// @notice Stable id assigned by the factory (also derivable off-chain).
    bytes32 public dealId;
    /// @notice Snapshotted at funding time, never changes after.
    address public feeWallet;
    uint16  public depositFeeBps;
    uint16  public releaseFeeBps;
    uint16  public recallFeeBps;
    /// @notice UX hint: backend routes the first compliance notification here.
    ///         Any officer in the factory allowlist may still act on-chain.
    address public notifyOfficer;

    // ─────────────────────────────────────────────────────────────────────
    // Types & Deal storage (single deal per clone)
    // ─────────────────────────────────────────────────────────────────────

    enum DealStatus {
        NONE,                  // 0
        ACTIVE,                // 1
        FULL_RECALL_REQUESTED, // 2
        SETTLED,               // 3
        RECALLED               // 4
    }

    enum MStatus {
        NONE,                  // 0
        PENDING,               // 1
        FULFILLED,             // 2
        COMPLIANCE_REQUESTED,  // 3
        RECALL_REQUESTED,      // 4
        RELEASED,              // 5
        REFUNDED               // 6
    }

    struct MilestoneInput {
        uint16 pctBps;
        uint64 deadline;
        bool   requiresCompliance;
    }

    struct Milestone {
        uint256 escrowedAmount;
        uint256 grossShare;
        uint64  deadline;
        bool    requiresCompliance;
        uint8   approvedCount;
        MStatus status;
        MStatus statusBeforeRecall;
    }

    address public buyer;
    address public seller;
    address public token;            // address(0) = native
    uint256 public grossAmount;
    uint256 public escrowedRemaining;
    uint8   public threshold;
    uint8   public milestoneCount;
    uint8   public openMilestones;
    DealStatus public status;
    uint64  public createdAt;

    address[] private _cosigners;
    mapping(address => bool) public isCosigner;
    /// @notice idx → cosigner → approved
    mapping(uint8 => mapping(address => bool)) public hasApprovedMilestone;
    mapping(uint8 => Milestone) private _milestones;

    bool private _initialized;

    // ─────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────

    event DealFunded(
        bytes32 indexed dealId,
        address indexed buyer,
        address indexed seller,
        address token,
        uint256 grossAmount,
        uint256 escrowedAmount,
        uint8 threshold,
        uint8 milestoneCount,
        address notifyOfficer
    );
    event MilestoneFulfilled(bytes32 indexed dealId, uint8 indexed idx, address indexed seller);
    event MilestoneCosignerApproved(bytes32 indexed dealId, uint8 indexed idx, address indexed cosigner, uint8 approvedCount);
    event MilestoneCosignThresholdMet(bytes32 indexed dealId, uint8 indexed idx);
    event MilestoneReleased(bytes32 indexed dealId, uint8 indexed idx, address indexed releaser, uint256 paidToSeller, bool autoTimelock);
    event MilestoneRecallRequested(bytes32 indexed dealId, uint8 indexed idx, address indexed buyer, bytes32 reasonHash);
    event MilestoneRecallApproved(bytes32 indexed dealId, uint8 indexed idx, address indexed officer, uint256 refundedToBuyer);
    event MilestoneRecallDenied(bytes32 indexed dealId, uint8 indexed idx, address indexed officer);
    event DealRecallRequested(bytes32 indexed dealId, address indexed buyer, bytes32 reasonHash);
    event DealRecallApproved(bytes32 indexed dealId, address indexed officer, uint256 refundedToBuyer);
    event DealRecallDenied(bytes32 indexed dealId, address indexed officer);
    event DealSettled(bytes32 indexed dealId);
    event FeeCollected(bytes32 indexed dealId, uint8 indexed milestoneIdx, bytes32 indexed kind, address token, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────

    error AlreadyInitialized();
    error OnlyFactory();
    error ZeroAddress();
    error DealNotFound();
    error WrongStatus();
    error WrongMilestoneStatus();
    error NotBuyer();
    error NotSeller();
    error NotCompliance();
    error NotCosigner();
    error AlreadyApproved();
    error InvalidThreshold();
    error TooManyCosigners();
    error TooManyMilestones();
    error NoMilestones();
    error BadPctSum();
    error DuplicateCosigner();
    error SelfDeal();
    error PartyConflict();
    error AmountMismatch();
    error NotEth();
    error TransferFailed();
    error TimelockNotReached();
    error TimelockNotApplicable();
    error DealNotPristine();

    // ─────────────────────────────────────────────────────────────────────
    // Initialize (called by factory inside createEscrow)
    // ─────────────────────────────────────────────────────────────────────

    struct InitParams {
        bytes32 dealId;
        address buyer;
        address seller;
        address token;
        uint256 amount;          // already pulled by factory; this is the gross
        address[] cosigners;
        uint8 threshold;
        MilestoneInput[] milestones;
        address notifyOfficer;   // may be address(0)
        address feeWallet;
        uint16 depositFeeBps;
        uint16 releaseFeeBps;
        uint16 recallFeeBps;
    }

    function initialize(InitParams calldata p) external payable nonReentrant {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        factory = msg.sender;

        if (p.dealId == bytes32(0)) revert DealNotFound();
        if (p.buyer == address(0) || p.seller == address(0)) revert ZeroAddress();
        if (p.buyer == p.seller) revert SelfDeal();
        if (p.amount == 0) revert AmountMismatch();
        if (p.cosigners.length == 0 || p.cosigners.length > MAX_COSIGNERS) revert TooManyCosigners();
        if (p.threshold == 0 || p.threshold > p.cosigners.length) revert InvalidThreshold();
        if (p.milestones.length == 0) revert NoMilestones();
        if (p.milestones.length > MAX_MILESTONES) revert TooManyMilestones();
        if (p.feeWallet == address(0)) revert ZeroAddress();

        // Funds must already be inside this contract (factory transferred them).
        if (p.token == address(0)) {
            if (msg.value != p.amount) revert AmountMismatch();
        } else {
            if (msg.value != 0) revert NotEth();
            // Defense-in-depth: the factory has already done safeTransferFrom
            // to address(this); we trust it for accounting but a sanity check
            // would cost gas with no real benefit.
        }

        dealId        = p.dealId;
        buyer         = p.buyer;
        seller        = p.seller;
        token         = p.token;
        grossAmount   = p.amount;
        feeWallet     = p.feeWallet;
        depositFeeBps = p.depositFeeBps;
        releaseFeeBps = p.releaseFeeBps;
        recallFeeBps  = p.recallFeeBps;
        notifyOfficer = p.notifyOfficer;

        uint256 depFee = (p.amount * p.depositFeeBps) / BPS_DENOM;
        uint256 escrowed = p.amount - depFee;
        escrowedRemaining = escrowed;
        threshold = p.threshold;
        milestoneCount = uint8(p.milestones.length);
        openMilestones = uint8(p.milestones.length);
        status = DealStatus.ACTIVE;
        createdAt = uint64(block.timestamp);

        for (uint256 i = 0; i < p.cosigners.length; i++) {
            address c = p.cosigners[i];
            if (c == address(0)) revert ZeroAddress();
            if (c == p.buyer || c == p.seller) revert PartyConflict();
            if (isCosigner[c]) revert DuplicateCosigner();
            isCosigner[c] = true;
            _cosigners.push(c);
        }

        uint16 pctSum = 0;
        uint256 escAssigned = 0;
        uint256 grossAssigned = 0;
        for (uint256 i = 0; i < p.milestones.length; i++) {
            MilestoneInput calldata mi = p.milestones[i];
            if (mi.pctBps == 0) revert BadPctSum();
            pctSum += mi.pctBps;
            Milestone storage m = _milestones[uint8(i)];
            if (i + 1 == p.milestones.length) {
                m.escrowedAmount = escrowed - escAssigned;
                m.grossShare = p.amount - grossAssigned;
            } else {
                uint256 escShare = (escrowed * mi.pctBps) / BPS_DENOM;
                uint256 grossShare = (p.amount * mi.pctBps) / BPS_DENOM;
                m.escrowedAmount = escShare;
                m.grossShare = grossShare;
                escAssigned += escShare;
                grossAssigned += grossShare;
            }
            m.deadline = mi.deadline;
            m.requiresCompliance = mi.requiresCompliance;
            m.status = MStatus.PENDING;
        }
        if (pctSum != BPS_DENOM) revert BadPctSum();

        if (depFee > 0) {
            _payOut(p.token, p.feeWallet, depFee);
            emit FeeCollected(p.dealId, type(uint8).max, keccak256("deposit"), p.token, depFee);
        }

        emit DealFunded(
            p.dealId, p.buyer, p.seller, p.token, p.amount, escrowed,
            p.threshold, uint8(p.milestones.length), p.notifyOfficer
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────

    function cosigners() external view returns (address[] memory) { return _cosigners; }

    function getMilestone(uint8 idx) external view returns (
        uint256 escrowedAmount,
        uint256 grossShare,
        uint64 deadline,
        bool requiresCompliance,
        uint8 approvedCount,
        MStatus mstatus
    ) {
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        return (m.escrowedAmount, m.grossShare, m.deadline, m.requiresCompliance, m.approvedCount, m.status);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Seller / cosigners
    // ─────────────────────────────────────────────────────────────────────

    function markFulfilled(uint8 idx) external {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (msg.sender != seller) revert NotSeller();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (m.status != MStatus.PENDING) revert WrongMilestoneStatus();
        m.status = MStatus.FULFILLED;
        emit MilestoneFulfilled(dealId, idx, msg.sender);
    }

    function cosignerApproveMilestone(uint8 idx) external nonReentrant {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (!isCosigner[msg.sender]) revert NotCosigner();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (m.status != MStatus.FULFILLED) revert WrongMilestoneStatus();
        if (hasApprovedMilestone[idx][msg.sender]) revert AlreadyApproved();

        hasApprovedMilestone[idx][msg.sender] = true;
        unchecked { m.approvedCount += 1; }
        emit MilestoneCosignerApproved(dealId, idx, msg.sender, m.approvedCount);

        if (m.approvedCount >= threshold) {
            emit MilestoneCosignThresholdMet(dealId, idx);
            if (m.requiresCompliance) {
                m.status = MStatus.COMPLIANCE_REQUESTED;
            } else {
                _releaseMilestone(idx, msg.sender, false);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Compliance — gated by factory allowlist
    // ─────────────────────────────────────────────────────────────────────

    modifier onlyCompliance() {
        if (!IComplianceRegistry(factory).isCompliance(msg.sender)) revert NotCompliance();
        if (msg.sender == buyer || msg.sender == seller || isCosigner[msg.sender]) revert PartyConflict();
        _;
    }

    function complianceReleaseMilestone(uint8 idx) external nonReentrant onlyCompliance {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (m.status != MStatus.COMPLIANCE_REQUESTED) revert WrongMilestoneStatus();
        _releaseMilestone(idx, msg.sender, false);
    }

    function autoReleaseMilestone(uint8 idx) external nonReentrant {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (m.status != MStatus.FULFILLED) revert WrongMilestoneStatus();
        if (m.requiresCompliance) revert TimelockNotApplicable();
        if (m.deadline == 0) revert TimelockNotApplicable();
        if (block.timestamp < m.deadline) revert TimelockNotReached();
        _releaseMilestone(idx, msg.sender, true);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Recall (per milestone & whole-deal)
    // ─────────────────────────────────────────────────────────────────────

    function requestRecallMilestone(uint8 idx, bytes32 reasonHash) external {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (msg.sender != buyer) revert NotBuyer();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (
            m.status != MStatus.PENDING &&
            m.status != MStatus.FULFILLED &&
            m.status != MStatus.COMPLIANCE_REQUESTED
        ) revert WrongMilestoneStatus();
        m.statusBeforeRecall = m.status;
        m.status = MStatus.RECALL_REQUESTED;
        emit MilestoneRecallRequested(dealId, idx, msg.sender, reasonHash);
    }

    function approveRecallMilestone(uint8 idx) external nonReentrant onlyCompliance {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (m.status != MStatus.RECALL_REQUESTED) revert WrongMilestoneStatus();

        uint256 escrowed = m.escrowedAmount;
        uint256 fee = (m.grossShare * recallFeeBps) / BPS_DENOM;
        if (fee > escrowed) fee = escrowed;
        uint256 toBuyer = escrowed - fee;

        m.escrowedAmount = 0;
        m.status = MStatus.REFUNDED;
        escrowedRemaining -= escrowed;
        _closeMilestone();

        if (fee > 0) {
            _payOut(token, feeWallet, fee);
            emit FeeCollected(dealId, idx, keccak256("recall"), token, fee);
        }
        if (toBuyer > 0) _payOut(token, buyer, toBuyer);
        emit MilestoneRecallApproved(dealId, idx, msg.sender, toBuyer);
    }

    function denyRecallMilestone(uint8 idx) external onlyCompliance {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (idx >= milestoneCount) revert WrongMilestoneStatus();
        Milestone storage m = _milestones[idx];
        if (m.status != MStatus.RECALL_REQUESTED) revert WrongMilestoneStatus();
        m.status = m.statusBeforeRecall;
        emit MilestoneRecallDenied(dealId, idx, msg.sender);
    }

    function requestDealRecall(bytes32 reasonHash) external {
        if (status != DealStatus.ACTIVE) revert WrongStatus();
        if (msg.sender != buyer) revert NotBuyer();
        for (uint8 i = 0; i < milestoneCount; i++) {
            if (_milestones[i].status != MStatus.PENDING) revert DealNotPristine();
        }
        status = DealStatus.FULL_RECALL_REQUESTED;
        emit DealRecallRequested(dealId, msg.sender, reasonHash);
    }

    function approveDealRecall() external nonReentrant onlyCompliance {
        if (status != DealStatus.FULL_RECALL_REQUESTED) revert WrongStatus();

        uint256 escrowed = escrowedRemaining;
        uint256 fee = (grossAmount * recallFeeBps) / BPS_DENOM;
        if (fee > escrowed) fee = escrowed;
        uint256 toBuyer = escrowed - fee;

        for (uint8 i = 0; i < milestoneCount; i++) {
            Milestone storage m = _milestones[i];
            m.escrowedAmount = 0;
            m.status = MStatus.REFUNDED;
        }
        escrowedRemaining = 0;
        openMilestones = 0;
        status = DealStatus.RECALLED;

        if (fee > 0) {
            _payOut(token, feeWallet, fee);
            emit FeeCollected(dealId, type(uint8).max, keccak256("recall"), token, fee);
        }
        if (toBuyer > 0) _payOut(token, buyer, toBuyer);
        emit DealRecallApproved(dealId, msg.sender, toBuyer);
    }

    function denyDealRecall() external onlyCompliance {
        if (status != DealStatus.FULL_RECALL_REQUESTED) revert WrongStatus();
        status = DealStatus.ACTIVE;
        emit DealRecallDenied(dealId, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────

    function _releaseMilestone(uint8 idx, address releaser, bool auto_) internal {
        Milestone storage m = _milestones[idx];
        uint256 escrowed = m.escrowedAmount;
        uint256 fee = (escrowed * releaseFeeBps) / BPS_DENOM;
        uint256 toSeller = escrowed - fee;

        m.escrowedAmount = 0;
        m.status = MStatus.RELEASED;
        escrowedRemaining -= escrowed;
        _closeMilestone();

        if (fee > 0) {
            _payOut(token, feeWallet, fee);
            emit FeeCollected(dealId, idx, keccak256("release"), token, fee);
        }
        if (toSeller > 0) _payOut(token, seller, toSeller);
        emit MilestoneReleased(dealId, idx, releaser, toSeller, auto_);
    }

    function _closeMilestone() internal {
        unchecked { openMilestones -= 1; }
        if (openMilestones == 0) {
            status = DealStatus.SETTLED;
            emit DealSettled(dealId);
        }
    }

    function _payOut(address tok, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (tok == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(tok).safeTransfer(to, amount);
        }
    }

    receive() external payable { revert NotEth(); }
}
