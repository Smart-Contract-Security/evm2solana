// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library LibArenaStorage {
    bytes32 internal constant ARENA_STORAGE_POSITION = keccak256("ace.contracts.judgment.arena.storage");

    enum MarketAsset {
        BTC_ETH
    }

    enum EngineAsset {
        ETH,
        USDC
    }

    enum Direction {
        Up,
        Down,
        Tie
    }

    enum JudgmentResult {
        Confirmed,
        Refuted,
        Pending
    }

    enum SettlementMode {
        Individual,
        Batch,
        Lazy
    }

    struct Round {
        uint256 startTime;
        uint256 lockTime;
        uint256 settleTime;
        uint256 openTwap;
        uint256 finalTwap;
        uint256 ethUsdReference;
        uint256 upPoolUsd;
        uint256 downPoolUsd;
        uint256 tiePoolUsd;
        uint256 upEntryCount;
        uint256 downEntryCount;
        uint256 tieEntryCount;
        bool started;
        bool locked;
        bool settled;
        uint256 ethUpPoolUsd;
        uint256 ethDownPoolUsd;
        uint256 ethTiePoolUsd;
        uint256 usdcUpPoolUsd;
        uint256 usdcDownPoolUsd;
        uint256 usdcTiePoolUsd;
        Direction winningSide;
        uint256 ethFinalMultiplierWad;
        uint256 usdcFinalMultiplierWad;
        uint256 ethUpAmount;
        uint256 ethDownAmount;
        uint256 ethTieAmount;
        uint256 usdcUpAmount;
        uint256 usdcDownAmount;
        uint256 usdcTieAmount;
        uint256 ethUpEntryCount;
        uint256 ethDownEntryCount;
        uint256 ethTieEntryCount;
        uint256 usdcUpEntryCount;
        uint256 usdcDownEntryCount;
        uint256 usdcTieEntryCount;
        uint256 ethCapacity;
        uint256 usdcCapacity;
        uint256 ethReservedPayoutAmount;
        uint256 usdcReservedPayoutAmount;
        uint256 ethSettledPayoutAmount;
        uint256 usdcSettledPayoutAmount;
        uint256 ethResolvedWinningAmount;
        uint256 usdcResolvedWinningAmount;
        uint256 ethAllocatedPayoutAmount;
        uint256 usdcAllocatedPayoutAmount;
        // Appended lifecycle timestamps for event-log replay/indexing only; do not use for settlement logic.
        uint256 lockedAt;
        uint256 settledAt;
        // Appended round parameter snapshots for replay and future per-market configurability.
        MarketAsset marketAsset;
        uint16 tieThresholdBp;
        uint16 upDownPayoutRateBps;
        uint16 tiePayoutRateBps;
        uint16 startUpPoolBps;
        uint16 startDownPoolBps;
        uint16 startTiePoolBps;
    }

    struct Judgment {
        address user;
        uint256 roundId;
        EngineAsset entryAsset;
        Direction direction;
        uint256 amountAsset;
        uint256 notionalUsd;
        uint256 maxReservedPayout;
        bool resolved;
    }

    struct ArenaStorage {
        bool initialized;
        address ethController;
        address usdcController;
        address oracle;
        uint256 nextJudgmentId;
        mapping(uint256 => Round) rounds;
        mapping(uint256 => uint256[]) roundJudgmentIds;
        mapping(uint256 => Judgment) judgments;
        address dataQuality;
        mapping(address => uint256) firstJudgmentIdByUser;
        mapping(address => bool) settlementOperators;
    }

    function arenaStorage() internal pure returns (ArenaStorage storage store) {
        bytes32 position = ARENA_STORAGE_POSITION;
        assembly {
            store.slot := position
        }
    }
}
