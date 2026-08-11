// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
//  BurnBombTypes · shared type declarations for BurnBomb v1.1 (dual-oracle)
//
//  Extracted so external libraries (BulkWithdrawLib, SupraLib) can read the
//  Round struct directly from the main contract's storage mapping without
//  re-marshaling each scalar. The struct layout MUST match the main
//  contract's expectation byte-for-byte; any append to this struct must mirror
//  the corresponding append in any future BurnBomb-family contract that
//  reuses the layout.
//
//  See burnbomb/MINNOW-V1.1-DUAL-ORACLE-SPEC.md §8 for the full storage map.
// ─────────────────────────────────────────────────────────────────────────────

library BurnBombTypes {
    struct Round {
        // --- timing packed in 1 slot ---
        uint64 createdAt;
        uint64 activeStartedAt;
        uint64 activeTimerEndsAt;
        uint64 finalCountdownEndsAt;

        // --- timing + state packed in 1 slot ---
        uint64 seedEndsAt;
        uint64 activeEndsAt;
        uint16 slotsClaimed;
        uint8  phase;
        uint32 retryCount;

        // --- pot accounting ---
        uint256 potTotal;
        uint256 seedPotTotal;

        // --- pot split snapshot ---
        uint256 seedDividendPool;

        // --- VRF state ---
        uint256 chainlinkRequestId;
        uint256 supraNonce;
        uint256 vrfRequestedAt;
        uint256 firstVrfRequestedAt;
        uint256 randomWord;
        uint256 totalRetryBountyPaid;

        // --- Best-effort BURN rake escrow ---
        uint256 pendingBurnRake;

        // --- finalization snapshots ---
        uint16  winnerSlot;
        uint16  secondSlot;
        uint16  thirdSlot;
        address founderPayoutAtSettle;

        // --- v1.1: per-round seed-cross threshold ---
        uint256 threshold;

        // --- v1.1a NEW: append-only (storage layout safety) ---
        address creator;
        string  name;
        string  imageURI;

        // --- v1.1 dual-oracle NEW: append-only ---
        uint8 fulfillingOracle;
    }
}
