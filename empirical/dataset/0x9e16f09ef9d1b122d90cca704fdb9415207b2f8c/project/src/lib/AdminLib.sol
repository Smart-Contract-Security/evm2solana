// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BurnBombTypes} from "./BurnBombTypes.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  AdminLib · v1.1 dual-oracle · external-linked library
//
//  Extracted from BurnBombV1_1's lifecycle/admin helpers:
//    - cancelVrfSubscriptionBody : pending-check + balance read + coordinator
//                                  cancel call, with all the live-round guards
//    - emergencyResolveBody      : phase pivot to REFUNDED with delay check
//
//  Pattern mirrors the other libs: external functions, storage refs, custom
//  errors mirror main contract selectors. ETH transfers stay in main contract
//  (none here — the coordinator handles the VRF balance return to recipient).
// ─────────────────────────────────────────────────────────────────────────────

library AdminLib {
    error WrongPhase();
    error EmergencyTooEarly();
    error ContractNotDeprecated();
    error BurnBomb_ZeroAddress();
    error ActiveRoundExists();
    error VrfRequestPending();
    error AlreadyActivated();
    error MustRequestBothFirst();
    error OverrideTooEarly();
    error AcceptedOracleNotFulfilled();
    error UseStandardActivate();
    error InvalidOracle();
    error HealthChecksIncomplete();
    error VrfReserveTooLow();
    error VrfStillPending();
    error HealthCheckRetryTooEarly();
    error AlreadyFulfilled();
    error NoPendingHealthCheck();
    error ZeroValue();
    error ExceedsReserveCap();
    error VrfTooEarly();
    error VrfRetryCapReached();

    // Phase ordinals (stay in sync with main contract enum).
    uint8 internal constant P_WAITING_FOR_RANDOMNESS = 5;
    uint8 internal constant P_RANDOMNESS_FULFILLED = 6;
    uint8 internal constant P_SETTLED = 7;
    uint8 internal constant P_REFUNDED = 8;

    event EmergencyRefundEnabled(uint256 indexed roundId);
    event RoundRefunded(uint256 indexed roundId);
    event VrfSubscriptionCancelled(address indexed recipient, uint256 amountRecovered);
    event SingleOracleActivationOverride(uint8 oracleAccepted, uint256 at);
    event Activated(address indexed owner, uint256 timestamp);
    event HealthCheckRetryReset(uint8 oracle, uint256 at);
    event VrfReserveToppedUp(address indexed funder, uint256 amount);

    /// @dev Body of topUpVrfReserve. Caller has nothing to check — payable handled at caller.
    /// Verifies msg.value > 0 and the cap, then forwards to coordinator.
    /// Codex M2 2026-05-25: cap prevents accidental overfunding lockup.
    function topUpVrfReserveBody(
        IVRFCoordinatorV2Plus coordinator,
        uint256 subId,
        uint256 currentBalance,
        uint256 maxBalance,
        uint256 msgValue,
        address msgSender
    ) external {
        if (msgValue == 0) revert ZeroValue();
        if (currentBalance + msgValue > maxBalance) revert ExceedsReserveCap();
        coordinator.fundSubscriptionWithNative{value: msgValue}(subId);
        emit VrfReserveToppedUp(msgSender, msgValue);
    }

    /// @dev Body of retryStuckHealthCheck. Caller checks onlyOwner + adminNotFrozen + !activated.
    /// Clears the pending request ID for the specified oracle so caller can re-fire fresh.
    /// Preflight §0.12 / Codex M1 2026-05-25.
    uint256 internal constant HEALTH_CHECK_RETRY_GRACE = 1 hours;

    function retryStuckHealthCheckBody(
        uint256 firstHealthRequestedAt,
        uint8 oracle,
        bool chainlinkHealthPassed,
        bool supraHealthPassed,
        uint256 chainlinkHealthRequestId,
        uint256 supraHealthNonce
    ) external returns (bool clearChainlink, bool clearSupra) {
        if (firstHealthRequestedAt == 0) revert NoPendingHealthCheck();
        if (block.timestamp < firstHealthRequestedAt + HEALTH_CHECK_RETRY_GRACE) revert HealthCheckRetryTooEarly();
        if (oracle == 1) {
            if (chainlinkHealthPassed) revert AlreadyFulfilled();
            // Codex M1 minor 2026-05-25: reject reset of an oracle that has no pending ID.
            if (chainlinkHealthRequestId == 0) revert NoPendingHealthCheck();
            emit HealthCheckRetryReset(oracle, block.timestamp);
            return (true, false);
        } else if (oracle == 2) {
            if (supraHealthPassed) revert AlreadyFulfilled();
            if (supraHealthNonce == 0) revert NoPendingHealthCheck();
            emit HealthCheckRetryReset(oracle, block.timestamp);
            return (false, true);
        } else revert InvalidOracle();
    }

    /// @dev Pre-body of requestRandomnessAgain — guards + bounty calc + mapping
    /// cleanup. Caller fires SupraLib.dualOracleRequest in main-context, then
    /// applies storage writes + pays bounty + emits event. Extracted for
    /// EIP-170 fit (R4 audit-approved pattern, re-applied in v10).
    function requestRandomnessAgainPre(
        BurnBombTypes.Round storage r,
        mapping(uint256 => uint256) storage clMap,
        mapping(uint256 => uint256) storage suMap,
        uint256 vrfRetryTimeout,
        uint32 maxChainlinkReqs,
        uint256 vrfRetryBounty,
        uint256 maxBountyPerRound
    ) external returns (uint256 bounty) {
        if (r.phase != P_WAITING_FOR_RANDOMNESS) revert WrongPhase();
        if (block.timestamp < r.vrfRequestedAt + vrfRetryTimeout) revert VrfTooEarly();
        if (r.retryCount >= maxChainlinkReqs - 1) revert VrfRetryCapReached();
        if (r.totalRetryBountyPaid + vrfRetryBounty <= maxBountyPerRound) {
            bounty = vrfRetryBounty;
            r.totalRetryBountyPaid += bounty;
        }
        if (r.chainlinkRequestId != 0) delete clMap[r.chainlinkRequestId];
        if (r.supraNonce != 0) delete suMap[r.supraNonce];
    }

    /// @dev Body of emergencyResolveStuckRound. Permissionless caller.
    /// Codex NB1 2026-05-25: tightened to ONLY accept randomness-stuck phases.
    /// Other phases have natural recovery paths (advancePhase + timer expiry);
    /// the 72h emergency refund exists specifically for VRF-stuck rounds.
    function emergencyResolveBody(
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        uint256 roundId,
        uint256 emergencyRefundDelay
    ) external {
        BurnBombTypes.Round storage r = rounds[roundId];
        uint8 p = r.phase;
        if (p != P_WAITING_FOR_RANDOMNESS && p != P_RANDOMNESS_FULFILLED) revert WrongPhase();
        if (block.timestamp < r.firstVrfRequestedAt + emergencyRefundDelay) revert EmergencyTooEarly();

        r.phase = P_REFUNDED;
        emit EmergencyRefundEnabled(roundId);
        emit RoundRefunded(roundId);
    }

    /// @dev Body of cancelVrfSubscription. Validates triple-gate, reads native
    /// balance for event emission, then calls coordinator cancel. Coordinator
    /// hands the balance to recipient internally.
    function cancelVrfSubscriptionBody(
        mapping(uint256 => BurnBombTypes.Round) storage rounds,
        IVRFCoordinatorV2Plus vrfCoordinator,
        uint256 vrfSubId,
        uint256 currentRoundId,
        bool deprecated_,
        address payable recipient
    ) external {
        if (!deprecated_) revert ContractNotDeprecated();
        if (recipient == address(0)) revert BurnBomb_ZeroAddress();

        if (currentRoundId != 0) {
            uint8 cur = rounds[currentRoundId].phase;
            if (cur != P_SETTLED && cur != P_REFUNDED) revert ActiveRoundExists();
        }

        if (vrfCoordinator.pendingRequestExists(vrfSubId)) {
            revert VrfRequestPending();
        }

        (, uint96 nativeBal, , , ) = vrfCoordinator.getSubscription(vrfSubId);
        vrfCoordinator.cancelSubscription(vrfSubId, recipient);
        emit VrfSubscriptionCancelled(recipient, uint256(nativeBal));
    }

    /// @dev Validation body of forceActivateSingleOracle. Pure (apart from
    /// reading args). Caller writes activated/degradedAtActivation/seasonStart
    /// and emits the Activated event.
    function validateForceActivate(
        bool activated_,
        uint256 chainlinkHealthRequestId,
        uint256 supraHealthNonce,
        bool chainlinkHealthPassed,
        bool supraHealthPassed,
        uint256 firstHealthRequestedAt,
        uint256 singleOracleOverrideDelay,
        uint8 oracleAccepted
    ) external view {
        if (activated_) revert AlreadyActivated();
        if (chainlinkHealthRequestId == 0 || supraHealthNonce == 0) revert MustRequestBothFirst();
        if (firstHealthRequestedAt == 0 ||
            block.timestamp < firstHealthRequestedAt + singleOracleOverrideDelay) {
            revert OverrideTooEarly();
        }
        if (oracleAccepted == 1) {
            if (!chainlinkHealthPassed) revert AcceptedOracleNotFulfilled();
            if (supraHealthPassed) revert UseStandardActivate();
        } else if (oracleAccepted == 2) {
            if (!supraHealthPassed) revert AcceptedOracleNotFulfilled();
            if (chainlinkHealthPassed) revert UseStandardActivate();
        } else {
            revert InvalidOracle();
        }
    }

    /// @dev Validation body of activate(). Pure. Caller writes activated +
    /// seasonStart and emits Activated. Pulls vrfReserve from caller via param.
    function validateActivate(
        bool activated_,
        uint256 vrfReserve,
        uint256 minVrfReserveToActivate,
        bool chainlinkDisabled,
        bool supraDisabled,
        bool chainlinkHealthPassed,
        bool supraHealthPassed
    ) external pure {
        if (activated_) revert AlreadyActivated();
        // MIN VRF reserve guard only applies when Chainlink is enabled.
        // Constructor flag `_chainlinkInitiallyDisabled=true` lets operator
        // activate Supra-only without Chainlink subscription funding.
        if (!chainlinkDisabled && vrfReserve < minVrfReserveToActivate) revert VrfReserveTooLow();
        if (!chainlinkDisabled && !chainlinkHealthPassed) revert HealthChecksIncomplete();
        if (!supraDisabled && !supraHealthPassed) revert HealthChecksIncomplete();
    }

    /// @dev v9: external Supra call portion of finalizeSupraRegistration().
    /// Main contract owns the supraRegistered flag check + write and event emit.
    /// Library only does the external addContractToWhitelist call. Pattern matches
    /// the other extracted body functions (state stays in main, external calls
    /// here for bytecode-saving DELEGATECALL semantics).
    function finalizeSupraRegistrationBody(
        address depositContract,
        uint128 maxGasPrice,
        uint128 maxGasLimit
    ) external {
        // address(this) under DELEGATECALL = main contract address (verified).
        // So this whitelists the main BurnBomb contract as a Supra consumer.
        IDepositSupraMin(depositContract).addContractToWhitelist(
            address(this),
            maxGasPrice,
            maxGasLimit
        );
    }
}

/// @dev Minimal interface (subset of main IDepositContract) so AdminLib doesn't
/// need to import the full Supra interface from the main contract file.
interface IDepositSupraMin {
    function addContractToWhitelist(address contractAddress, uint128 callbackGasPrice, uint128 callbackGasLimit) external;
}
