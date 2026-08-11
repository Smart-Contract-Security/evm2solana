// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BurnBombTypes} from "./BurnBombTypes.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  LifecycleLib · v1.1 dual-oracle · external-linked library for round entry
//  + phase-advance machinery.
//
//  Extracted from BurnBombV1_1's `_enterSingleInternal` and `_advancePhase`
//  helpers — both substantial functions called multiple sites in the main
//  contract, so inlining significantly inflates deployed bytecode. Moving
//  them to an external library (DELEGATECALL) collapses three copies to one
//  shared deployment.
//
//  Pattern mirrors ThroneLib / SettlementLib / BulkWithdrawLib / SupraLib:
//    - `external` functions taking storage refs.
//    - DELEGATECALL semantics — msg.sender, address(this), and storage all
//      target the main contract; library bytecode lives at its own address.
//    - Events emitted from the library reach the main contract address.
//    - Custom errors mirror main contract's selectors (keccak256 of name).
//
//  Phase enum ordinals (must stay in sync with BurnBombV1_1.Phase):
//    0 NONE, 1 SEEDING, 2 ACTIVE, 3 FINAL_COUNTDOWN,
//    4 READY_TO_REQUEST_RANDOMNESS, 5 WAITING_FOR_RANDOMNESS,
//    6 RANDOMNESS_FULFILLED, 7 SETTLED, 8 REFUNDED
// ─────────────────────────────────────────────────────────────────────────────

library LifecycleLib {
    error WrongPhase();
    error WrongValue();
    error SlotTaken();
    error SlotOutOfRange();
    error AddressCapExceeded();
    error NotActivated();
    error ContractDeprecated();
    error ActiveRoundExists();
    error ThresholdOutOfRange(uint256 supplied, uint256 min, uint256 max);
    error NameTooLong(uint256 length, uint256 max);
    error ImageURITooLong(uint256 length, uint256 max);

    // Phase ordinals (stay in sync with main contract enum).
    uint8 internal constant P_NONE = 0;
    uint8 internal constant P_SEEDING = 1;
    uint8 internal constant P_ACTIVE = 2;
    uint8 internal constant P_FINAL_COUNTDOWN = 3;
    uint8 internal constant P_READY_TO_REQUEST_RANDOMNESS = 4;
    uint8 internal constant P_REFUNDED = 8;

    // Mirror main contract event signatures (indexed args match).
    event SlotClaimed(uint256 indexed roundId, uint16 indexed slotIndex, address indexed claimer, uint256 value);
    event PhaseTransition(uint256 indexed roundId, uint8 oldPhase, uint8 newPhase);
    event ThresholdMet(uint256 indexed roundId, uint256 potAtThreshold);
    event FinalCountdownStarted(uint256 indexed roundId);
    event ReadyToRequestRandomness(uint256 indexed roundId);
    event RoundRefunded(uint256 indexed roundId);
    event RoundCreated(uint256 indexed roundId, address indexed creator, uint256 createdAt, uint256 threshold, string name, string imageURI);

    // (CreateRoundParams struct removed — split callable validation between
    // a flags-pack uint256 and direct args to avoid viaIR stack-too-deep.)

    struct LifecycleConstants {
        uint16 maxEntriesPerAddress;
        uint16 numSlots;
        uint256 activeTimer;
        uint256 activePhaseMax;
        uint256 finalCountdown;
    }

    /// @dev Core entry helper. Caller has already validated msg.value matches
    /// the slot value (or summed the batch). Library performs:
    ///   - phase guard (must be SEEDING / ACTIVE / FINAL_COUNTDOWN)
    ///   - bounds + slot-taken + address-cap checks
    ///   - effects (slot ownership, claimedSlots push, addressSlots push,
    ///             addressEntryCount++, pot + seedPot accounting)
    ///   - ACTIVE-phase sliding-timer reset
    ///   - SEEDING→ACTIVE threshold-cross transition
    ///   - any-phase NUM_SLOTS sold-out fast-track
    ///   - emits SlotClaimed / ThresholdMet / PhaseTransition / ReadyToRequestRandomness
    function enterSingleInternal(
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        mapping(uint256 => mapping(uint16 => address)) storage slotOwner,
        mapping(uint256 => uint16[]) storage claimedSlotsByRound,
        mapping(uint256 => mapping(address => uint16)) storage addressEntryCount,
        mapping(uint256 => mapping(address => uint16[])) storage addressSlots,
        mapping(uint256 => mapping(address => uint256)) storage seedContribution,
        uint256 roundId,
        uint16 slotIndex,
        uint256 value,
        address sender,
        LifecycleConstants memory C
    ) external {
        BurnBombTypes.Round storage r = rounds[roundId];
        uint8 p = r.phase;
        if (p != P_SEEDING && p != P_ACTIVE && p != P_FINAL_COUNTDOWN) revert WrongPhase();

        if (slotIndex >= C.numSlots) revert SlotOutOfRange();
        if (slotOwner[roundId][slotIndex] != address(0)) revert SlotTaken();
        if (addressEntryCount[roundId][sender] >= C.maxEntriesPerAddress) revert AddressCapExceeded();

        // Effects
        slotOwner[roundId][slotIndex] = sender;
        claimedSlotsByRound[roundId].push(slotIndex);
        addressSlots[roundId][sender].push(slotIndex);
        addressEntryCount[roundId][sender] += 1;

        uint256 potBefore = r.potTotal;
        uint256 potAfter = potBefore + value;
        if (potBefore < r.threshold) {
            uint256 seedRoom = r.threshold - potBefore;
            uint256 seedShare = value < seedRoom ? value : seedRoom;
            seedContribution[roundId][sender] += seedShare;
            r.seedPotTotal += seedShare;
        }

        r.potTotal = potAfter;
        r.slotsClaimed += 1;

        if (p == P_ACTIVE) {
            r.activeTimerEndsAt = uint64(block.timestamp + C.activeTimer);
        }

        emit SlotClaimed(roundId, slotIndex, sender, value);

        if (p == P_SEEDING && potAfter >= r.threshold) {
            r.phase = P_ACTIVE;
            r.activeStartedAt = uint64(block.timestamp);
            r.activeTimerEndsAt = uint64(block.timestamp + C.activeTimer);
            r.activeEndsAt = uint64(block.timestamp + C.activePhaseMax);
            emit ThresholdMet(roundId, potAfter);
            emit PhaseTransition(roundId, P_SEEDING, P_ACTIVE);
        }

        if (r.slotsClaimed == C.numSlots) {
            uint8 prev = r.phase;
            r.phase = P_READY_TO_REQUEST_RANDOMNESS;
            emit PhaseTransition(roundId, prev, P_READY_TO_REQUEST_RANDOMNESS);
            emit ReadyToRequestRandomness(roundId);
        }
    }

    /// @dev Permissionless time-driven phase transitions:
    ///   SEEDING (timeout w/o threshold) → REFUNDED
    ///   ACTIVE  (sliding-timer expiry or hard ceiling) → FINAL_COUNTDOWN
    ///   FINAL_COUNTDOWN (timer elapsed) → READY_TO_REQUEST_RANDOMNESS
    /// All other phases: noop.
    function advancePhase(
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        uint256 roundId,
        uint256 finalCountdown
    ) external {
        BurnBombTypes.Round storage r = rounds[roundId];
        uint8 p = r.phase;

        if (p == P_SEEDING) {
            if (block.timestamp >= r.seedEndsAt && r.potTotal < r.threshold) {
                r.phase = P_REFUNDED;
                emit PhaseTransition(roundId, P_SEEDING, P_REFUNDED);
                emit RoundRefunded(roundId);
            }
            return;
        }

        if (p == P_ACTIVE) {
            bool slidingExpired = block.timestamp >= r.activeTimerEndsAt;
            bool ceilingHit = block.timestamp >= r.activeEndsAt;
            if (slidingExpired || ceilingHit) {
                r.phase = P_FINAL_COUNTDOWN;
                r.finalCountdownEndsAt = uint64(block.timestamp + finalCountdown);
                emit PhaseTransition(roundId, P_ACTIVE, P_FINAL_COUNTDOWN);
                emit FinalCountdownStarted(roundId);
            }
            return;
        }

        if (p == P_FINAL_COUNTDOWN) {
            if (block.timestamp >= r.finalCountdownEndsAt) {
                r.phase = P_READY_TO_REQUEST_RANDOMNESS;
                emit PhaseTransition(roundId, P_FINAL_COUNTDOWN, P_READY_TO_REQUEST_RANDOMNESS);
                emit ReadyToRequestRandomness(roundId);
            }
            return;
        }
    }

    /// @dev Pre-check that has no storage writes — used by createRoundSetup
    /// caller to factor the heavy validation out. Returns silently on success.
    function checkCreateRoundActivation(
        bool activated_,
        bool deprecated_,
        uint8 currentRoundPhase,
        uint256 currentRoundId
    ) external pure {
        if (!activated_) revert NotActivated();
        if (deprecated_) revert ContractDeprecated();
        if (currentRoundId != 0) {
            if (currentRoundPhase != 7 /* SETTLED */ && currentRoundPhase != P_REFUNDED) {
                revert ActiveRoundExists();
            }
        }
    }

    /// @dev Body of createRoundAndEnter's validation + Round storage init.
    /// Caller has already validated `msg.value` matches `slotValue(slotIdx)`,
    /// and will invoke `enterSingleInternal` for the slot claim after this
    /// returns. Library emits RoundCreated + SEEDING PhaseTransition.
    /// Returns the new roundId so caller can pin currentRoundId.
    function createRoundSetup(
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        uint256 newRoundId,
        uint256 threshold,
        uint256 seedPhaseMax,
        address creator,
        string calldata name,
        string calldata imageURI
    ) external {
        BurnBombTypes.Round storage r = rounds[newRoundId];
        r.createdAt = uint64(block.timestamp);
        r.seedEndsAt = uint64(block.timestamp + seedPhaseMax);
        r.phase = P_SEEDING;
        r.threshold = threshold;
        r.creator = creator;
        r.name = name;
        r.imageURI = imageURI;

        emit RoundCreated(newRoundId, creator, block.timestamp, threshold, name, imageURI);
        emit PhaseTransition(newRoundId, P_NONE, P_SEEDING);
    }
}
