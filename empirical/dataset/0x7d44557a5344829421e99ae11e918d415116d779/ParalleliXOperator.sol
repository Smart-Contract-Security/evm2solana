// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ParalleliXOperator — node-operator collateral + rewards distribution
/// @notice Unified contract handling both operator collateral (per
///         tokenomics.md §8) and operator rewards distribution (per
///         tokenomics.md §3 and §9). Per project decision, kept as ONE
///         contract for simpler ops and a single address operators
///         interact with.
///
///         === SUPPLY ALLOCATION (canonical, per tokenomics.md §3) ===
///         Total supply:              100,000,000 PRLX (fixed, no inflation)
///         Operator Rewards bucket:    25,000,000 PRLX  (25 %)
///         Located in:                Sablier vesting stream LK3-1-664
///                                    https://app.sablier.com/vesting/stream/LK3-1-664
///         Vesting:                   Linear over 24 months from launch
///         Release rate:              ~1,041,666 PRLX per month
///                                    ~240,384 PRLX per week
///
///         === STAKING (collateral, per tokenomics.md §8) ===
///         "$PRLX staking is collateral posted by node operators to
///         participate in the compute network. It is not a holder
///         yield product."
///
///         Operators allowlisted by a registrar wallet (coordinator-
///         controlled). Per-node deposit of exactly 50,000 PRLX.
///         Multi-node operators stack deposits per-node. 7-day
///         cooldown to unstake. Slashable to Treasury for the six
///         misbehavior categories in §8.
///
///         === REWARDS (cumulative merkle drop, per tokenomics.md §9) ===
///         Operator earnings — computed off-chain by the coordinator
///         per §9 formula (base × complexity × uptime × reputation) —
///         are distributed via a weekly cumulative merkle root.
///
///         Weekly cycle (dev EOA per project decision):
///           1. Sablier.withdraw(LK3-1-664) → dev wallet
///           2. PRLX.transfer(this contract, weekly_amount ≈ 240,384)
///           3. publishRoot(newMerkleRoot)
///         Operators claim via CLI / Console at their own gas.
///
///         The 25M bucket lives in Sablier until each weekly slice is
///         pulled. The contract holds ~240K PRLX at any moment, not
///         25M. The merkle root is publisher-trusted (same model as
///         UNI/OP/ENS cumulative airdrops); the published tree is
///         posted off-chain so any operator can verify their leaf
///         against the §9 formula before claiming.
///
///         === KEY INVARIANT ===
///         At all times, `prlx.balanceOf(this) >= totalEscrowed`.
///         Active + pending stake never leaks to the rewards pool;
///         `emergencyWithdraw` is bounded to `balance - totalEscrowed`
///         so the owner can drain over-funded rewards but never touch
///         operator collateral.
///
///         === PRE-DEPLOY CHECKLIST ===
///           1. Six addresses: token, owner, slasher, registrar,
///              treasury, publisher. EOAs per project decision.
///           2. Per-node minimum (50K) and cooldown (7d) are CONSTANTS,
///              not constructor args — protocol commitments, not
///              admin-tunable.
///           3. PRLX 5% tax fires only on DEX-pair transfers; this
///              contract is not a pair and isn't taxed.
///           4. Deploy on Sepolia first, exercise the full lifecycle
///              including a slash, before mainnet.
contract ParalleliXOperator {
    // ---------------------------------------------------------------------
    //  Errors
    // ---------------------------------------------------------------------
    error NotOwner();
    error NotPendingOwner();
    error NotSlasher();
    error NotRegistrar();
    error NotPublisher();
    error InvalidAddress();
    error InvalidPercent();
    error InvalidProof();
    error ZeroAmount();
    error NotAllowedOperator();
    error NodeAlreadyExists();
    error NodeNotFound();
    error NodeNotOwnedByCaller();
    error UnstakeAlreadyPending();
    error NoUnstakePending();
    error UnstakeNotMatured();
    error UnstakeInProgress();
    error NodePermanentlyBanned();
    error NothingToClaim();
    error WithdrawExceedsRewardsPool();
    error TransferFailed();
    error Reentrancy();

    // ---------------------------------------------------------------------
    //  Events
    // ---------------------------------------------------------------------
    // Staking lifecycle (the coordinator listens for these to maintain
    // the off-chain operator state).
    event OperatorAllowed(address indexed operator);
    event OperatorRevoked(address indexed operator);
    event Staked(address indexed operator, bytes32 indexed nodeId, uint256 amount);
    event ToppedUp(address indexed operator, bytes32 indexed nodeId, uint256 amount, uint256 newStake);
    event UnstakeRequested(address indexed operator, bytes32 indexed nodeId, uint256 amount, uint64 unlocksAt);
    event UnstakeCancelled(address indexed operator, bytes32 indexed nodeId, uint256 amount);
    event StakeWithdrawn(address indexed operator, bytes32 indexed nodeId, uint256 amount);
    event Slashed(
        address indexed operator,
        bytes32 indexed nodeId,
        uint256 amount,
        uint16 percentBps,
        bytes32 reasonHash,
        string reason,
        bool permanentBan
    );

    // Rewards.
    event RootPublished(bytes32 indexed root, uint256 publishedAt);
    event Claimed(address indexed operator, uint256 cumulativeEarned, uint256 deltaPaid);

    // Admin.
    event OwnershipTransferStarted(address indexed previous, address indexed pending);
    event OwnershipTransferred(address indexed previous, address indexed next);
    event SlasherChanged(address indexed previous, address indexed next);
    event RegistrarChanged(address indexed previous, address indexed next);
    event TreasuryChanged(address indexed previous, address indexed next);
    event PublisherChanged(address indexed previous, address indexed next);
    event EmergencyWithdrawal(address indexed to, uint256 amount);

    // ---------------------------------------------------------------------
    //  Constants — canonical, surfaced in source per tokenomics.md
    // ---------------------------------------------------------------------

    /// Total $PRLX supply per tokenomics.md §3 (fixed, no inflation).
    uint256 public constant PRLX_TOTAL_SUPPLY = 100_000_000 ether;

    /// 25% Operator Rewards bucket (tokenomics.md §3).
    uint256 public constant OPERATOR_REWARDS_BUCKET = 25_000_000 ether;

    /// Vesting duration per tokenomics.md §3.
    uint256 public constant OPERATOR_REWARDS_VESTING_MONTHS = 24;

    /// Per-node minimum deposit (tokenomics.md §8: "50,000 PRLX per
    /// node, single-tier"). Multi-node operators stack deposits.
    uint256 public constant MIN_STAKE_PER_NODE = 50_000 ether;

    /// Withdrawal cooldown — 7 days per tokenomics.md §8. Protocol
    /// constant, not admin-tunable.
    uint64 public constant COOLDOWN_SECONDS = 7 days;

    /// Basis-points denominator (10000 bps = 100%).
    uint16 public constant BPS_DENOM = 10_000;

    // ---------------------------------------------------------------------
    //  Immutable
    // ---------------------------------------------------------------------

    /// The $PRLX token. Set at deployment.
    IERC20 public immutable prlx;

    // ---------------------------------------------------------------------
    //  Mutable roles (all EOAs per project decision; multisigs welcome)
    // ---------------------------------------------------------------------

    /// Admin. Rotates the other roles + emergency-withdraws rewards
    /// over-funding. Two-step transfer.
    address public owner;
    address public pendingOwner;

    /// Wallet authorized to slash operators (per §8 misbehavior table).
    address public slasher;

    /// Wallet authorized to allow/revoke operators on the on-chain
    /// allowlist (driven by the coordinator's off-chain hardware
    /// registration flow).
    address public operatorRegistrar;

    /// Treasury wallet — receives slashed PRLX per §8 "Slashed PRLX
    /// flows to the Treasury (5% bucket)".
    address public treasury;

    /// Wallet authorized to publish new cumulative-earnings merkle
    /// roots. In v1, the same dev EOA that funds the rewards pool
    /// weekly from Sablier.
    address public publisher;

    // ---------------------------------------------------------------------
    //  Staking state
    // ---------------------------------------------------------------------

    /// Allowlisted operator addresses. An address must be `true`
    /// here to call `deposit`. Revoking does NOT auto-unstake
    /// existing nodes — operators can still unstake + withdraw.
    mapping(address => bool) public isAllowedOperator;

    /// Per-node position. `nodeId` is a bytes32 the CLI computes
    /// deterministically (typically keccak256(pubkey)).
    struct NodePosition {
        address operator;
        uint256 staked;
        uint192 pendingWithdrawal;
        uint64 unlocksAt;
        bool exists;
        bool permanentlyBanned;
    }

    mapping(bytes32 => NodePosition) private nodes;

    /// Sum of `staked + pendingWithdrawal` across all nodes.
    /// Invariant: `prlx.balanceOf(this) >= totalEscrowed`.
    uint256 public totalEscrowed;

    /// Per-operator running count of active nodes.
    mapping(address => uint256) public activeNodeCount;

    // ---------------------------------------------------------------------
    //  Rewards state — cumulative merkle drop
    // ---------------------------------------------------------------------

    /// Current cumulative-earnings merkle root. Each new root
    /// supersedes the prior. Operators claim against this.
    bytes32 public currentRoot;
    uint256 public currentRootPublishedAt;

    /// Cumulative PRLX claimed per operator. The contract pays out
    /// `cumulativeEarned - claimedTo[operator]` on each `claim()`.
    mapping(address => uint256) public claimedTo;

    /// Total PRLX claimed across all operators since deployment.
    uint256 public totalClaimed;

    // ---------------------------------------------------------------------
    //  Reentrancy guard
    // ---------------------------------------------------------------------

    uint256 private _reentrancyStatus = 1;

    /// uint192 max — pre-checked before any narrowing cast.
    uint256 private constant UINT192_MAX = type(uint192).max;

    // ---------------------------------------------------------------------
    //  Modifiers
    // ---------------------------------------------------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlySlasher() {
        if (msg.sender != slasher) revert NotSlasher();
        _;
    }

    modifier onlyRegistrar() {
        if (msg.sender != operatorRegistrar) revert NotRegistrar();
        _;
    }

    modifier onlyPublisher() {
        if (msg.sender != publisher) revert NotPublisher();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus != 1) revert Reentrancy();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    // ---------------------------------------------------------------------
    //  Constructor
    // ---------------------------------------------------------------------

    constructor(
        IERC20 _prlx,
        address _owner,
        address _slasher,
        address _operatorRegistrar,
        address _treasury,
        address _publisher
    ) {
        if (address(_prlx) == address(0)) revert InvalidAddress();
        if (_owner == address(0)) revert InvalidAddress();
        if (_slasher == address(0)) revert InvalidAddress();
        if (_operatorRegistrar == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();
        if (_publisher == address(0)) revert InvalidAddress();

        prlx = _prlx;
        owner = _owner;
        slasher = _slasher;
        operatorRegistrar = _operatorRegistrar;
        treasury = _treasury;
        publisher = _publisher;
    }

    // =====================================================================
    //  REGISTRAR — operator allowlist
    // =====================================================================

    function allowOperator(address operator) external onlyRegistrar {
        if (operator == address(0)) revert InvalidAddress();
        isAllowedOperator[operator] = true;
        emit OperatorAllowed(operator);
    }

    function revokeOperator(address operator) external onlyRegistrar {
        isAllowedOperator[operator] = false;
        emit OperatorRevoked(operator);
    }

    // =====================================================================
    //  OPERATOR — staking lifecycle
    // =====================================================================

    /// @notice Deposit 50,000 PRLX for a new node. Caller must be
    ///         allowlisted and have approved this contract.
    function deposit(bytes32 nodeId) external nonReentrant {
        if (!isAllowedOperator[msg.sender]) revert NotAllowedOperator();
        NodePosition storage p = nodes[nodeId];
        if (p.exists) revert NodeAlreadyExists();

        _safeTransferFrom(msg.sender, address(this), MIN_STAKE_PER_NODE);

        p.operator = msg.sender;
        p.staked = MIN_STAKE_PER_NODE;
        p.exists = true;
        totalEscrowed += MIN_STAKE_PER_NODE;
        activeNodeCount[msg.sender] += 1;
        emit Staked(msg.sender, nodeId, MIN_STAKE_PER_NODE);
    }

    /// @notice Top up an existing node (useful after a partial slash).
    function topUp(bytes32 nodeId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        NodePosition storage p = nodes[nodeId];
        if (!p.exists) revert NodeNotFound();
        if (p.operator != msg.sender) revert NodeNotOwnedByCaller();
        if (p.permanentlyBanned) revert NodePermanentlyBanned();
        if (p.pendingWithdrawal != 0) revert UnstakeInProgress();

        _safeTransferFrom(msg.sender, address(this), amount);
        p.staked += amount;
        totalEscrowed += amount;
        emit ToppedUp(msg.sender, nodeId, amount, p.staked);
    }

    /// @notice Start the 7-day cooldown. Stake remains slashable.
    function requestUnstake(bytes32 nodeId) external {
        NodePosition storage p = nodes[nodeId];
        if (!p.exists) revert NodeNotFound();
        if (p.operator != msg.sender) revert NodeNotOwnedByCaller();
        if (p.pendingWithdrawal != 0) revert UnstakeAlreadyPending();
        if (p.staked == 0) revert NoUnstakePending();
        if (p.staked > UINT192_MAX) revert UnstakeInProgress(); // safety: cast guard

        uint256 amount = p.staked;
        p.staked = 0;
        p.pendingWithdrawal = uint192(amount);
        // Safe: uint64 max corresponds to year 584,542,046.
        p.unlocksAt = uint64(block.timestamp) + COOLDOWN_SECONDS;
        emit UnstakeRequested(msg.sender, nodeId, amount, p.unlocksAt);
    }

    /// @notice Cancel a pending unstake. Funds move back to active.
    function cancelUnstake(bytes32 nodeId) external {
        NodePosition storage p = nodes[nodeId];
        if (!p.exists) revert NodeNotFound();
        if (p.operator != msg.sender) revert NodeNotOwnedByCaller();
        if (p.pendingWithdrawal == 0) revert NoUnstakePending();

        uint256 amount = p.pendingWithdrawal;
        p.pendingWithdrawal = 0;
        p.unlocksAt = 0;
        p.staked += amount;
        emit UnstakeCancelled(msg.sender, nodeId, amount);
    }

    /// @notice After 7 days, claim the unstaked collateral back.
    function withdrawStake(bytes32 nodeId) external nonReentrant {
        NodePosition storage p = nodes[nodeId];
        if (!p.exists) revert NodeNotFound();
        if (p.operator != msg.sender) revert NodeNotOwnedByCaller();
        if (p.pendingWithdrawal == 0) revert NoUnstakePending();
        if (block.timestamp < p.unlocksAt) revert UnstakeNotMatured();

        uint256 amount = p.pendingWithdrawal;
        address operator = p.operator;
        p.pendingWithdrawal = 0;
        p.unlocksAt = 0;
        p.exists = false;
        totalEscrowed -= amount;
        activeNodeCount[operator] -= 1;
        _safeTransfer(operator, amount);
        emit StakeWithdrawn(operator, nodeId, amount);
    }

    // =====================================================================
    //  SLASHER
    // =====================================================================

    /// @notice Slash a node's stake by `percentBps` (1-10000).
    ///         Slashes active first, then dips into pending. Routes
    ///         to Treasury. 100% (=10000) marks the node permanently
    ///         banned.
    function slash(
        bytes32 nodeId,
        uint16 percentBps,
        bytes32 reasonHash,
        string calldata reason
    ) external onlySlasher nonReentrant {
        if (percentBps == 0 || percentBps > BPS_DENOM) revert InvalidPercent();
        NodePosition storage p = nodes[nodeId];
        if (!p.exists) revert NodeNotFound();

        uint256 total = p.staked + p.pendingWithdrawal;
        if (total == 0) revert ZeroAmount();
        uint256 slashAmount = (total * percentBps) / BPS_DENOM;
        if (slashAmount == 0) slashAmount = 1;

        if (p.staked >= slashAmount) {
            p.staked -= slashAmount;
        } else {
            uint256 remaining = slashAmount - p.staked;
            p.staked = 0;
            p.pendingWithdrawal -= uint192(remaining);
            if (p.pendingWithdrawal == 0) p.unlocksAt = 0;
        }
        totalEscrowed -= slashAmount;

        // 100% slash also permanently bans the node and decrements
        // the operator's active count. The percentage formula has
        // already zeroed both staked and pending by construction.
        bool ban = percentBps == BPS_DENOM;
        if (ban) {
            p.permanentlyBanned = true;
            activeNodeCount[p.operator] -= 1;
        }

        _safeTransfer(treasury, slashAmount);
        emit Slashed(p.operator, nodeId, slashAmount, percentBps, reasonHash, reason, ban);
    }

    // =====================================================================
    //  PUBLISHER — rewards merkle root
    // =====================================================================

    /// @notice Publish a new cumulative-earnings merkle root. Each
    ///         root supersedes the prior. Off-chain: the published
    ///         tree (e.g., parallelix.io/rewards/2026-MM-DD.json)
    ///         should expose per-operator leaf + proof so the
    ///         CLI/Console can claim without re-deriving the tree.
    function publishRoot(bytes32 newRoot) external onlyPublisher {
        currentRoot = newRoot;
        currentRootPublishedAt = block.timestamp;
        emit RootPublished(newRoot, block.timestamp);
    }

    // =====================================================================
    //  OPERATOR — claim rewards
    // =====================================================================

    /// @notice Claim accrued PRLX rewards. `cumulativeEarned` is the
    ///         operator's lifetime total as of the current root. The
    ///         contract pays `cumulativeEarned - claimedTo[caller]`.
    ///         Leaf is `keccak256(abi.encodePacked(msg.sender,
    ///         cumulativeEarned))` — binds to caller; no one else can
    ///         submit your proof.
    function claim(uint256 cumulativeEarned, bytes32[] calldata proof)
        external
        nonReentrant
    {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, cumulativeEarned));
        if (!_verifyMerkle(proof, currentRoot, leaf)) revert InvalidProof();

        uint256 already = claimedTo[msg.sender];
        if (cumulativeEarned <= already) revert NothingToClaim();

        uint256 delta = cumulativeEarned - already;
        // CEI: state before transfer.
        claimedTo[msg.sender] = cumulativeEarned;
        totalClaimed += delta;
        _safeTransfer(msg.sender, delta);
        emit Claimed(msg.sender, cumulativeEarned, delta);
    }

    // =====================================================================
    //  OWNER actions
    // =====================================================================

    function transferOwnership(address next) external onlyOwner {
        pendingOwner = next;
        emit OwnershipTransferStarted(owner, next);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        if (pendingOwner == address(0)) revert InvalidAddress();
        address previous = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }

    function setSlasher(address next) external onlyOwner {
        if (next == address(0)) revert InvalidAddress();
        emit SlasherChanged(slasher, next);
        slasher = next;
    }

    function setOperatorRegistrar(address next) external onlyOwner {
        if (next == address(0)) revert InvalidAddress();
        emit RegistrarChanged(operatorRegistrar, next);
        operatorRegistrar = next;
    }

    function setTreasury(address next) external onlyOwner {
        if (next == address(0)) revert InvalidAddress();
        emit TreasuryChanged(treasury, next);
        treasury = next;
    }

    function setPublisher(address next) external onlyOwner {
        if (next == address(0)) revert InvalidAddress();
        emit PublisherChanged(publisher, next);
        publisher = next;
    }

    /// @notice Emergency-withdraw PRLX from the rewards pool. Bounded
    ///         to `balance - totalEscrowed` so operator collateral
    ///         (staked + pending) is NEVER touchable by the owner.
    ///         Intended for: shutdown, migration, recovering an
    ///         accidental over-deposit.
    function emergencyWithdraw(address to, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 balance = prlx.balanceOf(address(this));
        uint256 rewardsPool = balance - totalEscrowed; // safe: invariant balance >= totalEscrowed
        if (amount > rewardsPool) revert WithdrawExceedsRewardsPool();
        _safeTransfer(to, amount);
        emit EmergencyWithdrawal(to, amount);
    }

    // =====================================================================
    //  Internals
    // =====================================================================

    /// @dev Standard sorted-pair merkle proof verification (matches
    ///      merkletreejs and OpenZeppelin merkle-tree defaults).
    function _verifyMerkle(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal
        pure
        returns (bool)
    {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            if (computed < sibling) {
                computed = keccak256(abi.encodePacked(computed, sibling));
            } else {
                computed = keccak256(abi.encodePacked(sibling, computed));
            }
        }
        return computed == root;
    }

    function _safeTransferFrom(address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(prlx).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!success) revert TransferFailed();
        if (data.length != 0 && !abi.decode(data, (bool))) revert TransferFailed();
    }

    function _safeTransfer(address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(prlx).call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        if (!success) revert TransferFailed();
        if (data.length != 0 && !abi.decode(data, (bool))) revert TransferFailed();
    }

    // =====================================================================
    //  Views
    // =====================================================================

    function positionOf(bytes32 nodeId)
        external
        view
        returns (
            address operator,
            uint256 staked,
            uint256 pendingWithdrawal,
            uint64 unlocksAt,
            bool exists,
            bool permanentlyBanned
        )
    {
        NodePosition storage p = nodes[nodeId];
        return (p.operator, p.staked, p.pendingWithdrawal, p.unlocksAt, p.exists, p.permanentlyBanned);
    }

    function stakeOfNode(bytes32 nodeId) external view returns (uint256) {
        return nodes[nodeId].staked;
    }

    function operatorOfNode(bytes32 nodeId) external view returns (address) {
        return nodes[nodeId].operator;
    }

    function claimableOf(address operator, uint256 cumulativeEarned)
        external
        view
        returns (uint256)
    {
        uint256 already = claimedTo[operator];
        if (cumulativeEarned <= already) return 0;
        return cumulativeEarned - already;
    }

    function rewardsPoolBalance() external view returns (uint256) {
        return prlx.balanceOf(address(this)) - totalEscrowed;
    }
}

/// Minimal ERC-20 interface — only the methods this contract touches.
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}