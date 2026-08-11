// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BurnBombTypes} from "./BurnBombTypes.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {ThroneLib} from "./ThroneLib.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  SettlementLib · v1.1 dual-oracle · external-linked library
//
//  Extracts the bulk-of-bytecode operations inside finalizeSettlement that
//  have no oracle-callback coupling:
//    - rankTop3      : nearest-target slot scan (winner / 2nd / 3rd)
//    - creditPayouts : winner/2nd/3rd/founder/keeper pull-payout crediting
//                      with the same fall-through rules as the inline version
//                      (any seat collision merges into the winner credit)
//
//  Pattern mirrors ThroneLib / BulkWithdrawLib / SupraLib:
//    - `external` functions; deploy as separate bytecode; delegate-called.
//    - Storage-ref args (mapping / dynamic array) where mutation is required.
//    - Custom errors mirror the main contract's selectors.
// ─────────────────────────────────────────────────────────────────────────────

library SettlementLib {
    error WrongPhase();
    error ZeroWinnerOnOverflow();

    // Mirror main contract event signatures — emitted via DELEGATECALL so the
    // emitting address is the main contract.
    event VrfReplenishOverflowToWinner(uint256 indexed roundId, address indexed winner, uint256 amount);
    event VrfReserveReplenished(uint256 indexed roundId, uint256 amount);
    event ThroneSnapshot(
        uint256 indexed roundId,
        address seat1Owner, uint256 seat1Size,
        address seat2Owner, uint256 seat2Size,
        address seat3Owner, uint256 seat3Size
    );
    event SeasonReset(uint64 oldSeasonStart, uint64 newSeasonStart);

    event RoundSettled(
        uint256 indexed roundId,
        address indexed winner,
        uint16 winningSlot,
        uint16 target,
        uint256 pot,
        uint256 winnerShare,
        address secondPlace,
        uint256 secondShare,
        address thirdPlace,
        uint256 thirdShare,
        uint256 seedDividendPool,
        uint256 burnRake,
        address founder,
        uint256 founderShare,
        uint256 keeperBounty,
        address keeper
    );

    /// @dev Scan claimed slots once, tracking the three slots closest to
    /// `target` by absolute distance. Ties broken by lower slot index (matches
    /// the inline version exactly).
    function rankTop3(
        mapping(uint256 => uint16[]) storage claimedSlotsByRound,
        uint256 roundId,
        uint16 target
    ) external view returns (uint16 first, uint16 second, uint16 third) {
        uint16[] storage slots = claimedSlotsByRound[roundId];
        uint256 n = slots.length;
        if (n == 0) revert WrongPhase();

        first = slots[0];
        uint32 d1 = _distance(first, target);

        uint32 d2 = type(uint32).max;
        uint32 d3 = type(uint32).max;

        for (uint256 i = 1; i < n; i++) {
            uint16 s = slots[i];
            uint32 d = _distance(s, target);

            if (d < d1 || (d == d1 && s < first)) {
                d3 = d2; third = second;
                d2 = d1; second = first;
                d1 = d;  first = s;
            } else if (d < d2 || (d == d2 && s < second)) {
                d3 = d2; third = second;
                d2 = d;  second = s;
            } else if (d < d3 || (d == d3 && s < third)) {
                d3 = d;  third = s;
            }
        }
    }

    function _distance(uint16 a, uint16 b) private pure returns (uint32) {
        return a > b ? uint32(a) - uint32(b) : uint32(b) - uint32(a);
    }

    /// @dev Credit the winner/second/third/founder/keeper into claimablePayout
    /// per the v1.1 fall-through rules: any duplicate or zero-address fallback
    /// merges into the winner credit (matches inline semantics).
    function creditPayouts(
        mapping(uint256 => mapping(address => uint256)) storage claimablePayout,
        uint256 roundId,
        address winner,
        address second,
        address third,
        address founderAtSettle,
        address keeper,
        uint256 winnerShare,
        uint256 secondShare,
        uint256 thirdShare,
        uint256 founderShare,
        uint256 keeperBounty
    ) external {
        claimablePayout[roundId][winner] += winnerShare;
        if (second != address(0) && second != winner) {
            claimablePayout[roundId][second] += secondShare;
        } else {
            claimablePayout[roundId][winner] += secondShare;
        }
        if (third != address(0) && third != winner && third != second) {
            claimablePayout[roundId][third] += thirdShare;
        } else {
            claimablePayout[roundId][winner] += thirdShare;
        }
        claimablePayout[roundId][founderAtSettle] += founderShare;
        claimablePayout[roundId][keeper] += keeperBounty;
    }

    /// @dev Season check + throne update + payout + snapshot. Returns the
    /// new seasonStartedAt (caller writes to storage) and the empty-seat
    /// overflow that should route to winner.
    function settleThrone(
        address[3] storage throne,
        uint256[3] storage throneSize,
        mapping(uint256 => mapping(address => uint256)) storage claimablePayout,
        uint64 seasonStartedAt,
        uint256 seasonLength,
        uint256 roundId,
        address roundCreator,
        uint256 pot,
        uint256 thronePool
    ) external returns (uint64 newSeasonStart, uint256 emptySeatOverflow) {
        newSeasonStart = seasonStartedAt;
        // (A) season reset
        if (block.timestamp >= uint256(seasonStartedAt) + seasonLength) {
            uint64 oldStart = seasonStartedAt;
            ThroneLib.wipe(throne, throneSize);
            newSeasonStart = uint64(block.timestamp);
            emit SeasonReset(oldStart, newSeasonStart);
        }
        // (B) update
        if (roundCreator != address(0)) {
            ThroneLib.update(throne, throneSize, roundCreator, pot);
        }
        // (C) payout
        (, emptySeatOverflow) = ThroneLib.payout(throne, thronePool, roundId, claimablePayout);

        // (D) snapshot
        emit ThroneSnapshot(
            roundId,
            throne[0], throneSize[0],
            throne[1], throneSize[1],
            throne[2], throneSize[2]
        );
    }

    /// @dev Emit the final RoundSettled event. Extracted because the 16-arg
    /// event materializes a large stack/memory frame; pulling it into a lib
    /// call collapses bytecode in the caller. Caller passes the snapshot.
    struct SettledSnapshot {
        uint256 roundId;
        address winner;
        uint16 winningSlot;
        uint16 target;
        uint256 pot;
        uint256 winnerShare;
        address secondPlace;
        uint256 secondShare;
        address thirdPlace;
        uint256 thirdShare;
        uint256 seedDividendPool;
        uint256 burnRake;
        address founder;
        uint256 founderShare;
        uint256 keeperBounty;
        address keeper;
    }
    function emitRoundSettled(SettledSnapshot memory S) external {
        emit RoundSettled(
            S.roundId, S.winner, S.winningSlot, S.target, S.pot, S.winnerShare,
            S.secondPlace, S.secondShare, S.thirdPlace, S.thirdShare,
            S.seedDividendPool, S.burnRake, S.founder, S.founderShare, S.keeperBounty, S.keeper
        );
    }

    /// @dev Positional emitter for RoundSettled. Bundles addresses + uints
    /// in parallel arrays to dodge the 16-arg stack pressure in the caller.
    /// Layout:
    ///   addrs[0]=winner, addrs[1]=secondPlace, addrs[2]=thirdPlace,
    ///   addrs[3]=founder, addrs[4]=keeper
    ///   nums[0]=roundId, nums[1]=winningSlot (cast back to uint16),
    ///   nums[2]=target (uint16), nums[3]=pot, nums[4]=winnerShare,
    ///   nums[5]=secondShare, nums[6]=thirdShare, nums[7]=seedDividendPool,
    ///   nums[8]=burnRake, nums[9]=founderShare, nums[10]=keeperBounty
    function emitRoundSettledPacked(address[5] memory addrs, uint256[11] memory nums) external {
        emit RoundSettled(
            nums[0], addrs[0], uint16(nums[1]), uint16(nums[2]), nums[3], nums[4],
            addrs[1], nums[5], addrs[2], nums[6], nums[7], nums[8],
            addrs[3], nums[9], nums[10], addrs[4]
        );
    }

    /// @dev Process the Chainlink half of the VRF replenish slice. Either:
    ///   (a) credits the overflow to the winner if the sub is already capped,
    ///   (b) partial top-up + overflow credit if the slice would cross the cap,
    ///   (c) full top-up of the sub.
    /// Called via DELEGATECALL — events emit from the main contract address;
    /// `address(this).balance` is the main contract's; the call's `value` flows
    /// from the main contract's balance into the VRF coordinator.
    function chainlinkReplenish(
        mapping(uint256 => mapping(address => uint256)) storage claimablePayout,
        IVRFCoordinatorV2Plus vrfCoordinator,
        uint256 vrfSubId,
        uint256 maxVrfReserveBalance,
        uint256 roundId,
        address winner,
        uint256 chainlinkSlice
    ) external {
        if (chainlinkSlice == 0) return;
        (, uint96 nativeBal, , , ) = vrfCoordinator.getSubscription(vrfSubId);
        uint256 currentNative = uint256(nativeBal);

        if (currentNative >= maxVrfReserveBalance) {
            if (winner == address(0)) revert ZeroWinnerOnOverflow();
            claimablePayout[roundId][winner] += chainlinkSlice;
            emit VrfReplenishOverflowToWinner(roundId, winner, chainlinkSlice);
        } else if (currentNative + chainlinkSlice > maxVrfReserveBalance) {
            uint256 topUp = maxVrfReserveBalance - currentNative;
            uint256 overflowAmt = chainlinkSlice - topUp;
            if (winner == address(0)) revert ZeroWinnerOnOverflow();
            claimablePayout[roundId][winner] += overflowAmt;
            emit VrfReplenishOverflowToWinner(roundId, winner, overflowAmt);
            vrfCoordinator.fundSubscriptionWithNative{value: topUp}(vrfSubId);
            emit VrfReserveReplenished(roundId, topUp);
        } else {
            vrfCoordinator.fundSubscriptionWithNative{value: chainlinkSlice}(vrfSubId);
            emit VrfReserveReplenished(roundId, chainlinkSlice);
        }
    }
}
