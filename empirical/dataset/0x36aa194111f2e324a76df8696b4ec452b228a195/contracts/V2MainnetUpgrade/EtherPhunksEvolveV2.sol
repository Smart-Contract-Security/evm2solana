// SPDX-License-Identifier: PHUNKY

/* ========================================
   ∬  EtherPhunks Mutation V2              ∬
   ========================================
   ∬  V2 changes from V1:                   ∬
   ∬  - 5-block deposit cooldown            ∬
   ∬  - Fallback no longer auto-executes    ∬
   ∬  - cancelDeposit admin sweep           ∬
   ∬  - Storage-compatible UUPS upgrade     ∬
   ====================================== */

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract MutationV2 is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ─── Events ────────────────────────────────────────────

    event ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
        address indexed previousOwner,
        address indexed recipient,
        bytes32 indexed id
    );

    event Evolved(
        address indexed user,
        uint256 indexed pairId,
        bytes32 ogHashId,
        bytes32 quantumHashId
    );

    event Devolved(
        address indexed user,
        uint256 indexed pairId,
        bytes32 quantumHashId,
        bytes32 ogHashId
    );

    event PairsRegistered(uint256 startPairId, uint256 count);

    event QuantumHashIdUpdated(
        uint256 indexed pairId,
        bytes32 oldQuantumHashId,
        bytes32 newQuantumHashId
    );

    // V2 new events
    event Deposited(bytes32 indexed hashId, address indexed user, uint256 blockNumber);
    event DepositCancelled(bytes32 indexed hashId, address indexed user);

    // ─── Errors ────────────────────────────────────────────

    error InvalidDataLength();
    error UnknownEthscription();
    error PartnerNotAvailable();
    error InsufficientFee();
    error NotDepositor();
    error NotOg();
    error NotQuantum();
    // V2 new errors
    error CooldownActive(uint256 blocksRemaining);
    error NoDeposit();
    error CannotCancelOwnerDeposit();

    // ─── State (V1 — preserved storage layout) ─────────────

    uint256 public evolveFee;
    uint256 public pairCount;

    mapping(uint256 => bytes32) public ogHashId;
    mapping(uint256 => bytes32) public quantumHashId;
    mapping(uint256 => bool)    public feePaid;
    mapping(bytes32 => uint256) public pairIdOf;
    mapping(bytes32 => bool)    public isOg;
    mapping(bytes32 => bool)    public registered;
    mapping(bytes32 => address) public depositor;
    mapping(address => uint256) public pendingReturns;

    // ─── State (V2 — appended; consumes 1 slot from gap) ───

    /// @dev Block number when each (user, hashId) was deposited. 0 = no deposit.
    ///      User must wait DEPOSIT_COOLDOWN_BLOCKS before calling evolve/devolve.
    mapping(address => mapping(bytes32 => uint256)) public depositBlockNumber;

    // Storage gap (was 49, now 48 — 1 consumed by depositBlockNumber)
    uint256[48] private __gap;

    // ─── Constants ─────────────────────────────────────────

    uint256 public constant DEPOSIT_COOLDOWN_BLOCKS = 5;

    // ─── Constructor & Initializer ──────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    /// @notice Original V1 initializer. Not callable after first deploy.
    function initialize(uint256 _evolveFee) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        evolveFee = _evolveFee;
    }

    /// @notice V2 reinitializer. Called once during upgrade.
    ///         No state to initialize — depositBlockNumber starts empty by design.
    ///         New deposits will populate it; existing pre-loaded items don't need cooldown
    ///         (they're admin-deposited and trusted).
    function initializeV2() public reinitializer(2) {
        // Intentionally empty — V2 has no new state requiring initialization.
        // Existing depositor mappings remain valid for already-deposited items.
    }

    // ─── Admin: Register pairs ────────────────────────────

    function registerPairs(
        bytes32[] calldata _ogHashIds,
        bytes32[] calldata _quantumHashIds
    ) external onlyOwner {
        require(_ogHashIds.length == _quantumHashIds.length, "Length mismatch");

        uint256 startId = pairCount;

        for (uint256 i = 0; i < _ogHashIds.length; i++) {
            require(!registered[_ogHashIds[i]], "OG already registered");
            require(!registered[_quantumHashIds[i]], "Quantum already registered");

            uint256 pid = pairCount++;

            ogHashId[pid] = _ogHashIds[i];
            quantumHashId[pid] = _quantumHashIds[i];

            pairIdOf[_ogHashIds[i]] = pid;
            pairIdOf[_quantumHashIds[i]] = pid;

            isOg[_ogHashIds[i]] = true;

            registered[_ogHashIds[i]] = true;
            registered[_quantumHashIds[i]] = true;
        }

        emit PairsRegistered(startId, _ogHashIds.length);
    }

    // ─── Admin: Update quantum hashId for a pair ─────────

    function updateQuantumHashId(
        uint256 pid,
        bytes32 newQuantumHashId
    ) external onlyOwner {
        require(pid < pairCount, "Invalid pair ID");
        require(newQuantumHashId != bytes32(0), "Zero hashId");

        bytes32 oldQuantumHashId = quantumHashId[pid];
        require(oldQuantumHashId != newQuantumHashId, "Same hashId");
        require(!registered[newQuantumHashId], "New quantum already registered");

        delete registered[oldQuantumHashId];
        delete pairIdOf[oldQuantumHashId];
        delete depositor[oldQuantumHashId];

        quantumHashId[pid] = newQuantumHashId;
        pairIdOf[newQuantumHashId] = pid;
        registered[newQuantumHashId] = true;

        emit QuantumHashIdUpdated(pid, oldQuantumHashId, newQuantumHashId);
    }

    // ─── Fallback: Record deposit only — NO auto-execute ───
    //
    //  V2 CHANGE: Non-owner deposits no longer trigger _evolve/_devolve in
    //  the same tx. User must call evolve()/devolve() after the 5-block
    //  cooldown. This gives the off-chain indexer time to verify protocol-
    //  level ownership and call cancelDeposit() on fakes.

    fallback() external payable nonReentrant {
        if (msg.data.length == 0 || msg.data.length % 32 != 0) revert InvalidDataLength();
        require(!paused(), "Pausable: paused");

        uint256 count = msg.data.length / 32;

        // Owner pre-load: cooldown bypass (admin trusted)
        if (msg.sender == owner()) {
            for (uint256 i = 0; i < count; i++) {
                bytes32 hId;
                assembly {
                    hId := calldataload(mul(i, 32))
                }
                if (!registered[hId]) revert UnknownEthscription();
                depositor[hId] = msg.sender;
                // Mark as immediately valid (block 1 = always past cooldown)
                depositBlockNumber[msg.sender][hId] = 1;
                emit Deposited(hId, msg.sender, 1);
            }
            return;
        }

        // Non-owner: single deposit only, no auto-execute
        if (count != 1) revert InvalidDataLength();

        bytes32 hashId;
        assembly {
            hashId := calldataload(0)
        }

        if (!registered[hashId]) revert UnknownEthscription();
        depositor[hashId] = msg.sender;
        depositBlockNumber[msg.sender][hashId] = block.number;
        emit Deposited(hashId, msg.sender, block.number);

        // No auto-execute. User must call evolve(hashId) after cooldown.
    }

    receive() external payable {
        revert("No direct ETH transfers");
    }

    // ─── Internal: Cooldown check ──────────────────────────

    function _requireCooldownPassed(address user, bytes32 hashId) internal view {
        uint256 dep = depositBlockNumber[user][hashId];
        if (dep == 0) revert NoDeposit();
        uint256 elapsed = block.number - dep;
        if (elapsed < DEPOSIT_COOLDOWN_BLOCKS) {
            revert CooldownActive(DEPOSIT_COOLDOWN_BLOCKS - elapsed);
        }
    }

    // ─── Internal: Evolve (OG → Quantum) ──────────────────

    function _evolve(address user, uint256 pid) internal {
        bytes32 qHashId = quantumHashId[pid];
        address qDepositor = depositor[qHashId];

        if (qDepositor == address(0)) revert PartnerNotAvailable();

        // Charge fee on first evolve only
        uint256 feeRequired = 0;
        if (!feePaid[pid]) {
            if (msg.value < evolveFee) revert InsufficientFee();
            feePaid[pid] = true;
            feeRequired = evolveFee;
        }

        // Transfer quantum ethscription to user
        emit ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
            qDepositor,
            user,
            qHashId
        );
        delete depositor[qHashId];
        delete depositBlockNumber[qDepositor][qHashId];

        emit Evolved(user, pid, ogHashId[pid], qHashId);

        // Refund excess ETH (hybrid push/pull)
        if (msg.value > feeRequired) {
            uint256 refund = msg.value - feeRequired;
            (bool sent, ) = payable(user).call{value: refund}("");
            if (!sent) {
                pendingReturns[user] += refund;
            }
        }
    }

    // ─── Internal: Devolve (Quantum → OG) ─────────────────

    function _devolve(address user, uint256 pid) internal {
        bytes32 oHashId = ogHashId[pid];
        address oDepositor = depositor[oHashId];

        if (oDepositor == address(0)) revert PartnerNotAvailable();

        emit ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
            oDepositor,
            user,
            oHashId
        );
        delete depositor[oHashId];
        delete depositBlockNumber[oDepositor][oHashId];

        emit Devolved(user, pid, quantumHashId[pid], oHashId);

        if (msg.value > 0) {
            (bool sent, ) = payable(user).call{value: msg.value}("");
            if (!sent) {
                pendingReturns[user] += msg.value;
            }
        }
    }

    // ─── Explicit swap (cooldown-gated) ────────────────────

    function evolve(bytes32 hashId) external payable nonReentrant {
        if (!registered[hashId]) revert UnknownEthscription();
        if (depositor[hashId] != msg.sender) revert NotDepositor();
        require(!paused(), "Pausable: paused");

        uint256 pid = pairIdOf[hashId];
        if (!isOg[hashId]) revert NotOg();

        // V2: enforce 5-block cooldown on the user's OG deposit
        _requireCooldownPassed(msg.sender, hashId);

        // Clear the user's OG deposit BEFORE _evolve to prevent re-use
        delete depositor[hashId];
        delete depositBlockNumber[msg.sender][hashId];

        _evolve(msg.sender, pid);
    }

    function devolve(bytes32 hashId) external payable nonReentrant {
        if (!registered[hashId]) revert UnknownEthscription();
        if (depositor[hashId] != msg.sender) revert NotDepositor();
        require(!paused(), "Pausable: paused");

        uint256 pid = pairIdOf[hashId];
        if (isOg[hashId]) revert NotQuantum();

        _requireCooldownPassed(msg.sender, hashId);

        delete depositor[hashId];
        delete depositBlockNumber[msg.sender][hashId];

        _devolve(msg.sender, pid);
    }

    // ─── V2 NEW: Cancel fake deposit (indexer-triggered) ───
    //
    //  Off-chain indexer detects deposits where the depositor didn't
    //  actually own the ethscription at the protocol level, and calls
    //  this function to wipe the bogus deposit before the cooldown
    //  expires. Owner-only.

    function cancelDeposit(bytes32 hashId) external onlyOwner {
        address d = depositor[hashId];
        if (d == address(0)) revert NoDeposit();
        // Don't allow canceling owner pre-loads
        if (d == owner()) revert CannotCancelOwnerDeposit();

        delete depositor[hashId];
        delete depositBlockNumber[d][hashId];

        emit DepositCancelled(hashId, d);
    }

    /// @notice Batch variant for sweeping multiple fakes in one tx.
    function cancelDepositBatch(bytes32[] calldata hashIds) external onlyOwner {
        for (uint256 i = 0; i < hashIds.length; i++) {
            address d = depositor[hashIds[i]];
            if (d == address(0) || d == owner()) continue;
            delete depositor[hashIds[i]];
            delete depositBlockNumber[d][hashIds[i]];
            emit DepositCancelled(hashIds[i], d);
        }
    }

    // ─── Admin functions ──────────────────────────────────

    function setFee(uint256 _fee) external onlyOwner {
        evolveFee = _fee;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingReturns[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Transfer failed");
    }

    function withdrawETH() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "Transfer failed");
    }

    function withdrawEthscription(bytes32 hashId, address to) external onlyOwner {
        address prevOwner = depositor[hashId] != address(0) ? depositor[hashId] : to;
        emit ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
            prevOwner,
            to,
            hashId
        );
        delete depositor[hashId];
        delete depositBlockNumber[prevOwner][hashId];
    }

    function redirectPendingReturns(address from, address payable to) external onlyOwner {
        require(to != address(0), "Invalid address");
        uint256 amount = pendingReturns[from];
        require(amount > 0, "Nothing to redirect");
        pendingReturns[from] = 0;
        pendingReturns[to] += amount;
    }

    function renounceOwnership() public pure override {
        revert("Cannot renounce ownership");
    }
}
