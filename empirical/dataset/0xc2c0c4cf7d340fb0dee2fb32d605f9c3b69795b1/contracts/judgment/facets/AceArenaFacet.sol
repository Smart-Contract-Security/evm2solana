// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../diamond/libraries/LibDiamond.sol";
import "../../interfaces/IAceDataQuality.sol";
import "../../interfaces/IJudgmentObligationController.sol";
import "../../interfaces/IJudgmentOracleAdapter.sol";
import "../../interfaces/IPoolVault.sol";
import "../libraries/LibArenaStorage.sol";

contract AceArenaFacet {
    using Math for uint256;
    using LibArenaStorage for LibArenaStorage.ArenaStorage;

    uint256 public constant ROUND_DURATION = 300;
    uint256 public constant ENTRY_LOCK_OFFSET = 240;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant TIE_THRESHOLD_BP = 1;
    uint256 public constant UP_DOWN_PAYOUT_RATE_BPS = 9_500;
    uint256 public constant TIE_PAYOUT_RATE_BPS = 7_500;
    uint256 public constant START_UP_POOL_BPS = 4_625;
    uint256 public constant START_DOWN_POOL_BPS = 4_625;
    uint256 public constant START_TIE_POOL_BPS = 750;
    uint256 public constant MAX_RESOLVE_BATCH = 32;
    uint256 public constant MAX_AUTO_RESOLVE_PER_COMMIT = 4;
    uint256 public constant MAX_JUDGMENT_ID_PAGE_SIZE = 256;
    uint256 public constant WAD = 1e18;
    uint256 public constant MIN_ETH_ENTRY_AMOUNT = 1 gwei;
    uint256 public constant MIN_USDC_ENTRY_AMOUNT = 1_000;
    uint8 public constant DEFAULT_DATA_QUALITY_TIER = 1;
    uint16 public constant DEFAULT_TIER_WEIGHT_BPS = 7_000;
    address private constant ETH_ASSET = address(0);

    event RoundStarted(
        uint256 indexed roundId,
        LibArenaStorage.MarketAsset marketAsset,
        uint256 startTime,
        uint256 lockTime,
        uint256 settleTime,
        uint256 openTwap,
        uint256 ethUsdReference,
        uint16 tieThresholdBp,
        uint16 upDownPayoutRateBps,
        uint16 tiePayoutRateBps,
        uint16 startUpPoolBps,
        uint16 startDownPoolBps,
        uint16 startTiePoolBps
    );
    // Seed fields are reserved for future protocol seed accounting; Phase 1 emits zero seed amounts.
    event RoundCapacitySeeded(
        uint256 indexed roundId,
        LibArenaStorage.EngineAsset asset,
        uint256 capacityAsset,
        uint256 capacityUsd,
        uint256 upSeedUsd,
        uint256 downSeedUsd,
        uint256 tieSeedUsd
    );
    event JudgmentCommitted(
        address indexed user,
        uint256 indexed roundId,
        uint256 indexed judgmentId,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction,
        uint256 amountAsset,
        uint256 notionalUsd,
        uint8 dataQualityTier,
        uint16 tierWeightBps
    );
    event RoundLocked(
        uint256 indexed roundId,
        uint256 upPoolUsd,
        uint256 downPoolUsd,
        uint256 tiePoolUsd,
        uint256 upEntryCount,
        uint256 downEntryCount,
        uint256 tieEntryCount,
        uint256 lockedAt
    );
    event RoundSettled(
        uint256 indexed roundId,
        LibArenaStorage.Direction winningSide,
        uint256 openPriceWad,
        uint256 finalPriceWad,
        uint256 winningPoolUsd,
        uint256 totalPoolUsd,
        uint256 edgeUsd,
        uint16 payoutRateBps,
        LibArenaStorage.SettlementMode settlementMode,
        uint256 settledAt
    );
    event RoundAssetSettled(
        uint256 indexed roundId,
        LibArenaStorage.EngineAsset asset,
        uint256 winningPoolUsd,
        uint256 totalPoolUsd,
        uint256 edgeUsd,
        uint16 payoutRateBps,
        uint256 finalMultiplierWad
    );
    event JudgmentResolved(
        address indexed user,
        uint256 indexed roundId,
        uint256 indexed judgmentId,
        LibArenaStorage.JudgmentResult result,
        LibArenaStorage.EngineAsset payoutAsset,
        uint256 payoutAmount,
        uint256 finalMultiplierWad
    );
    event AutoResolveCompleted(address indexed user, uint256 resolvedCount);
    event FirstJudgmentRecorded(
        address indexed user,
        uint256 indexed judgmentId,
        uint256 indexed roundId
    );
    event DataQualityUpdated(
        address indexed previousDataQuality,
        address indexed newDataQuality
    );
    event SettlementOperatorUpdated(address indexed operator, bool authorized);

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidRound();
    error RoundAlreadyStarted();
    error RoundLockedAlready();
    error RoundNotLocked();
    error RoundSettledAlready();
    error EntryLocked();
    error InvalidAssetTransfer();
    error RoundTooEarlyToLock();
    error RoundTooEarlyToSettle();
    error RoundNotSettled();
    error BatchTooLarge();
    error JudgmentAlreadyResolved();
    error NotJudgmentOwner();
    error OraclePriceInvalid();
    error InvalidDataQualityAttestation();
    error NotSettlementOperator();
    error InvalidRoundEconomics();
    error PageTooLarge();
    error InvalidAsset();
    error InvalidControllerBinding();
    error EntryAmountTooSmall();

    function initializeArena(
        address ethController,
        address usdcController,
        address oracle
    ) external {
        LibDiamond.enforceIsContractOwner();
        if (
            ethController == address(0) ||
            usdcController == address(0) ||
            oracle == address(0)
        ) {
            revert InvalidAddress();
        }
        if (oracle.code.length == 0) {
            revert InvalidAddress();
        }

        LibArenaStorage.ArenaStorage storage store = LibArenaStorage
            .arenaStorage();
        if (store.initialized) {
            revert AlreadyInitialized();
        }
        _validateControllerPair(ethController, usdcController);

        store.initialized = true;
        store.ethController = ethController;
        store.usdcController = usdcController;
        store.oracle = oracle;
        store.nextJudgmentId = 1;
    }

    function setDataQuality(address newDataQuality) external {
        LibDiamond.enforceIsContractOwner();
        LibArenaStorage.ArenaStorage storage store = _store();

        address previousDataQuality = store.dataQuality;
        store.dataQuality = newDataQuality;

        emit DataQualityUpdated(previousDataQuality, newDataQuality);
    }

    function setSettlementOperator(address operator, bool authorized) external {
        LibDiamond.enforceIsContractOwner();
        if (operator == address(0)) {
            revert InvalidAddress();
        }

        LibArenaStorage.ArenaStorage storage store = _store();
        store.settlementOperators[operator] = authorized;

        emit SettlementOperatorUpdated(operator, authorized);
    }

    function isSettlementOperator(
        address operator
    ) external view returns (bool) {
        LibDiamond.DiamondStorage storage diamondStore = LibDiamond
            .diamondStorage();
        if (operator == diamondStore.contractOwner) {
            return true;
        }

        return LibArenaStorage.arenaStorage().settlementOperators[operator];
    }

    function isArenaController(
        address controller
    ) external view returns (bool) {
        LibArenaStorage.ArenaStorage storage store = LibArenaStorage
            .arenaStorage();
        return
            controller != address(0) &&
            (controller == store.ethController ||
                controller == store.usdcController);
    }

    function startRound(uint256 roundId) external {
        _enforceSettlementOperator();
        bytes[] memory emptyPriceUpdateData = new bytes[](0);
        _startRound(roundId, emptyPriceUpdateData, 0);
    }

    function startRoundWithOracleData(
        uint256 roundId,
        bytes[] calldata priceUpdateData
    ) external payable {
        _enforceSettlementOperator();
        _startRound(roundId, priceUpdateData, msg.value);
    }

    function _startRound(
        uint256 roundId,
        bytes[] memory priceUpdateData,
        uint256 updateFee
    ) private {
        LibArenaStorage.ArenaStorage storage store = _store();
        if (roundId == 0) {
            revert InvalidRound();
        }
        _validateRoundEconomics();

        LibArenaStorage.Round storage round = store.rounds[roundId];
        if (round.started) {
            revert RoundAlreadyStarted();
        }

        (uint256 openTwap, uint256 ethUsdReference) = IJudgmentOracleAdapter(
            store.oracle
        ).getRoundStartPrices{value: updateFee}(priceUpdateData);
        if (openTwap == 0 || ethUsdReference == 0) {
            revert OraclePriceInvalid();
        }
        uint256 startTime_ = block.timestamp;

        round.startTime = startTime_;
        round.lockTime = startTime_ + ENTRY_LOCK_OFFSET;
        round.settleTime = startTime_ + ROUND_DURATION;
        round.openTwap = openTwap;
        round.ethUsdReference = ethUsdReference;
        round.started = true;
        round.marketAsset = LibArenaStorage.MarketAsset.BTC_ETH;
        round.tieThresholdBp = uint16(TIE_THRESHOLD_BP);
        round.upDownPayoutRateBps = uint16(UP_DOWN_PAYOUT_RATE_BPS);
        round.tiePayoutRateBps = uint16(TIE_PAYOUT_RATE_BPS);
        round.startUpPoolBps = uint16(START_UP_POOL_BPS);
        round.startDownPoolBps = uint16(START_DOWN_POOL_BPS);
        round.startTiePoolBps = uint16(START_TIE_POOL_BPS);

        uint256 ethCapacity = IJudgmentObligationController(store.ethController)
            .openRoundCapacity(roundId);
        uint256 usdcCapacity = IJudgmentObligationController(
            store.usdcController
        ).openRoundCapacity(roundId);
        round.ethCapacity = ethCapacity;
        round.usdcCapacity = usdcCapacity;

        emit RoundStarted(
            roundId,
            round.marketAsset,
            round.startTime,
            round.lockTime,
            round.settleTime,
            openTwap,
            ethUsdReference,
            round.tieThresholdBp,
            round.upDownPayoutRateBps,
            round.tiePayoutRateBps,
            round.startUpPoolBps,
            round.startDownPoolBps,
            round.startTiePoolBps
        );
        emit RoundCapacitySeeded(
            roundId,
            LibArenaStorage.EngineAsset.ETH,
            ethCapacity,
            _ethToUsd(ethCapacity, ethUsdReference),
            0,
            0,
            0
        );
        emit RoundCapacitySeeded(
            roundId,
            LibArenaStorage.EngineAsset.USDC,
            usdcCapacity,
            _usdcToUsd(usdcCapacity),
            0,
            0,
            0
        );
    }

    function commitJudgment(
        uint256 roundId,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction,
        uint256 amount
    ) external payable returns (uint256 judgmentId) {
        LibArenaStorage.ArenaStorage storage store = _store();
        judgmentId = _commitJudgment(
            store,
            roundId,
            entryAsset,
            direction,
            amount,
            DEFAULT_DATA_QUALITY_TIER,
            DEFAULT_TIER_WEIGHT_BPS
        );
    }

    function commitJudgmentWithAutoResolve(
        uint256 roundId,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction,
        uint256 amount,
        uint256[] calldata autoResolveJudgmentIds
    ) external payable returns (uint256 judgmentId) {
        LibArenaStorage.ArenaStorage storage store = _store();
        _resolveOwnedJudgments(
            store,
            autoResolveJudgmentIds,
            MAX_AUTO_RESOLVE_PER_COMMIT,
            true
        );

        judgmentId = _commitJudgment(
            store,
            roundId,
            entryAsset,
            direction,
            amount,
            DEFAULT_DATA_QUALITY_TIER,
            DEFAULT_TIER_WEIGHT_BPS
        );
    }

    function commitJudgmentWithDataQuality(
        uint256 roundId,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction,
        uint256 amount,
        IAceDataQuality.DataQualityAttestation calldata attestation,
        bytes calldata signature
    ) external payable returns (uint256 judgmentId) {
        LibArenaStorage.ArenaStorage storage store = _store();
        if (store.dataQuality == address(0)) {
            revert InvalidAddress();
        }
        if (attestation.user != msg.sender || attestation.roundId != roundId) {
            revert InvalidDataQualityAttestation();
        }

        (uint8 dataQualityTier, uint16 tierWeightBps) = IAceDataQuality(
            store.dataQuality
        ).consumeAttestation(attestation, signature);

        judgmentId = _commitJudgment(
            store,
            roundId,
            entryAsset,
            direction,
            amount,
            dataQualityTier,
            tierWeightBps
        );
    }

    function _commitJudgment(
        LibArenaStorage.ArenaStorage storage store,
        uint256 roundId,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction,
        uint256 amount,
        uint8 dataQualityTier,
        uint16 tierWeightBps
    ) private returns (uint256 judgmentId) {
        LibArenaStorage.Round storage round = store.rounds[roundId];
        if (!round.started || round.settled) {
            revert InvalidRound();
        }
        if (round.locked || block.timestamp >= round.lockTime) {
            revert EntryLocked();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }

        uint256 notionalUsd;

        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            if (amount < MIN_ETH_ENTRY_AMOUNT) {
                revert EntryAmountTooSmall();
            }
            if (msg.value != amount) {
                revert InvalidAssetTransfer();
            }
            notionalUsd = _ethToUsd(amount, round.ethUsdReference);
        } else {
            if (amount < MIN_USDC_ENTRY_AMOUNT) {
                revert EntryAmountTooSmall();
            }
            if (msg.value != 0) {
                revert InvalidAssetTransfer();
            }
            notionalUsd = _usdcToUsd(amount);
        }
        if (notionalUsd == 0) {
            revert InvalidAmount();
        }

        _addPool(round, entryAsset, direction, amount, notionalUsd);
        uint256 maxPayoutAmount = _assetCapacity(round, entryAsset);
        if (maxPayoutAmount == 0) {
            revert InvalidAmount();
        }
        uint256 reserveDelta = _aggregateReserveDelta(round, entryAsset);

        judgmentId = store.nextJudgmentId++;
        uint256[] storage judgmentIds = store.roundJudgmentIds[roundId];
        judgmentIds.push(judgmentId);
        store.judgments[judgmentId] = LibArenaStorage.Judgment({
            user: msg.sender,
            roundId: roundId,
            entryAsset: entryAsset,
            direction: direction,
            amountAsset: amount,
            notionalUsd: notionalUsd,
            maxReservedPayout: maxPayoutAmount,
            resolved: false
        });
        if (store.firstJudgmentIdByUser[msg.sender] == 0) {
            store.firstJudgmentIdByUser[msg.sender] = judgmentId;
            emit FirstJudgmentRecorded(msg.sender, judgmentId, roundId);
        }

        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            IJudgmentObligationController(store.ethController)
                .commitAggregateJudgmentEth{value: amount}(
                roundId,
                judgmentId,
                msg.sender,
                amount,
                maxPayoutAmount
            );
        } else {
            IJudgmentObligationController(store.usdcController)
                .commitAggregateJudgmentFromWallet(
                    roundId,
                    judgmentId,
                    msg.sender,
                    amount,
                    maxPayoutAmount
                );
        }

        _increaseAggregateReserve(
            store,
            roundId,
            round,
            entryAsset,
            reserveDelta
        );

        emit JudgmentCommitted(
            msg.sender,
            roundId,
            judgmentId,
            entryAsset,
            direction,
            amount,
            notionalUsd,
            dataQualityTier,
            tierWeightBps
        );
    }

    function lockRound(uint256 roundId) external {
        LibArenaStorage.ArenaStorage storage store = _store();
        LibArenaStorage.Round storage round = store.rounds[roundId];
        if (!round.started) {
            revert InvalidRound();
        }
        if (round.locked) {
            revert RoundLockedAlready();
        }
        if (block.timestamp < round.lockTime) {
            revert RoundTooEarlyToLock();
        }

        round.locked = true;
        round.lockedAt = block.timestamp;
        emit RoundLocked(
            roundId,
            round.upPoolUsd,
            round.downPoolUsd,
            round.tiePoolUsd,
            round.upEntryCount,
            round.downEntryCount,
            round.tieEntryCount,
            round.lockedAt
        );
    }

    function settleRound(uint256 roundId) external {
        _enforceSettlementOperator();
        bytes[] memory emptyPriceUpdateData = new bytes[](0);
        _settleRound(roundId, emptyPriceUpdateData, 0);
    }

    function settleRoundWithOracleData(
        uint256 roundId,
        bytes[] calldata priceUpdateData
    ) external payable {
        _enforceSettlementOperator();
        _settleRound(roundId, priceUpdateData, msg.value);
    }

    function _settleRound(
        uint256 roundId,
        bytes[] memory priceUpdateData,
        uint256 updateFee
    ) private {
        LibArenaStorage.ArenaStorage storage store = _store();
        LibArenaStorage.Round storage round = store.rounds[roundId];
        if (!round.started) {
            revert InvalidRound();
        }
        if (!round.locked) {
            revert RoundNotLocked();
        }
        if (round.settled) {
            revert RoundSettledAlready();
        }
        if (block.timestamp < round.settleTime) {
            revert RoundTooEarlyToSettle();
        }

        uint256 finalTwap = IJudgmentOracleAdapter(store.oracle)
            .getRoundSettlementPrice{value: updateFee}(priceUpdateData);
        if (finalTwap == 0) {
            revert OraclePriceInvalid();
        }
        round.finalTwap = finalTwap;
        round.settled = true;
        round.settledAt = block.timestamp;

        LibArenaStorage.Direction winningSide = _winningSide(
            round.openTwap,
            finalTwap,
            _tieThresholdBpFor(round)
        );
        uint256 winningPoolUsd = _poolFor(round, winningSide);
        uint256 totalPoolUsd = round.upPoolUsd +
            round.downPoolUsd +
            round.tiePoolUsd;
        uint16 payoutRateBps = _payoutRateBpsFor(round, winningSide);
        uint256 edgeUsd = _edgeUsd(totalPoolUsd, payoutRateBps);

        round.winningSide = winningSide;

        (
            uint256 ethWinningPoolUsd,
            uint256 ethTotalPoolUsd,
            uint256 ethEdgeUsd,
            uint16 ethPayoutRateBps,
            uint256 ethMultiplierWad
        ) = _assetSettlement(
                round,
                LibArenaStorage.EngineAsset.ETH,
                winningSide
            );
        (
            uint256 usdcWinningPoolUsd,
            uint256 usdcTotalPoolUsd,
            uint256 usdcEdgeUsd,
            uint16 usdcPayoutRateBps,
            uint256 usdcMultiplierWad
        ) = _assetSettlement(
                round,
                LibArenaStorage.EngineAsset.USDC,
                winningSide
            );

        round.ethFinalMultiplierWad = ethMultiplierWad;
        round.usdcFinalMultiplierWad = usdcMultiplierWad;

        emit RoundAssetSettled(
            roundId,
            LibArenaStorage.EngineAsset.ETH,
            ethWinningPoolUsd,
            ethTotalPoolUsd,
            ethEdgeUsd,
            ethPayoutRateBps,
            ethMultiplierWad
        );
        emit RoundAssetSettled(
            roundId,
            LibArenaStorage.EngineAsset.USDC,
            usdcWinningPoolUsd,
            usdcTotalPoolUsd,
            usdcEdgeUsd,
            usdcPayoutRateBps,
            usdcMultiplierWad
        );

        uint256 ethPayoutAmount = (_assetWinningAmount(
            round,
            LibArenaStorage.EngineAsset.ETH,
            winningSide
        ) * ethMultiplierWad) / WAD;
        uint256 usdcPayoutAmount = (_assetWinningAmount(
            round,
            LibArenaStorage.EngineAsset.USDC,
            winningSide
        ) * usdcMultiplierWad) / WAD;
        round.ethSettledPayoutAmount = ethPayoutAmount;
        round.usdcSettledPayoutAmount = usdcPayoutAmount;

        IJudgmentObligationController(store.ethController)
            .settleRoundPayoutPool(roundId, ethPayoutAmount);
        IJudgmentObligationController(store.usdcController)
            .settleRoundPayoutPool(roundId, usdcPayoutAmount);

        emit RoundSettled(
            roundId,
            winningSide,
            round.openTwap,
            finalTwap,
            winningPoolUsd,
            totalPoolUsd,
            edgeUsd,
            payoutRateBps,
            LibArenaStorage.SettlementMode.Lazy,
            round.settledAt
        );
    }

    function claimArenaPayout(uint256 judgmentId) external {
        LibArenaStorage.ArenaStorage storage store = _store();
        _resolveOwnedJudgment(store, judgmentId, address(0), false);
    }

    function claimArenaPayouts(uint256[] calldata judgmentIds) external {
        LibArenaStorage.ArenaStorage storage store = _store();
        if (judgmentIds.length == 0 || judgmentIds.length > MAX_RESOLVE_BATCH) {
            revert BatchTooLarge();
        }

        _resolveOwnedJudgments(store, judgmentIds, MAX_RESOLVE_BATCH, false);
    }

    function claimArenaPayoutAndWithdraw(
        uint256 judgmentId,
        address receiver
    ) external {
        if (receiver == address(0)) {
            revert InvalidAddress();
        }

        LibArenaStorage.ArenaStorage storage store = _store();
        _resolveOwnedJudgment(store, judgmentId, receiver, true);
    }

    function claimArenaPayoutsAndWithdraw(
        uint256[] calldata judgmentIds,
        address receiver
    ) external {
        if (receiver == address(0)) {
            revert InvalidAddress();
        }

        LibArenaStorage.ArenaStorage storage store = _store();
        if (judgmentIds.length == 0 || judgmentIds.length > MAX_RESOLVE_BATCH) {
            revert BatchTooLarge();
        }

        _resolveOwnedJudgmentsAndWithdraw(store, judgmentIds, receiver);
    }

    function getRound(
        uint256 roundId
    ) external view returns (LibArenaStorage.Round memory) {
        return LibArenaStorage.arenaStorage().rounds[roundId];
    }

    function getJudgment(
        uint256 judgmentId
    ) external view returns (LibArenaStorage.Judgment memory) {
        return LibArenaStorage.arenaStorage().judgments[judgmentId];
    }

    function getRoundJudgmentCount(
        uint256 roundId
    ) external view returns (uint256) {
        return LibArenaStorage.arenaStorage().roundJudgmentIds[roundId].length;
    }

    /// @dev Legacy whole-array reader. Prefer getRoundJudgmentIdsPage for keeper/API paths.
    function getRoundJudgmentIds(
        uint256 roundId
    ) external view returns (uint256[] memory) {
        uint256 length = LibArenaStorage
            .arenaStorage()
            .roundJudgmentIds[roundId]
            .length;
        if (length > MAX_JUDGMENT_ID_PAGE_SIZE) {
            revert PageTooLarge();
        }

        return _roundJudgmentIdsPage(roundId, 0, length);
    }

    function getRoundJudgmentIdsPage(
        uint256 roundId,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory) {
        if (limit > MAX_JUDGMENT_ID_PAGE_SIZE) {
            revert PageTooLarge();
        }

        return _roundJudgmentIdsPage(roundId, offset, limit);
    }

    function getUserFirstJudgmentId(
        address user
    ) external view returns (uint256) {
        return LibArenaStorage.arenaStorage().firstJudgmentIdByUser[user];
    }

    function _store()
        private
        view
        returns (LibArenaStorage.ArenaStorage storage store)
    {
        store = LibArenaStorage.arenaStorage();
        if (!store.initialized) {
            revert NotInitialized();
        }
    }

    function _validateControllerPair(
        address ethController,
        address usdcController
    ) private view {
        if (
            ethController == usdcController ||
            ethController.code.length == 0 ||
            usdcController.code.length == 0
        ) {
            revert InvalidControllerBinding();
        }

        address ethVault = IJudgmentObligationController(ethController)
            .poolVault();
        address usdcVault = IJudgmentObligationController(usdcController)
            .poolVault();
        address ethAsset = IJudgmentObligationController(ethController).asset();
        address usdcAsset = IJudgmentObligationController(usdcController)
            .asset();

        if (
            ethVault == address(0) ||
            usdcVault == address(0) ||
            ethVault == usdcVault
        ) {
            revert InvalidControllerBinding();
        }
        if (ethAsset != ETH_ASSET || usdcAsset == ETH_ASSET) {
            revert InvalidAsset();
        }
        if (IPoolVault(ethVault).businessController() != ethController) {
            revert InvalidControllerBinding();
        }
        if (IPoolVault(usdcVault).businessController() != usdcController) {
            revert InvalidControllerBinding();
        }
        if (
            IPoolVault(ethVault).asset() != ethAsset ||
            IPoolVault(usdcVault).asset() != usdcAsset
        ) {
            revert InvalidAsset();
        }
    }

    function _roundJudgmentIdsPage(
        uint256 roundId,
        uint256 offset,
        uint256 limit
    ) private view returns (uint256[] memory) {
        uint256[] storage judgmentIds = LibArenaStorage
            .arenaStorage()
            .roundJudgmentIds[roundId];
        uint256 length = judgmentIds.length;
        if (limit == 0 || offset >= length) {
            return new uint256[](0);
        }

        uint256 remaining = length - offset;
        uint256 pageSize = limit < remaining ? limit : remaining;
        uint256[] memory page = new uint256[](pageSize);
        // pageSize is bounded by length - offset, so offset + i cannot overflow.
        for (uint256 i = 0; i < pageSize; i++) {
            page[i] = judgmentIds[offset + i];
        }

        return page;
    }

    function _enforceSettlementOperator() private view {
        LibArenaStorage.ArenaStorage storage store = _store();
        LibDiamond.DiamondStorage storage diamondStore = LibDiamond
            .diamondStorage();
        if (
            msg.sender != diamondStore.contractOwner &&
            !store.settlementOperators[msg.sender]
        ) {
            revert NotSettlementOperator();
        }
    }

    function _addPool(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction,
        uint256 amountAsset,
        uint256 notionalUsd
    ) private {
        if (direction == LibArenaStorage.Direction.Up) {
            round.upPoolUsd += notionalUsd;
            round.upEntryCount += 1;
            if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
                round.ethUpPoolUsd += notionalUsd;
                round.ethUpAmount += amountAsset;
                round.ethUpEntryCount += 1;
            } else {
                round.usdcUpPoolUsd += notionalUsd;
                round.usdcUpAmount += amountAsset;
                round.usdcUpEntryCount += 1;
            }
        } else if (direction == LibArenaStorage.Direction.Down) {
            round.downPoolUsd += notionalUsd;
            round.downEntryCount += 1;
            if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
                round.ethDownPoolUsd += notionalUsd;
                round.ethDownAmount += amountAsset;
                round.ethDownEntryCount += 1;
            } else {
                round.usdcDownPoolUsd += notionalUsd;
                round.usdcDownAmount += amountAsset;
                round.usdcDownEntryCount += 1;
            }
        } else {
            round.tiePoolUsd += notionalUsd;
            round.tieEntryCount += 1;
            if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
                round.ethTiePoolUsd += notionalUsd;
                round.ethTieAmount += amountAsset;
                round.ethTieEntryCount += 1;
            } else {
                round.usdcTiePoolUsd += notionalUsd;
                round.usdcTieAmount += amountAsset;
                round.usdcTieEntryCount += 1;
            }
        }
    }

    function _resolveOwnedJudgments(
        LibArenaStorage.ArenaStorage storage store,
        uint256[] calldata judgmentIds,
        uint256 maxBatch,
        bool emitAutoResolve
    ) private {
        if (judgmentIds.length > maxBatch) {
            revert BatchTooLarge();
        }

        for (uint256 i = 0; i < judgmentIds.length; i++) {
            _resolveOwnedJudgment(store, judgmentIds[i], address(0), false);
        }

        if (emitAutoResolve && judgmentIds.length != 0) {
            emit AutoResolveCompleted(msg.sender, judgmentIds.length);
        }
    }

    function _resolveOwnedJudgmentsAndWithdraw(
        LibArenaStorage.ArenaStorage storage store,
        uint256[] calldata judgmentIds,
        address receiver
    ) private {
        for (uint256 i = 0; i < judgmentIds.length; i++) {
            _resolveOwnedJudgment(store, judgmentIds[i], receiver, true);
        }
    }

    function _resolveOwnedJudgment(
        LibArenaStorage.ArenaStorage storage store,
        uint256 judgmentId,
        address receiver,
        bool withdraw
    ) private {
        LibArenaStorage.Judgment storage judgment = store.judgments[judgmentId];
        if (judgment.user != msg.sender) {
            revert NotJudgmentOwner();
        }

        _resolveJudgment(store, judgmentId, receiver, withdraw);
    }

    function _resolveJudgment(
        LibArenaStorage.ArenaStorage storage store,
        uint256 judgmentId,
        address receiver,
        bool withdraw
    ) private {
        LibArenaStorage.Judgment storage judgment = store.judgments[judgmentId];
        if (judgment.user == address(0)) {
            revert InvalidRound();
        }
        if (judgment.resolved) {
            revert JudgmentAlreadyResolved();
        }

        LibArenaStorage.Round storage round = store.rounds[judgment.roundId];
        if (!round.settled) {
            revert RoundNotSettled();
        }

        uint256 multiplierWad = _finalMultiplierFor(round, judgment.entryAsset);
        bool confirmed = judgment.direction == round.winningSide &&
            multiplierWad != 0;
        uint256 payoutAmount = confirmed
            ? _consumeFinalPayout(
                round,
                judgment.entryAsset,
                judgment.amountAsset
            )
            : 0;

        judgment.resolved = true;

        address controller = judgment.entryAsset ==
            LibArenaStorage.EngineAsset.ETH
            ? store.ethController
            : store.usdcController;
        if (withdraw) {
            IJudgmentObligationController(controller)
                .allocateAndClaimSettledJudgmentPayout(
                    judgmentId,
                    payoutAmount,
                    receiver
                );
        } else {
            IJudgmentObligationController(controller)
                .allocateSettledJudgmentPayout(judgmentId, payoutAmount);
        }

        emit JudgmentResolved(
            judgment.user,
            judgment.roundId,
            judgmentId,
            confirmed
                ? LibArenaStorage.JudgmentResult.Confirmed
                : LibArenaStorage.JudgmentResult.Refuted,
            judgment.entryAsset,
            payoutAmount,
            multiplierWad
        );
    }

    function _poolFor(
        LibArenaStorage.Round storage round,
        LibArenaStorage.Direction direction
    ) private view returns (uint256) {
        if (direction == LibArenaStorage.Direction.Up) {
            return round.upPoolUsd;
        }
        if (direction == LibArenaStorage.Direction.Down) {
            return round.downPoolUsd;
        }
        return round.tiePoolUsd;
    }

    function _assetAggregatePayout(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction
    ) private view returns (uint256) {
        uint256 sidePoolUsd = _assetPoolFor(round, entryAsset, direction);
        if (sidePoolUsd == 0) {
            return 0;
        }

        uint256 totalPoolUsd = _assetTotalPoolUsd(round, entryAsset);
        uint16 payoutRateBps = _payoutRateBpsFor(round, direction);
        uint256 multiplierWad = _finalMultiplierWad(
            totalPoolUsd,
            payoutRateBps,
            sidePoolUsd
        );
        return
            (_assetWinningAmount(round, entryAsset, direction) *
                multiplierWad) / WAD;
    }

    function _aggregateReserveDelta(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset
    ) private view returns (uint256) {
        uint256 requiredReserve = _assetMaxAggregatePayout(round, entryAsset);
        uint256 currentReserve = _assetReservedPayout(round, entryAsset);
        if (requiredReserve <= currentReserve) {
            return 0;
        }

        return requiredReserve - currentReserve;
    }

    function _increaseAggregateReserve(
        LibArenaStorage.ArenaStorage storage store,
        uint256 roundId,
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        uint256 reserveDelta
    ) private {
        if (reserveDelta == 0) {
            return;
        }

        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            round.ethReservedPayoutAmount += reserveDelta;
            IJudgmentObligationController(store.ethController)
                .increaseRoundReservedPayout(roundId, reserveDelta);
        } else {
            round.usdcReservedPayoutAmount += reserveDelta;
            IJudgmentObligationController(store.usdcController)
                .increaseRoundReservedPayout(roundId, reserveDelta);
        }
    }

    function _assetPoolFor(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            if (direction == LibArenaStorage.Direction.Up) {
                return round.ethUpPoolUsd;
            }
            if (direction == LibArenaStorage.Direction.Down) {
                return round.ethDownPoolUsd;
            }
            return round.ethTiePoolUsd;
        }

        if (direction == LibArenaStorage.Direction.Up) {
            return round.usdcUpPoolUsd;
        }
        if (direction == LibArenaStorage.Direction.Down) {
            return round.usdcDownPoolUsd;
        }
        return round.usdcTiePoolUsd;
    }

    function _assetTotalPoolUsd(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            return
                round.ethUpPoolUsd + round.ethDownPoolUsd + round.ethTiePoolUsd;
        }

        return
            round.usdcUpPoolUsd + round.usdcDownPoolUsd + round.usdcTiePoolUsd;
    }

    function _assetCapacity(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            return round.ethCapacity;
        }

        return round.usdcCapacity;
    }

    function _assetReservedPayout(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            return round.ethReservedPayoutAmount;
        }

        return round.usdcReservedPayoutAmount;
    }

    function _assetMaxAggregatePayout(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset
    ) private view returns (uint256) {
        uint256 upPayout = _assetAggregatePayout(
            round,
            entryAsset,
            LibArenaStorage.Direction.Up
        );
        uint256 downPayout = _assetAggregatePayout(
            round,
            entryAsset,
            LibArenaStorage.Direction.Down
        );
        uint256 tiePayout = _assetAggregatePayout(
            round,
            entryAsset,
            LibArenaStorage.Direction.Tie
        );
        uint256 maxPayout = upPayout > downPayout ? upPayout : downPayout;
        return maxPayout > tiePayout ? maxPayout : tiePayout;
    }

    function _assetWinningAmount(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            if (direction == LibArenaStorage.Direction.Up) {
                return round.ethUpAmount;
            }
            if (direction == LibArenaStorage.Direction.Down) {
                return round.ethDownAmount;
            }
            return round.ethTieAmount;
        }

        if (direction == LibArenaStorage.Direction.Up) {
            return round.usdcUpAmount;
        }
        if (direction == LibArenaStorage.Direction.Down) {
            return round.usdcDownAmount;
        }
        return round.usdcTieAmount;
    }

    function _assetWinningEntryCount(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        LibArenaStorage.Direction direction
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            if (direction == LibArenaStorage.Direction.Up) {
                return round.ethUpEntryCount;
            }
            if (direction == LibArenaStorage.Direction.Down) {
                return round.ethDownEntryCount;
            }
            return round.ethTieEntryCount;
        }

        if (direction == LibArenaStorage.Direction.Up) {
            return round.usdcUpEntryCount;
        }
        if (direction == LibArenaStorage.Direction.Down) {
            return round.usdcDownEntryCount;
        }
        return round.usdcTieEntryCount;
    }

    function _finalMultiplierFor(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset
    ) private view returns (uint256) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            return round.ethFinalMultiplierWad;
        }

        return round.usdcFinalMultiplierWad;
    }

    function _consumeFinalPayout(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset entryAsset,
        uint256 amountAsset
    ) private returns (uint256 payoutAmount) {
        if (entryAsset == LibArenaStorage.EngineAsset.ETH) {
            uint256 ethTotalWinningAmount = _assetWinningAmount(
                round,
                LibArenaStorage.EngineAsset.ETH,
                round.winningSide
            );
            if (ethTotalWinningAmount == 0) {
                revert InvalidRound();
            }
            uint256 ethNewResolvedWinningAmount = round
                .ethResolvedWinningAmount + amountAsset;
            if (ethNewResolvedWinningAmount > ethTotalWinningAmount) {
                revert InvalidRound();
            }
            uint256 ethCumulativePayout = ethNewResolvedWinningAmount.mulDiv(
                round.ethSettledPayoutAmount,
                ethTotalWinningAmount
            );
            if (ethCumulativePayout > round.ethSettledPayoutAmount) {
                revert InvalidRound();
            }
            payoutAmount = ethCumulativePayout - round.ethAllocatedPayoutAmount;
            round.ethResolvedWinningAmount = ethNewResolvedWinningAmount;
            round.ethAllocatedPayoutAmount = ethCumulativePayout;
            return payoutAmount;
        }

        uint256 usdcTotalWinningAmount = _assetWinningAmount(
            round,
            LibArenaStorage.EngineAsset.USDC,
            round.winningSide
        );
        if (usdcTotalWinningAmount == 0) {
            revert InvalidRound();
        }
        uint256 usdcNewResolvedWinningAmount = round.usdcResolvedWinningAmount +
            amountAsset;
        if (usdcNewResolvedWinningAmount > usdcTotalWinningAmount) {
            revert InvalidRound();
        }
        uint256 usdcCumulativePayout = usdcNewResolvedWinningAmount.mulDiv(
            round.usdcSettledPayoutAmount,
            usdcTotalWinningAmount
        );
        if (usdcCumulativePayout > round.usdcSettledPayoutAmount) {
            revert InvalidRound();
        }
        payoutAmount = usdcCumulativePayout - round.usdcAllocatedPayoutAmount;
        round.usdcResolvedWinningAmount = usdcNewResolvedWinningAmount;
        round.usdcAllocatedPayoutAmount = usdcCumulativePayout;
    }

    function _assetSettlement(
        LibArenaStorage.Round storage round,
        LibArenaStorage.EngineAsset asset,
        LibArenaStorage.Direction winningSide
    )
        private
        view
        returns (
            uint256 winningPoolUsd,
            uint256 totalPoolUsd,
            uint256 edgeUsd,
            uint16 payoutRateBps,
            uint256 finalMultiplierWad
        )
    {
        winningPoolUsd = _assetPoolFor(round, asset, winningSide);
        totalPoolUsd = _assetTotalPoolUsd(round, asset);
        payoutRateBps = _payoutRateBpsFor(round, winningSide);
        edgeUsd = _edgeUsd(totalPoolUsd, payoutRateBps);
        finalMultiplierWad = winningPoolUsd == 0
            ? 0
            : _finalMultiplierWad(totalPoolUsd, payoutRateBps, winningPoolUsd);
    }

    function _finalMultiplierWad(
        uint256 totalPoolUsd,
        uint16 payoutRateBps,
        uint256 winningPoolUsd
    ) private pure returns (uint256) {
        return
            totalPoolUsd.mulDiv(
                uint256(payoutRateBps) * WAD,
                BPS_DENOMINATOR * winningPoolUsd
            );
    }

    function _payoutRateBpsFor(
        LibArenaStorage.Round storage round,
        LibArenaStorage.Direction direction
    ) private view returns (uint16) {
        if (direction == LibArenaStorage.Direction.Tie) {
            return
                round.tiePayoutRateBps == 0
                    ? uint16(TIE_PAYOUT_RATE_BPS)
                    : round.tiePayoutRateBps;
        }

        return
            round.upDownPayoutRateBps == 0
                ? uint16(UP_DOWN_PAYOUT_RATE_BPS)
                : round.upDownPayoutRateBps;
    }

    function _tieThresholdBpFor(
        LibArenaStorage.Round storage round
    ) private view returns (uint16) {
        return
            round.tieThresholdBp == 0
                ? uint16(TIE_THRESHOLD_BP)
                : round.tieThresholdBp;
    }

    function _edgeUsd(
        uint256 totalPoolUsd,
        uint16 payoutRateBps
    ) private pure returns (uint256) {
        return
            (totalPoolUsd * (BPS_DENOMINATOR - payoutRateBps)) /
            BPS_DENOMINATOR;
    }

    function _validateRoundEconomics() private pure {
        if (
            START_UP_POOL_BPS + START_DOWN_POOL_BPS + START_TIE_POOL_BPS !=
            BPS_DENOMINATOR ||
            UP_DOWN_PAYOUT_RATE_BPS == 0 ||
            UP_DOWN_PAYOUT_RATE_BPS > BPS_DENOMINATOR ||
            TIE_PAYOUT_RATE_BPS == 0 ||
            TIE_PAYOUT_RATE_BPS > BPS_DENOMINATOR
        ) {
            revert InvalidRoundEconomics();
        }
    }

    function _winningSide(
        uint256 openTwap,
        uint256 finalTwap,
        uint16 tieThresholdBp
    ) private pure returns (LibArenaStorage.Direction) {
        uint256 threshold = (openTwap * tieThresholdBp) / BPS_DENOMINATOR;
        if (finalTwap >= openTwap) {
            if (finalTwap - openTwap <= threshold) {
                return LibArenaStorage.Direction.Tie;
            }
            return LibArenaStorage.Direction.Up;
        }
        if (openTwap - finalTwap <= threshold) {
            return LibArenaStorage.Direction.Tie;
        }
        return LibArenaStorage.Direction.Down;
    }

    function _ethToUsd(
        uint256 ethAmount,
        uint256 ethUsdReference
    ) private pure returns (uint256) {
        return (ethAmount * ethUsdReference) / WAD;
    }

    function _usdcToUsd(uint256 usdcAmount) private pure returns (uint256) {
        return usdcAmount * 1e12;
    }
}
