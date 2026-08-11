// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBurnableToken} from "../interfaces/IBurnableToken.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice Router-native ERC-20 and holder ledger for a WETH-denominated Uniswap v4 market.
/// @dev This token is the canonical holder record. Balances, burns, holder epochs,
/// launch-relative weight, and reward eligibility live in chain state. No website,
/// social feed, or off-chain registry is part of the trust surface.
///
/// Normal swaps pass through the designated v4 pool. The hook meters WETH fees,
/// closes epochs, tracks all-time-high checkpoints, and responds only to ordinary
/// exact-input buys. Confirmed highs route WETH into buyback reserve and holder
/// distribution. Consecutive confirmed highs raise the snowball level, increasing
/// the share of free-sink WETH reserved by on-chain rules.
///
/// Holder rewards are snapshot-based. Holding through more epochs can increase
/// weight through the multiplier table; decreasing before confirmation removes
/// that account from the reward denominator. The mechanic is the WETH vault at
/// rest: it pays claims, releases buyback reserve, and records execution.
///
/// The bytecode, pool, events, and accounting state are the public record.
contract Token is ERC20, IBurnableToken {
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant BUCKET_SIZE = 1 hours;
    uint256 public constant EPOCH_LENGTH = 300;
    uint256 public constant IMMATURE_BUCKETS = 168;
    uint256 public constant MATURE_BUCKET = IMMATURE_BUCKETS;
    uint256 public constant SNAPSHOT_BUCKETS = IMMATURE_BUCKETS + 1;
    uint16 public constant BASE_MULTIPLIER_BPS = 10_000;
    uint16 public constant MAX_MULTIPLIER_BPS = 50_000;
    uint256 public constant MAX_CONFIG_ADDRESSES = 16;
    uint256 public constant MAX_CONTEXT_EXPIRY_EPOCHS = 3;
    uint256 public constant FIRST_DECREASE_TWO_CONTEXT_GAS_TARGET = 11_000_000;
    uint256 public constant FIRST_DECREASE_TWO_CONTEXT_GAS_HARD_CAP = 12_000_000;

    enum HolderContextStatus {
        Invalid,
        Potential,
        Candidate,
        Closed,
        Discarded
    }

    struct HolderContext {
        HolderContextStatus status;
        uint64 epochId;
        uint48 snapshotBlock;
        uint64 snapshotTimestamp;
        uint48 openBlock;
        uint256 openSeq;
        uint64 expiresAtEpochId;
        uint64 confirmationEpochId;
        uint64 cutoffTimestamp;
        uint256 processingSeq;
        uint256 finalDisqualifiedWeight;
    }

    struct AccountContextDisqualification {
        bool exists;
        uint64 decreaseEpochId;
        uint256 decreaseSeq;
        uint256 snapshotWeight;
    }

    struct SnapshotWeightRequest {
        bool active;
        uint256 contextId;
        bool preOpen;
        uint48 snapshotBlock;
        uint64 snapshotTimestamp;
        uint64 snapshotHour;
        uint256 total;
        uint256 prelaunch;
        uint256 immatureSum;
        uint256 immatureWeight;
    }

    address public immutable holderAccountingActivator;
    bytes32 public immutable multiplierTableHash;

    uint64 public holderAccountingStartTimestamp;
    uint256 public transferSeq;
    uint256 public nextHolderContextId = 1;
    uint256 public currentPotentialContextId;
    uint256 public activeCandidateContextId;
    mapping(uint64 epochId => uint256 contextId) public potentialContextOpenedForEpoch;

    mapping(address account => bool) public isRewardExcludedAddress;
    mapping(address account => bool) public isProtocolTransferExemptAddress;
    mapping(address account => uint64) public firstHeldBlock;
    mapping(address account => uint64) public firstDecreaseBlockPlusOne;
    mapping(address account => uint256) public firstDecreaseSeqPlusOne;

    uint16[169] private _multiplierBpsByAgeBucket;

    mapping(address account => Checkpoints.Trace208) private _accountEligibleTotal;
    Checkpoints.Trace208 private _globalEligibleTotal;

    mapping(address account => Checkpoints.Trace208) private _accountPrelaunchEligible;
    Checkpoints.Trace208 private _globalPrelaunchEligible;

    mapping(address account => mapping(uint64 acquisitionHour => Checkpoints.Trace208)) private _accountBucketEligible;
    mapping(uint64 acquisitionHour => Checkpoints.Trace208) private _globalBucketEligible;

    mapping(uint256 contextId => HolderContext) private _holderContexts;
    mapping(uint256 contextId => mapping(address account => AccountContextDisqualification)) private
        _accountContextDisqualifications;
    mapping(uint256 contextId => mapping(uint256 epochId => uint256 weight)) private _disqualifiedWeightByEpoch;
    mapping(uint256 blockNumber => uint256 weight) public preOpenDisqualifiedWeightByBlock;
    mapping(uint256 blockNumber => mapping(address account => AccountContextDisqualification)) private
        _preOpenDisqualifications;

    event MultiplierTableLoaded(bytes32 tableHash);
    event HolderAccountingActivated(uint64 startTimestamp);
    event FirstDecreaseRecorded(address indexed account, uint256 indexed sequence, uint64 firstDecreaseBlockPlusOne);
    event HolderContextOpened(
        uint256 indexed contextId,
        uint64 indexed epochId,
        uint48 snapshotBlock,
        uint64 snapshotTimestamp,
        uint64 expiresAtEpochId
    );
    event HolderContextPromoted(uint256 indexed contextId, uint64 indexed epochId);
    event HolderContextDiscarded(uint256 indexed contextId, HolderContextStatus previousStatus);
    event HolderContextClosed(
        uint256 indexed contextId,
        uint64 indexed confirmationEpochId,
        uint64 cutoffTimestamp,
        uint256 processingSeq,
        uint256 finalDisqualifiedWeight
    );
    event ContextDisqualificationRecorded(
        uint256 indexed contextId,
        address indexed account,
        uint64 indexed decreaseEpochId,
        uint256 decreaseSeq,
        uint256 snapshotWeight
    );
    event PreOpenDisqualificationRecorded(
        uint256 indexed blockNumber,
        address indexed account,
        uint64 indexed decreaseEpochId,
        uint256 decreaseSeq,
        uint256 snapshotWeight
    );

    error ZeroInitialRecipient();
    error ZeroInitialSupply();
    error InitialSupplyTooLarge(uint256 supply);
    error ZeroHolderAccountingActivator();
    error TooManyConfigAddresses(uint256 count);
    error ZeroConfigAddress();
    error DuplicateConfigAddress(address account);
    error ProtocolExemptNotRewardExcluded(address account);
    error InvalidMultiplierTable(uint256 index, uint16 value);
    error UnauthorizedHolderAccountingActivator(address caller, address expected);
    error HolderAccountingAlreadyActivated();
    error InvalidHolderAccountingStartTimestamp(uint64 startTimestamp, uint256 blockTimestamp);
    error HolderAccountingNotActivated();
    error UnauthorizedHolderContextController(address caller, address expected);
    error FutureSnapshotBlock(uint48 snapshotBlock, uint256 currentBlock);
    error SnapshotTimestampInFuture(uint64 snapshotTimestamp, uint256 blockTimestamp);
    error SnapshotBeforeHolderAccountingStart(uint64 snapshotTimestamp, uint64 startTimestamp);
    error BlockNumberTooLarge(uint256 blockNumber);
    error InconsistentEligibleBuckets(address account, uint256 eligibleTotal, uint256 prelaunch, uint256 immatureSum);
    error CheckpointWriteMismatch(uint208 previous, uint208 expected, uint208 actual);
    error InvalidContextId(uint256 contextId);
    error InvalidHolderContextStatus(uint256 contextId, HolderContextStatus status);
    error ActivePotentialContextExists(uint256 contextId);
    error ActiveCandidateContextExists(uint256 contextId);
    error PotentialContextAlreadyOpenedForEpoch(uint64 epochId, uint256 contextId);
    error InvalidContextSnapshotBlock(uint48 snapshotBlock, uint256 expectedSnapshotBlock);
    error InvalidContextSnapshotTimestamp(uint64 snapshotTimestamp, uint256 expectedTimestamp);
    error ContextEpochMismatch(uint256 expectedEpochId, uint256 actualEpochId);
    error InvalidContextExpiry(uint256 epochId, uint256 expiresAtEpochId);
    error InvalidConfirmationEpoch(uint256 confirmationEpochId, uint256 epochId, uint256 expiresAtEpochId);
    error InvalidCutoffTimestamp(uint64 cutoffTimestamp, uint256 expectedCutoffTimestamp);
    error ConfirmationEpochNotClosed(uint64 confirmationEpochId, uint256 liveEpochId);
    error ContextScanTooWide(uint64 startHour, uint64 endHour);

    constructor(
        string memory name_,
        string memory symbol_,
        address initialRecipient,
        uint256 initialSupply,
        address holderAccountingActivator_,
        address[] memory rewardExcludedAddresses,
        address[] memory protocolTransferExemptAddresses,
        uint16[169] memory multiplierBpsByAgeBucket_
    ) ERC20(name_, symbol_) {
        if (initialRecipient == address(0)) revert ZeroInitialRecipient();
        if (initialSupply == 0) revert ZeroInitialSupply();
        if (initialSupply > type(uint208).max) revert InitialSupplyTooLarge(initialSupply);
        if (holderAccountingActivator_ == address(0)) revert ZeroHolderAccountingActivator();

        _loadRewardExclusions(rewardExcludedAddresses);
        _loadProtocolTransferExemptions(protocolTransferExemptAddresses);
        bytes32 tableHash = _loadMultiplierTable(multiplierBpsByAgeBucket_);

        holderAccountingActivator = holderAccountingActivator_;
        multiplierTableHash = tableHash;

        emit MultiplierTableLoaded(tableHash);
        _mint(initialRecipient, initialSupply);
    }

    function activateHolderAccounting(uint64 startTimestamp) external {
        if (msg.sender != holderAccountingActivator) {
            revert UnauthorizedHolderAccountingActivator(msg.sender, holderAccountingActivator);
        }
        if (holderAccountingStartTimestamp != 0) revert HolderAccountingAlreadyActivated();
        if (startTimestamp == 0 || startTimestamp < block.timestamp) {
            revert InvalidHolderAccountingStartTimestamp(startTimestamp, block.timestamp);
        }

        holderAccountingStartTimestamp = startTimestamp;
        emit HolderAccountingActivated(startTimestamp);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function currentTransferSeq() external view returns (uint256) {
        return transferSeq;
    }

    function holderContextController() external view returns (address) {
        return holderAccountingActivator;
    }

    function holderEpochId(uint64 timestamp) public view returns (uint256) {
        uint64 startTimestamp = holderAccountingStartTimestamp;
        if (startTimestamp == 0) revert HolderAccountingNotActivated();
        if (timestamp < startTimestamp) revert SnapshotBeforeHolderAccountingStart(timestamp, startTimestamp);
        return (uint256(timestamp) - startTimestamp) / EPOCH_LENGTH;
    }

    function multiplierBpsByAgeBucket(uint256 ageBucket) external view returns (uint16) {
        if (ageBucket > MATURE_BUCKET) return MAX_MULTIPLIER_BPS;
        return _multiplierBpsByAgeBucket[ageBucket];
    }

    function accountEligibleBalance(address account) external view returns (uint256) {
        return _accountEligibleTotal[account].latest();
    }

    function globalEligibleBalance() external view returns (uint256) {
        return _globalEligibleTotal.latest();
    }

    function accountPrelaunchEligible(address account) external view returns (uint256) {
        return _accountPrelaunchEligible[account].latest();
    }

    function globalPrelaunchEligible() external view returns (uint256) {
        return _globalPrelaunchEligible.latest();
    }

    function accountBucketEligible(address account, uint64 acquisitionHour) external view returns (uint256) {
        return _accountBucketEligible[account][acquisitionHour].latest();
    }

    function globalBucketEligible(uint64 acquisitionHour) external view returns (uint256) {
        return _globalBucketEligible[acquisitionHour].latest();
    }

    function holderContext(uint256 contextId) external view returns (HolderContext memory) {
        _requireContextExists(contextId);
        return _holderContexts[contextId];
    }

    function accountDisqualificationForContext(address account, uint256 contextId)
        public
        view
        returns (AccountContextDisqualification memory disqualification)
    {
        _requireContextExists(contextId);
        disqualification = _accountContextDisqualifications[contextId][account];
        if (disqualification.exists) return disqualification;

        HolderContext memory context = _holderContexts[contextId];
        AccountContextDisqualification memory preOpen = _preOpenDisqualifications[context.openBlock][account];
        if (preOpen.exists && preOpen.decreaseSeq < context.openSeq) return preOpen;
    }

    function contextDisqualificationExists(address account, uint256 contextId) external view returns (bool) {
        return accountDisqualificationForContext(account, contextId).exists;
    }

    function isAccountDisqualifiedForConfirmation(address account, uint256 contextId, uint256 confirmationEpochId)
        external
        view
        returns (bool)
    {
        AccountContextDisqualification memory disqualification = accountDisqualificationForContext(account, contextId);
        return disqualification.exists && disqualification.decreaseEpochId <= confirmationEpochId;
    }

    function disqualifiedWeightForEpoch(uint256 contextId, uint256 epochId) external view returns (uint256) {
        _requireContextExists(contextId);
        return _disqualifiedWeightByEpoch[contextId][epochId];
    }

    function finalDisqualifiedWeight(uint256 contextId) external view returns (uint256) {
        _requireContextExists(contextId);
        return _holderContexts[contextId].finalDisqualifiedWeight;
    }

    function openPotentialHolderContext(
        uint64 epochId,
        uint48 snapshotBlock,
        uint64 snapshotTimestamp,
        uint64 expiresAtEpochId
    ) external returns (uint256 contextId) {
        _requireContextController();
        _validateAtomicContextOpen(epochId, snapshotBlock, snapshotTimestamp, expiresAtEpochId);
        if (currentPotentialContextId != 0) revert ActivePotentialContextExists(currentPotentialContextId);
        uint256 openedContextId = potentialContextOpenedForEpoch[epochId];
        if (openedContextId != 0) revert PotentialContextAlreadyOpenedForEpoch(epochId, openedContextId);

        contextId = nextHolderContextId++;
        potentialContextOpenedForEpoch[epochId] = contextId;
        uint48 openBlock = _currentCheckpointKey();
        uint256 openSeq = transferSeq + 1;
        _holderContexts[contextId] = HolderContext({
            status: HolderContextStatus.Potential,
            epochId: epochId,
            snapshotBlock: snapshotBlock,
            snapshotTimestamp: snapshotTimestamp,
            openBlock: openBlock,
            openSeq: openSeq,
            expiresAtEpochId: expiresAtEpochId,
            confirmationEpochId: 0,
            cutoffTimestamp: 0,
            processingSeq: 0,
            finalDisqualifiedWeight: 0
        });
        currentPotentialContextId = contextId;

        uint256 preOpenWeight = preOpenDisqualifiedWeightByBlock[block.number];
        if (preOpenWeight != 0) {
            _disqualifiedWeightByEpoch[contextId][epochId] += preOpenWeight;
            preOpenDisqualifiedWeightByBlock[block.number] = 0;
        }

        emit HolderContextOpened(contextId, epochId, snapshotBlock, snapshotTimestamp, expiresAtEpochId);
    }

    function promotePotentialHolderContext(uint256 contextId) external {
        _requireContextController();
        HolderContext storage context = _requireContextStatus(contextId, HolderContextStatus.Potential);
        if (contextId != currentPotentialContextId) revert InvalidContextId(contextId);
        if (activeCandidateContextId != 0) revert ActiveCandidateContextExists(activeCandidateContextId);

        context.status = HolderContextStatus.Candidate;
        currentPotentialContextId = 0;
        activeCandidateContextId = contextId;
        emit HolderContextPromoted(contextId, context.epochId);
    }

    function discardHolderContext(uint256 contextId) external {
        _requireContextController();
        HolderContext storage context = _requireContextExists(contextId);
        HolderContextStatus previousStatus = context.status;
        if (previousStatus == HolderContextStatus.Potential) {
            if (currentPotentialContextId != contextId) revert InvalidContextId(contextId);
            currentPotentialContextId = 0;
        } else if (previousStatus == HolderContextStatus.Candidate) {
            if (activeCandidateContextId != contextId) revert InvalidContextId(contextId);
            activeCandidateContextId = 0;
        } else {
            revert InvalidHolderContextStatus(contextId, previousStatus);
        }

        context.status = HolderContextStatus.Discarded;
        emit HolderContextDiscarded(contextId, previousStatus);
    }

    /// @dev Closes the holder context after its confirmation epoch has passed. The final
    /// disqualified weight is subtracted from the snapshot denominator before rewards are reserved.
    function closeHolderContext(uint256 contextId, uint64 confirmationEpochId, uint64 cutoffTimestamp)
        external
        returns (uint256 disqualifiedWeight)
    {
        _requireContextController();
        HolderContext storage context = _requireContextStatus(contextId, HolderContextStatus.Candidate);
        if (activeCandidateContextId != contextId) revert InvalidContextId(contextId);
        if (confirmationEpochId <= context.epochId || confirmationEpochId > context.expiresAtEpochId) {
            revert InvalidConfirmationEpoch(confirmationEpochId, context.epochId, context.expiresAtEpochId);
        }

        uint256 expectedCutoffTimestamp =
            uint256(holderAccountingStartTimestamp) + (uint256(confirmationEpochId) + 1) * EPOCH_LENGTH;
        if (cutoffTimestamp != expectedCutoffTimestamp) {
            revert InvalidCutoffTimestamp(cutoffTimestamp, expectedCutoffTimestamp);
        }
        uint256 liveEpochId = holderEpochId(uint64(block.timestamp));
        if (liveEpochId <= confirmationEpochId) {
            revert ConfirmationEpochNotClosed(confirmationEpochId, liveEpochId);
        }

        for (uint256 epochId = context.epochId; epochId <= confirmationEpochId; epochId++) {
            disqualifiedWeight += _disqualifiedWeightByEpoch[contextId][epochId];
        }

        context.status = HolderContextStatus.Closed;
        context.confirmationEpochId = confirmationEpochId;
        context.cutoffTimestamp = cutoffTimestamp;
        context.processingSeq = transferSeq;
        context.finalDisqualifiedWeight = disqualifiedWeight;
        activeCandidateContextId = 0;

        emit HolderContextClosed(contextId, confirmationEpochId, cutoffTimestamp, transferSeq, disqualifiedWeight);
    }

    /// @notice Returns one account's weighted holder balance at a historical snapshot.
    /// @dev The `(snapshotBlock, snapshotTimestamp)` pair is authoritative only when it comes from
    /// an atomically stored protocol holder context. Public callers can pass inconsistent pairs and
    /// receive diagnostic-only output.
    function accountWeightAtSnapshot(address account, uint48 snapshotBlock, uint64 snapshotTimestamp)
        public
        view
        returns (uint256)
    {
        _validateSnapshot(snapshotBlock, snapshotTimestamp);
        if (_isExcludedFromHolderWeight(account)) return 0;

        uint256 total = _accountEligibleTotal[account].upperLookupRecent(snapshotBlock);
        if (total == 0) return 0;

        (uint256 prelaunch, uint256 immatureSum, uint256 immatureWeight) =
            _accountImmatureWeightAt(account, snapshotBlock, snapshotTimestamp);
        if (prelaunch + immatureSum > total) {
            revert InconsistentEligibleBuckets(account, total, prelaunch, immatureSum);
        }

        uint256 prelaunchWeight = _prelaunchWeight(prelaunch, snapshotTimestamp);
        uint256 mature = total - prelaunch - immatureSum;
        return prelaunchWeight + immatureWeight + _weightedAmount(mature, MAX_MULTIPLIER_BPS);
    }

    /// @notice Returns the global weighted holder denominator at a historical snapshot.
    /// @dev The `(snapshotBlock, snapshotTimestamp)` pair is authoritative only when it comes from
    /// an atomically stored protocol holder context. Public callers can pass inconsistent pairs and
    /// receive diagnostic-only output.
    function globalWeightAtSnapshot(uint48 snapshotBlock, uint64 snapshotTimestamp) public view returns (uint256) {
        _validateSnapshot(snapshotBlock, snapshotTimestamp);

        uint256 total = _globalEligibleTotal.upperLookupRecent(snapshotBlock);
        if (total == 0) return 0;

        (uint256 prelaunch, uint256 immatureSum, uint256 immatureWeight) =
            _globalImmatureWeightAt(snapshotBlock, snapshotTimestamp);
        if (prelaunch + immatureSum > total) {
            revert InconsistentEligibleBuckets(address(0), total, prelaunch, immatureSum);
        }

        uint256 prelaunchWeight = _prelaunchWeight(prelaunch, snapshotTimestamp);
        uint256 mature = total - prelaunch - immatureSum;
        return prelaunchWeight + immatureWeight + _weightedAmount(mature, MAX_MULTIPLIER_BPS);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (value == 0 || from == to) {
            super._update(from, to, value);
            return;
        }

        uint256 recipientBalanceBefore = to == address(0) ? 0 : balanceOf(to);

        if (from != address(0)) {
            _recordOutgoing(from);
        }
        if (to != address(0)) {
            _recordIncoming(to, recipientBalanceBefore, value);
        }

        super._update(from, to, value);
    }

    function _loadRewardExclusions(address[] memory rewardExcludedAddresses) private {
        if (rewardExcludedAddresses.length > MAX_CONFIG_ADDRESSES) {
            revert TooManyConfigAddresses(rewardExcludedAddresses.length);
        }

        for (uint256 i = 0; i < rewardExcludedAddresses.length; i++) {
            address account = rewardExcludedAddresses[i];
            if (account == address(0)) revert ZeroConfigAddress();
            if (isRewardExcludedAddress[account]) revert DuplicateConfigAddress(account);
            isRewardExcludedAddress[account] = true;
        }
    }

    function _loadProtocolTransferExemptions(address[] memory protocolTransferExemptAddresses) private {
        if (protocolTransferExemptAddresses.length > MAX_CONFIG_ADDRESSES) {
            revert TooManyConfigAddresses(protocolTransferExemptAddresses.length);
        }

        for (uint256 i = 0; i < protocolTransferExemptAddresses.length; i++) {
            address account = protocolTransferExemptAddresses[i];
            if (account == address(0)) revert ZeroConfigAddress();
            if (isProtocolTransferExemptAddress[account]) revert DuplicateConfigAddress(account);
            if (!isRewardExcludedAddress[account]) revert ProtocolExemptNotRewardExcluded(account);
            isProtocolTransferExemptAddress[account] = true;
        }
    }

    function _loadMultiplierTable(uint16[169] memory multiplierBpsByAgeBucket_) private returns (bytes32 tableHash) {
        for (uint256 i = 0; i < SNAPSHOT_BUCKETS; i++) {
            uint16 value = multiplierBpsByAgeBucket_[i];
            if (value > MAX_MULTIPLIER_BPS) revert InvalidMultiplierTable(i, value);
            if (i == 0 && value != BASE_MULTIPLIER_BPS) revert InvalidMultiplierTable(i, value);
            if (i == MATURE_BUCKET && value != MAX_MULTIPLIER_BPS) revert InvalidMultiplierTable(i, value);
            if (i > 0 && value < multiplierBpsByAgeBucket_[i - 1]) revert InvalidMultiplierTable(i, value);
            _multiplierBpsByAgeBucket[i] = value;
        }

        tableHash = keccak256(abi.encode(multiplierBpsByAgeBucket_));
    }

    function _recordOutgoing(address from) private {
        if (_isExcludedFromHolderWeight(from) || firstDecreaseSeqPlusOne[from] != 0) return;

        uint256 newSeq = ++transferSeq;
        uint64 firstDecreaseBlockPlusOneValue = (block.number + 1).toUint64();
        firstDecreaseSeqPlusOne[from] = newSeq + 1;
        firstDecreaseBlockPlusOne[from] = firstDecreaseBlockPlusOneValue;

        _recordDisqualificationsAndRemoveEligibleBalance(from, newSeq);
        emit FirstDecreaseRecorded(from, newSeq, firstDecreaseBlockPlusOneValue);
    }

    function _recordIncoming(address to, uint256 recipientBalanceBefore, uint256 value) private {
        if (_isExcludedFromHolderWeight(to) || firstDecreaseSeqPlusOne[to] != 0) return;

        if (recipientBalanceBefore == 0 && firstHeldBlock[to] == 0) {
            firstHeldBlock[to] = block.number.toUint64();
        }

        _addEligibleBalance(to, value);
    }

    function _addEligibleBalance(address account, uint256 amount) private {
        uint208 castAmount = amount.toUint208();
        uint48 key = _currentCheckpointKey();

        _pushAccountEligibleTotal(account, key, uint256(_accountEligibleTotal[account].latest()) + castAmount);
        _pushGlobalEligibleTotal(key, uint256(_globalEligibleTotal.latest()) + castAmount);

        uint64 startTimestamp = holderAccountingStartTimestamp;
        if (startTimestamp == 0 || block.timestamp < startTimestamp) {
            _pushAccountPrelaunch(account, key, uint256(_accountPrelaunchEligible[account].latest()) + castAmount);
            _pushGlobalPrelaunch(key, uint256(_globalPrelaunchEligible.latest()) + castAmount);
            return;
        }

        uint64 acquisitionHour = _hourBucket(block.timestamp);
        _pushAccountBucket(
            account,
            acquisitionHour,
            key,
            uint256(_accountBucketEligible[account][acquisitionHour].latest()) + castAmount
        );
        _pushGlobalBucket(acquisitionHour, key, uint256(_globalBucketEligible[acquisitionHour].latest()) + castAmount);
    }

    function _recordDisqualificationsAndRemoveEligibleBalance(address account, uint256 decreaseSeq) private {
        bool contextAccountingActive = holderAccountingStartTimestamp != 0
            && block.timestamp >= holderAccountingStartTimestamp && block.number != 0;
        uint256 currentEpochId = contextAccountingActive ? holderEpochId(uint64(block.timestamp)) : 0;
        SnapshotWeightRequest[] memory requests = new SnapshotWeightRequest[](3);
        uint256 requestCount = 0;

        if (contextAccountingActive && _shouldRecordPreOpen(currentEpochId)) {
            requestCount = _addSnapshotWeightRequest(
                requests, requestCount, 0, true, uint48(block.number - 1), uint64(block.timestamp)
            );
        }
        if (contextAccountingActive) {
            requestCount = _addActiveContextRequest(requests, requestCount, currentPotentialContextId, currentEpochId);
            requestCount = _addActiveContextRequest(requests, requestCount, activeCandidateContextId, currentEpochId);
        }

        _processSharedAccountScan(account, requests, requestCount);

        for (uint256 i = 0; i < requestCount; i++) {
            uint256 weight = _requestWeight(requests[i]);
            if (requests[i].preOpen) {
                if (weight == 0) continue;
                AccountContextDisqualification storage preOpen = _preOpenDisqualifications[block.number][account];
                preOpen.exists = true;
                preOpen.decreaseEpochId = currentEpochId.toUint64();
                preOpen.decreaseSeq = decreaseSeq;
                preOpen.snapshotWeight = weight;
                preOpenDisqualifiedWeightByBlock[block.number] += weight;
                emit PreOpenDisqualificationRecorded(
                    block.number, account, currentEpochId.toUint64(), decreaseSeq, weight
                );
                continue;
            }

            _storeContextDisqualification(
                requests[i].contextId, account, currentEpochId.toUint64(), decreaseSeq, weight
            );
        }
    }

    function _processSharedAccountScan(address account, SnapshotWeightRequest[] memory requests, uint256 requestCount)
        private
    {
        uint208 total = _accountEligibleTotal[account].latest();
        uint208 prelaunch = _accountPrelaunchEligible[account].latest();
        bool removeLiveEligible = total != 0;
        uint48 key = _currentCheckpointKey();
        uint256 immatureSum = 0;
        bool hasScan = false;
        uint64 scanStartHour = 0;
        uint64 scanEndHour = 0;

        uint64 currentHour = _hourBucket(block.timestamp);
        if (removeLiveEligible) {
            (scanStartHour, scanEndHour, hasScan) = _includeScanPeriod(scanStartHour, scanEndHour, hasScan, currentHour);
        }

        for (uint256 i = 0; i < requestCount; i++) {
            requests[i].snapshotHour = _hourBucket(requests[i].snapshotTimestamp);
            requests[i].total = _accountEligibleTotal[account].upperLookupRecent(requests[i].snapshotBlock);
            if (requests[i].total != 0) {
                requests[i].prelaunch = _accountPrelaunchEligible[account].upperLookupRecent(requests[i].snapshotBlock);
                (scanStartHour, scanEndHour, hasScan) =
                    _includeScanPeriod(scanStartHour, scanEndHour, hasScan, requests[i].snapshotHour);
            }
        }

        if (hasScan) {
            if (uint256(scanEndHour) - scanStartHour + 1 > IMMATURE_BUCKETS + 2) {
                revert ContextScanTooWide(scanStartHour, scanEndHour);
            }

            uint256 scanSpan = uint256(scanEndHour) - scanStartHour;
            for (uint256 scanOffset = 0; scanOffset <= scanSpan; scanOffset++) {
                uint64 acquisitionHour = (uint256(scanStartHour) + scanOffset).toUint64();
                if (removeLiveEligible && _hourInPeriod(acquisitionHour, currentHour)) {
                    uint208 bucketAmount = _accountBucketEligible[account][acquisitionHour].latest();
                    if (bucketAmount != 0) {
                        immatureSum += bucketAmount;
                        _pushAccountBucket(account, acquisitionHour, key, 0);
                        _pushGlobalBucket(
                            acquisitionHour,
                            key,
                            uint256(_globalBucketEligible[acquisitionHour].latest()) - bucketAmount
                        );
                    }
                }

                for (uint256 requestIndex = 0; requestIndex < requestCount; requestIndex++) {
                    if (
                        requests[requestIndex].total == 0
                            || !_hourInPeriod(acquisitionHour, requests[requestIndex].snapshotHour)
                    ) {
                        continue;
                    }

                    uint256 amount = _accountBucketEligible[account][acquisitionHour].upperLookupRecent(
                        requests[requestIndex].snapshotBlock
                    );
                    uint256 ageBucket = requests[requestIndex].snapshotHour - acquisitionHour;
                    requests[requestIndex].immatureSum += amount;
                    requests[requestIndex].immatureWeight += _weightedAmount(
                        amount, _multiplierBpsByAgeBucket[ageBucket]
                    );
                }
            }
        }

        if (removeLiveEligible && uint256(prelaunch) + immatureSum > total) {
            revert InconsistentEligibleBuckets(account, total, prelaunch, immatureSum);
        }

        for (uint256 i = 0; i < requestCount; i++) {
            if (requests[i].prelaunch + requests[i].immatureSum > requests[i].total) {
                revert InconsistentEligibleBuckets(
                    account, requests[i].total, requests[i].prelaunch, requests[i].immatureSum
                );
            }
        }

        if (!removeLiveEligible) return;

        if (prelaunch != 0) {
            _pushAccountPrelaunch(account, key, 0);
            _pushGlobalPrelaunch(key, uint256(_globalPrelaunchEligible.latest()) - prelaunch);
        }

        _pushAccountEligibleTotal(account, key, 0);
        _pushGlobalEligibleTotal(key, uint256(_globalEligibleTotal.latest()) - total);
    }

    function _addActiveContextRequest(
        SnapshotWeightRequest[] memory requests,
        uint256 requestCount,
        uint256 contextId,
        uint256 currentEpochId
    ) private view returns (uint256) {
        if (contextId == 0) return requestCount;
        HolderContext storage context = _holderContexts[contextId];
        if (
            context.status != HolderContextStatus.Potential && context.status != HolderContextStatus.Candidate
                || currentEpochId > context.expiresAtEpochId
        ) {
            return requestCount;
        }

        return _addSnapshotWeightRequest(
            requests, requestCount, contextId, false, context.snapshotBlock, context.snapshotTimestamp
        );
    }

    function _addSnapshotWeightRequest(
        SnapshotWeightRequest[] memory requests,
        uint256 requestCount,
        uint256 contextId,
        bool preOpen,
        uint48 snapshotBlock,
        uint64 snapshotTimestamp
    ) private pure returns (uint256) {
        requests[requestCount].active = true;
        requests[requestCount].contextId = contextId;
        requests[requestCount].preOpen = preOpen;
        requests[requestCount].snapshotBlock = snapshotBlock;
        requests[requestCount].snapshotTimestamp = snapshotTimestamp;
        return requestCount + 1;
    }

    function _shouldRecordPreOpen(uint256 currentEpochId) private view returns (bool) {
        uint256 potentialContextId = currentPotentialContextId;
        if (potentialContextId == 0) return true;

        HolderContext storage context = _holderContexts[potentialContextId];
        return context.status == HolderContextStatus.Potential && currentEpochId > context.epochId;
    }

    function _storeContextDisqualification(
        uint256 contextId,
        address account,
        uint64 decreaseEpochId,
        uint256 decreaseSeq,
        uint256 snapshotWeight
    ) private {
        AccountContextDisqualification storage disqualification = _accountContextDisqualifications[contextId][account];
        if (disqualification.exists) return;

        disqualification.exists = true;
        disqualification.decreaseEpochId = decreaseEpochId;
        disqualification.decreaseSeq = decreaseSeq;
        disqualification.snapshotWeight = snapshotWeight;
        _disqualifiedWeightByEpoch[contextId][decreaseEpochId] += snapshotWeight;
        emit ContextDisqualificationRecorded(contextId, account, decreaseEpochId, decreaseSeq, snapshotWeight);
    }

    function _requestWeight(SnapshotWeightRequest memory request) private view returns (uint256) {
        if (request.total == 0) return 0;
        uint256 prelaunchWeight = _prelaunchWeight(request.prelaunch, request.snapshotTimestamp);
        uint256 mature = request.total - request.prelaunch - request.immatureSum;
        return prelaunchWeight + request.immatureWeight + _weightedAmount(mature, MAX_MULTIPLIER_BPS);
    }

    function _includeScanPeriod(uint64 startHour, uint64 endHour, bool hasScan, uint64 periodEndHour)
        private
        pure
        returns (uint64 newStartHour, uint64 newEndHour, bool newHasScan)
    {
        uint64 periodStartHour = _periodStartHour(periodEndHour);
        if (!hasScan) return (periodStartHour, periodEndHour, true);
        if (periodStartHour < startHour) startHour = periodStartHour;
        if (periodEndHour > endHour) endHour = periodEndHour;
        return (startHour, endHour, true);
    }

    function _periodStartHour(uint64 endHour) private pure returns (uint64) {
        uint256 lastImmatureOffset = IMMATURE_BUCKETS - 1;
        if (endHour <= lastImmatureOffset) return 0;
        return endHour - lastImmatureOffset.toUint64();
    }

    function _hourInPeriod(uint64 acquisitionHour, uint64 periodEndHour) private pure returns (bool) {
        return acquisitionHour <= periodEndHour && acquisitionHour >= _periodStartHour(periodEndHour);
    }

    function _accountImmatureWeightAt(address account, uint48 snapshotBlock, uint64 snapshotTimestamp)
        private
        view
        returns (uint256 prelaunch, uint256 immatureSum, uint256 immatureWeight)
    {
        prelaunch = _accountPrelaunchEligible[account].upperLookupRecent(snapshotBlock);
        uint64 snapshotHour = _hourBucket(snapshotTimestamp);

        for (uint256 ageBucket = 0; ageBucket < IMMATURE_BUCKETS; ageBucket++) {
            if (ageBucket > snapshotHour) break;
            uint64 acquisitionHour = snapshotHour - ageBucket.toUint64();
            uint256 amount = _accountBucketEligible[account][acquisitionHour].upperLookupRecent(snapshotBlock);
            immatureSum += amount;
            immatureWeight += _weightedAmount(amount, _multiplierBpsByAgeBucket[ageBucket]);
        }
    }

    function _globalImmatureWeightAt(uint48 snapshotBlock, uint64 snapshotTimestamp)
        private
        view
        returns (uint256 prelaunch, uint256 immatureSum, uint256 immatureWeight)
    {
        prelaunch = _globalPrelaunchEligible.upperLookupRecent(snapshotBlock);
        uint64 snapshotHour = _hourBucket(snapshotTimestamp);

        for (uint256 ageBucket = 0; ageBucket < IMMATURE_BUCKETS; ageBucket++) {
            if (ageBucket > snapshotHour) break;
            uint64 acquisitionHour = snapshotHour - ageBucket.toUint64();
            uint256 amount = _globalBucketEligible[acquisitionHour].upperLookupRecent(snapshotBlock);
            immatureSum += amount;
            immatureWeight += _weightedAmount(amount, _multiplierBpsByAgeBucket[ageBucket]);
        }
    }

    function _prelaunchWeight(uint256 amount, uint64 snapshotTimestamp) private view returns (uint256) {
        if (amount == 0) return 0;

        uint64 startTimestamp = holderAccountingStartTimestamp;
        uint256 ageBucket = (snapshotTimestamp - startTimestamp) / BUCKET_SIZE;
        if (ageBucket > MATURE_BUCKET) ageBucket = MATURE_BUCKET;
        return _weightedAmount(amount, _multiplierBpsByAgeBucket[ageBucket]);
    }

    function _weightedAmount(uint256 amount, uint256 multiplierBps) private pure returns (uint256) {
        return amount * multiplierBps / BPS_DENOMINATOR;
    }

    function _validateSnapshot(uint48 snapshotBlock, uint64 snapshotTimestamp) private view {
        uint64 startTimestamp = holderAccountingStartTimestamp;
        if (startTimestamp == 0) revert HolderAccountingNotActivated();
        if (snapshotBlock > block.number) revert FutureSnapshotBlock(snapshotBlock, block.number);
        if (snapshotTimestamp > block.timestamp) revert SnapshotTimestampInFuture(snapshotTimestamp, block.timestamp);
        if (snapshotTimestamp < startTimestamp) {
            revert SnapshotBeforeHolderAccountingStart(snapshotTimestamp, startTimestamp);
        }
    }

    function _requireContextController() private view {
        if (msg.sender != holderAccountingActivator) {
            revert UnauthorizedHolderContextController(msg.sender, holderAccountingActivator);
        }
    }

    function _requireContextExists(uint256 contextId) private view returns (HolderContext storage context) {
        context = _holderContexts[contextId];
        if (context.status == HolderContextStatus.Invalid) revert InvalidContextId(contextId);
    }

    function _requireContextStatus(uint256 contextId, HolderContextStatus expected)
        private
        view
        returns (HolderContext storage context)
    {
        context = _requireContextExists(contextId);
        if (context.status != expected) revert InvalidHolderContextStatus(contextId, context.status);
    }

    function _validateAtomicContextOpen(
        uint64 epochId,
        uint48 snapshotBlock,
        uint64 snapshotTimestamp,
        uint64 expiresAtEpochId
    ) private view {
        if (holderAccountingStartTimestamp == 0) revert HolderAccountingNotActivated();
        if (block.number < 1 || block.number > type(uint48).max) revert BlockNumberTooLarge(block.number);

        uint256 expectedSnapshotBlock = block.number - 1;
        if (snapshotBlock != expectedSnapshotBlock) {
            revert InvalidContextSnapshotBlock(snapshotBlock, expectedSnapshotBlock);
        }
        if (snapshotTimestamp != block.timestamp) {
            revert InvalidContextSnapshotTimestamp(snapshotTimestamp, block.timestamp);
        }

        uint256 actualEpochId = holderEpochId(snapshotTimestamp);
        if (actualEpochId != epochId) revert ContextEpochMismatch(epochId, actualEpochId);
        if (expiresAtEpochId <= epochId || expiresAtEpochId > epochId + MAX_CONTEXT_EXPIRY_EPOCHS) {
            revert InvalidContextExpiry(epochId, expiresAtEpochId);
        }
    }

    function _isExcludedFromHolderWeight(address account) private view returns (bool) {
        return isRewardExcludedAddress[account] || isProtocolTransferExemptAddress[account];
    }

    function _hourBucket(uint256 timestamp) private pure returns (uint64) {
        return (timestamp / BUCKET_SIZE).toUint64();
    }

    function _currentCheckpointKey() internal view returns (uint48) {
        if (block.number > type(uint48).max) revert BlockNumberTooLarge(block.number);
        return uint48(block.number);
    }

    function _pushAccountEligibleTotal(address account, uint48 key, uint256 value) private {
        uint208 castValue = value.toUint208();
        (uint208 previous, uint208 actual) = _accountEligibleTotal[account].push(key, castValue);
        if (actual != castValue) revert CheckpointWriteMismatch(previous, castValue, actual);
    }

    function _pushGlobalEligibleTotal(uint48 key, uint256 value) private {
        uint208 castValue = value.toUint208();
        (uint208 previous, uint208 actual) = _globalEligibleTotal.push(key, castValue);
        if (actual != castValue) revert CheckpointWriteMismatch(previous, castValue, actual);
    }

    function _pushAccountPrelaunch(address account, uint48 key, uint256 value) private {
        uint208 castValue = value.toUint208();
        (uint208 previous, uint208 actual) = _accountPrelaunchEligible[account].push(key, castValue);
        if (actual != castValue) revert CheckpointWriteMismatch(previous, castValue, actual);
    }

    function _pushGlobalPrelaunch(uint48 key, uint256 value) private {
        uint208 castValue = value.toUint208();
        (uint208 previous, uint208 actual) = _globalPrelaunchEligible.push(key, castValue);
        if (actual != castValue) revert CheckpointWriteMismatch(previous, castValue, actual);
    }

    function _pushAccountBucket(address account, uint64 acquisitionHour, uint48 key, uint256 value) private {
        uint208 castValue = value.toUint208();
        (uint208 previous, uint208 actual) = _accountBucketEligible[account][acquisitionHour].push(key, castValue);
        if (actual != castValue) revert CheckpointWriteMismatch(previous, castValue, actual);
    }

    function _pushGlobalBucket(uint64 acquisitionHour, uint48 key, uint256 value) private {
        uint208 castValue = value.toUint208();
        (uint208 previous, uint208 actual) = _globalBucketEligible[acquisitionHour].push(key, castValue);
        if (actual != castValue) revert CheckpointWriteMismatch(previous, castValue, actual);
    }
}
