// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BurnBombTypes} from "./BurnBombTypes.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  BulkWithdrawLib · v1.1 · external-linked library for batch withdraw loops
//
//  Bytecode size optimization. BurnBombV1_1 (dual-oracle) pushes past the
//  EIP-170 24,576-byte deployed-code ceiling. The three bulk-withdraw loops
//  (refund / payout / seed dividend) are mechanical iteration code with no
//  oracle dependency; perfect extraction candidates.
//
//  Pattern mirrors ThroneLib:
//    - `library` with `external` functions taking `storage` references.
//    - Library reads/writes the main contract's storage directly via the
//      shared BurnBombTypes.Round struct definition.
//    - The library is invoked via DELEGATECALL — execution happens in the
//      main contract's context. Storage writes land in the main contract's
//      slots, msg.sender stays the original caller, AND events emitted from
//      library code are emitted by the main contract address. This is
//      necessary for event-based size optimization (emitting from the loop
//      avoids a second iteration in the caller).
//    - All ETH transfers stay in the main contract wrapper (nonReentrant +
//      interaction-ordering safety): the library returns the total payable
//      amount; the caller performs `to.call{value}`.
//
//  Custom errors mirror the main contract's (selectors keccak-match by name).
// ─────────────────────────────────────────────────────────────────────────────

library BulkWithdrawLib {
    error WrongPhase();
    error NotSlotOwner();
    error NothingToWithdraw();
    error AlreadyClaimed();
    error BurnBomb_ZeroAddress();

    // SETTLED ordinal in main contract's Phase enum. Hard-coded as a constant
    // here so the library has no dependency on the enum definition. MUST stay
    // in sync with BurnBombV1_1.Phase.SETTLED (= 7).
    uint8 internal constant PHASE_SETTLED = 7;

    // Mirror main contract event signatures for indexer compatibility.
    event RefundClaimed(uint256 indexed roundId, address indexed account, uint16 indexed slotIndex, uint256 amount);
    event PayoutWithdrawn(uint256 indexed roundId, address indexed account, address indexed recipient, uint256 amount);
    event SeedDividendWithdrawn(uint256 indexed roundId, address indexed account, uint256 amount);
    event BurnRakeForwarded(uint256 indexed roundId, uint256 amount);

    /// @dev Process per-slot refunds for a single REFUNDED round. Computes
    /// pro-rata-adjusted amounts, zeroes slot ownership, emits per-slot
    /// RefundClaimed events, returns total payable.
    function processRefundBatch(
        uint256 roundId,
        uint16[] calldata slotIndices,
        address claimer,
        mapping(uint256 => mapping(uint16 => address)) storage slotOwner,
        uint256 totalRetryBountyPaid,
        uint256 potTotal,
        uint256 contractBal,
        uint256 minSlot,
        uint256 slotStep
    ) external returns (uint256 total) {
        uint256 n = slotIndices.length;

        for (uint256 i = 0; i < n; i++) {
            uint16 slotIndex = slotIndices[i];
            if (slotOwner[roundId][slotIndex] != claimer) revert NotSlotOwner();

            uint256 grossAmount = minSlot + uint256(slotIndex) * slotStep;
            uint256 amount = grossAmount;
            if (totalRetryBountyPaid > 0 && potTotal > 0) {
                uint256 shortfall = grossAmount * totalRetryBountyPaid / potTotal;
                amount = grossAmount - shortfall;
            }

            slotOwner[roundId][slotIndex] = address(0);

            if (total + amount > contractBal) {
                amount = contractBal > total ? contractBal - total : 0;
            }
            total += amount;

            emit RefundClaimed(roundId, claimer, slotIndex, amount);
        }
    }

    /// @dev Process per-round payouts across multiple SETTLED rounds. Zeroes
    /// the claimer's claimablePayout per round, emits per-round PayoutWithdrawn,
    /// returns total payable. Phase check per-round strict (any non-SETTLED
    /// reverts).
    function processPayoutBatch(
        uint256[] calldata roundIds,
        address claimer,
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        mapping(uint256 => mapping(address => uint256)) storage claimablePayout
    ) external returns (uint256 total) {
        uint256 n = roundIds.length;

        for (uint256 i = 0; i < n; i++) {
            uint256 roundId = roundIds[i];
            if (rounds[roundId].phase != PHASE_SETTLED) revert WrongPhase();

            uint256 amount = claimablePayout[roundId][claimer];
            if (amount > 0) {
                claimablePayout[roundId][claimer] = 0;
                total += amount;
                emit PayoutWithdrawn(roundId, claimer, claimer, amount);
            }
        }
    }

    /// @dev Process per-round seed dividends across multiple SETTLED rounds.
    /// Marks claimed, emits per-round SeedDividendWithdrawn, returns total
    /// payable. Already-claimed or zero-contribution rounds silently skip.
    function processSeedDividendBatch(
        uint256[] calldata roundIds,
        address claimer,
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        mapping(uint256 => mapping(address => bool)) storage seedDividendClaimed,
        mapping(uint256 => mapping(address => uint256)) storage seedContribution
    ) external returns (uint256 total) {
        uint256 n = roundIds.length;

        for (uint256 i = 0; i < n; i++) {
            uint256 roundId = roundIds[i];
            BurnBombTypes.Round storage r = rounds[roundId];
            if (r.phase != PHASE_SETTLED) revert WrongPhase();

            if (seedDividendClaimed[roundId][claimer]) continue;
            uint256 contrib = seedContribution[roundId][claimer];
            if (contrib == 0) continue;

            uint256 amount = r.seedDividendPool * contrib / r.seedPotTotal;
            if (amount > 0) {
                seedDividendClaimed[roundId][claimer] = true;
                total += amount;
                emit SeedDividendWithdrawn(roundId, claimer, amount);
            }
        }
    }

    /// @dev Single-item payout. Validates non-zero recipient + claimable,
    /// zeroes state, emits event, returns amount for the caller to transfer.
    function payoutSingle(
        mapping(uint256 => mapping(address => uint256)) storage claimablePayout,
        uint256 roundId,
        address claimer,
        address recipient
    ) external returns (uint256 amount) {
        if (recipient == address(0)) revert BurnBomb_ZeroAddress();
        amount = claimablePayout[roundId][claimer];
        if (amount == 0) revert NothingToWithdraw();
        claimablePayout[roundId][claimer] = 0;
        emit PayoutWithdrawn(roundId, claimer, recipient, amount);
    }

    /// @dev Single-item seed dividend. Caller phase-checks SETTLED before invoking.
    function seedDividendSingle(
        uint256 roundId,
        address claimer,
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        mapping(uint256 => mapping(address => bool)) storage seedDividendClaimed,
        mapping(uint256 => mapping(address => uint256)) storage seedContribution
    ) external returns (uint256 amount) {
        BurnBombTypes.Round storage r = rounds[roundId];
        if (r.phase != PHASE_SETTLED) revert WrongPhase();
        if (seedDividendClaimed[roundId][claimer]) revert AlreadyClaimed();

        uint256 contrib = seedContribution[roundId][claimer];
        if (contrib == 0) revert NothingToWithdraw();

        amount = r.seedDividendPool * contrib / r.seedPotTotal;
        if (amount == 0) revert NothingToWithdraw();

        seedDividendClaimed[roundId][claimer] = true;
        emit SeedDividendWithdrawn(roundId, claimer, amount);
    }

    /// @dev Single-item refund. Caller phase-checks REFUNDED before invoking.
    function refundSingle(
        uint256 roundId,
        uint16 slotIndex,
        address claimer,
        mapping(uint256 => mapping(uint16 => address)) storage slotOwner,
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        uint256 contractBal,
        uint256 minSlot,
        uint256 slotStep
    ) external returns (uint256 amount) {
        if (slotOwner[roundId][slotIndex] != claimer) revert NotSlotOwner();
        BurnBombTypes.Round storage r = rounds[roundId];

        uint256 grossAmount = minSlot + uint256(slotIndex) * slotStep;
        amount = grossAmount;
        if (r.totalRetryBountyPaid > 0 && r.potTotal > 0) {
            uint256 shortfall = grossAmount * r.totalRetryBountyPaid / r.potTotal;
            amount = grossAmount - shortfall;
        }

        slotOwner[roundId][slotIndex] = address(0);

        if (amount > contractBal) amount = contractBal;
        emit RefundClaimed(roundId, claimer, slotIndex, amount);
    }

    /// @dev Forward pending burn rake. Validates non-zero, zeroes state,
    /// returns the amount for caller to transfer + emit-after-success.
    function forwardBurnRakePrep(
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        uint256 roundId
    ) external returns (uint256 amount) {
        BurnBombTypes.Round storage r = rounds[roundId];
        amount = r.pendingBurnRake;
        if (amount == 0) revert NothingToWithdraw();
        r.pendingBurnRake = 0;
    }
}
