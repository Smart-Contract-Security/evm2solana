// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
//  BurnBomb · Minnow v1.1 (DUAL-ORACLE) — supersedes v1.1a
//
//  Motivated by the Chainlink VRF Ethereum-mainnet outage of 2026-05-25 which
//  stalled v1.1a pre-activation health checks for >75 min on multiple gas
//  lanes. This revision adds Supra dVRF V3 alongside Chainlink VRF v2.5 so
//  every randomness request (health check + round settlement) is fired at
//  BOTH oracles simultaneously. Whichever fulfills first wins; the second
//  callback is a graceful noop. Single-oracle dependency is eliminated.
//
//  Per spec (burnbomb/MINNOW-V1.1-DUAL-ORACLE-SPEC-V9.md, graduated v9 +
//  v10 F1-F5 fixes), this is "Option X": the contract OWNS its own Supra
//  subscription. Two-tx Supra bootstrap (v9 change): constructor calls
//  `addClientToWhitelist(gp, gl)` with value=0 + `depositFundClient{value:
//  msg.value}()`; `addContractToWhitelist(address(this), gp, gl)` is
//  DEFERRED to the post-deploy permissionless `finalizeSupraRegistration()`
//  because `address(this).code.length == 0` inside the constructor and
//  Supra's addContractToWhitelist enforces `extcodesize(target) > 0`.
//  Per-round VRF replenish is split 40% Chainlink / 60% Supra and
//  auto-deposited to each oracle's sub.
//
//  v10 fixes (post v9 R5 mainnet stuck-deploy, see POSTMORTEM 2026-05-26):
//    - F1: external `topUpSupraBalance() external payable` (closes
//      operational symmetry gap with `topUpVrfReserve()`)
//    - F2: deploy scripts compute SUPRA_SEED dynamically as
//      `getMinBalanceLimit() + SAFETY_BUFFER` (no more hardcoded constants)
//    - F3: MockSupraDeposit enforces real Supra invariants (strict-> at
//      generateRequest, ClientNotWhitelisted at depositFundClient)
//    - F4: preflight §0.10 + §0.15 + §0.16 rule additions
//    - F5: anvil-verify exercises both at-min AND at-min+buffer cases
//
//  All v1.1a features preserved:
//
//    §A  Throne royalty mechanic (3-seat creator leaderboard).
//        - WINNER_BPS 7250 → 7150; THRONE_BPS = 100 (1% of pot).
//        - Split 0.7 / 0.2 / 0.1 across seats 1 / 2 / 3.
//        - One-seat-per-creator rule (your biggest pot wins your seat).
//        - Throne UPDATE happens BEFORE throne PAYOUT in finalizeSettlement
//          so new ascenders earn their first throne payout on their
//          crowning round (operator-locked dramatic-payout design).
//        - 90-day season auto-reset; clock starts at activate().
//        - Empty throne seats overflow back to winner (matches v1.1's
//          VRF-cap-overflow pattern).
//    §B  On-chain Round.name (bytes32) + Round.imageURI (string).
//        - Fixes the v1.1 metadata oversight (creators' branding lived
//          off-chain only).
//        - Permanent + indexable by anyone; no backend dependency.
//    §C  Drop createRound() gas-only variants; only createRoundAndEnter
//        remains as the canonical opener (skin-in-the-game enforced at
//        the contract level).
//
//  Plus: Round.creator field added (needed for throne lookup; the address
//  was already emitted in RoundCreated but not stored on the struct).
//
//  UNCHANGED from v1.1 (verified preserved):
//    - VRF v2.5 + IMMUTABLE s_vrfCoordinator (no setCoordinator bypass)
//    - renounceOwnership() reverts unconditionally
//    - Single-active-round invariant
//    - Bulk withdraw functions (refund / payout / seed dividend)
//    - cancelVrfSubscription (deprecated + terminal + no-pending gates)
//    - freezeAdmin + adminNotFrozen on pause/unpause/cancelVrfSubscription
//    - Per-round tunable threshold (MIN/DEFAULT/MAX_THRESHOLD)
//    - VRF cap with overflow-to-winner
//    - 72h emergency refund path
//    - Pull-payment everywhere
//    - Two-step founder rotation (proposeFounderPayoutAddress + accept)
//    - Ownable2Step from OpenZeppelin (NOT Chainlink ConfirmedOwner)
//    - VRFConsumerBaseV2Plus NOT inherited (inline rawFulfillRandomWords)
//
//  Storage layout: independent from v1 + v1.1 (new deploy, not a proxy
//  upgrade). v1.1 (0x555b80b8...) will be deprecated as part of v1.1a
//  deploy; 0.05 Ξ VRF reserve recovered via cancelVrfSubscription.
//
//  See: burnbomb/MINNOW-V1.1-DUAL-ORACLE-SPEC-V9.md  (canonical SOT; v10 inherits)
//       burnbomb/POSTMORTEM-2026-05-26-v9-supra-min-balance-and-asymmetric-topup.md
//       burnbomb/MINNOW-V1.1-DUAL-ORACLE-SPEC.md   (historical-only, superseded by -V9)
//       burnbomb/POSTMORTEM-2026-05-25-chainlink-outage-and-supra-sloppiness/
//       burnbomb/MINNOW-V1.1A-SPEC.md   (predecessor design)
//       contracts/src/BurnBombV1_1a.sol (predecessor source - fork base)
// ─────────────────────────────────────────────────────────────────────────────

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

// v1.1a · External library extracted to fit EIP-170 24KB ceiling. ThroneLib
// owns the bubble-sort + one-seat-per-creator mutation logic; delegate-called
// from finalizeSettlement. ~1KB saved off main bytecode.
import {ThroneLib} from "./lib/ThroneLib.sol";

// v1.1 dual-oracle · Shared Round struct + external libraries extracted to
// fit EIP-170. BurnBombTypes hosts the Round struct so libraries can read
// main contract storage directly via storage references.
import {BurnBombTypes} from "./lib/BurnBombTypes.sol";

// v1.1 dual-oracle · Bulk withdraw loops extracted to fit EIP-170. Library
// computes per-item amounts via storage refs; main contract emits per-item
// events and performs the single ETH transfer (nonReentrant + CEI safety).
import {BulkWithdrawLib} from "./lib/BulkWithdrawLib.sol";

// v1.1 dual-oracle · Supra glue extracted to fit EIP-170. SupraLib owns the
// try/catch deposit + operator-pull bucket + balance/replenish/disable/enable
// bodies; main contract owns events and IDepositContract interface.
import {SupraLib} from "./lib/SupraLib.sol";

// v1.1 dual-oracle · Settlement math extracted to fit EIP-170. SettlementLib
// owns the rankTop3 scan + creditPayouts accounting; main contract orchestrates
// the BPS slice math, throne, replenish and event emit.
import {SettlementLib} from "./lib/SettlementLib.sol";

// v1.1 dual-oracle · Round lifecycle (enter + phase-advance) extracted to fit
// EIP-170. Both functions are large + called from multiple sites; one shared
// deployment via DELEGATECALL beats inline duplication.
import {LifecycleLib} from "./lib/LifecycleLib.sol";

// v1.1 dual-oracle · Admin / emergency / cancelVrfSubscription bodies extracted
// to fit EIP-170. Main contract owns the modifier surface; library owns the
// branching + coordinator call.
import {AdminLib} from "./lib/AdminLib.sol";

// ── Supra dVRF V3 interfaces (verified from Etherscan source) ──
// Router: 0x23726e27Ec79d421cf58C815D37748AfCaFeC9e4 (mainnet)
// Deposit (proxy): 0xb63b8391e666d21958b8b3459840594A12055D2d (impl 0xb9ffbcea1f...)
// Reference: github.com/Entropy-Foundation/supra-vrf-examples/blob/master/
//            supra_examples/src/PlayingCards_V2.sol
interface ISupraRouterContract {
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations,
        address _clientWalletAddress
    ) external returns (uint256);
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations,
        uint256 _clientSeed,
        address _clientWalletAddress
    ) external returns (uint256);
}

interface IDepositContract {
    function addClientToWhitelist(uint128 _maxGasPrice, uint128 _maxGasLimit) external payable;
    function addContractToWhitelist(address _contractAddress, uint128 _callbackGasPrice, uint128 _callbackGasLimit) external;
    function removeContractFromWhitelist(address _contractAddress) external;
    function depositFundClient() external payable;
    function withdrawFundClient(uint128 _amount) external;
    function checkClientFund(address _clientAddress) external view returns (uint128);
    function isContractWhitelisted(address _client, address _contract) external view returns (bool);
    function getMinBalanceLimit(uint128 _maxGasPrice, uint128 _maxGasLimit) external view returns (uint128);
}

// ─── VRF consumer logic — INLINED in v1.1 instead of inheriting VRFConsumerBaseV2Plus ───
//
// v1 inherited Chainlink's `VRFConsumerBaseV2Plus`, which exposes
// `setCoordinator(address)` to `owner()` (and current coordinator). That function
// is NOT virtual (cannot be overridden) and NOT guarded by our `adminNotFrozen`
// modifier. After `freezeAdmin()`, the owner could still swap `s_vrfCoordinator`
// to an attacker-controlled address that then injects chosen randomness via
// `rawFulfillRandomWords`. (Third Codex pass 2026-05-24 BLOCKER finding.)
//
// v1.1 fix: do NOT inherit the base. Inline only the bits we need:
//   - `s_vrfCoordinator` declared `immutable` (set once in constructor, can't change)
//   - `rawFulfillRandomWords` external dispatch with msg.sender == coordinator check
//   - `fulfillRandomWords` is now a plain `internal` virtual hook (no override)
//   - No `setCoordinator` surface exposed at all
//
// Ownership: switch from Chainlink's `ConfirmedOwner` (two-step transfer) to
// OpenZeppelin's `Ownable2Step` — same two-step UX, but decoupled from VRF.

contract BurnBombMinnowV1_1 is Ownable2Step, ReentrancyGuard, Pausable {
    // ─────────────────────────────────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────────────────────────────────

    error BurnBomb_ZeroAddress();
    error WrongPhase();
    error WrongValue();
    error SlotOutOfRange();
    error TxCapExceeded();
    error BatchValueMismatch();
    error EmptyBatch();
    error ContractDeprecated();
    error NotActivated();
    error AlreadyActivated();
    error AdminIsFrozen();
    error AlreadyFrozen();
    error AlreadyDeprecated();
    error NotProposedRecipient();
    error NoPendingProposal();
    error CannotFreezeWhilePaused();
    error InvalidConstructorParam();
    error VrfTooEarly();
    error VrfReserveTooLow();
    error VrfStillPending();
    error VrfRetryCapReached();
    error NothingToWithdraw();
    error ThresholdOutOfRange(uint256 supplied, uint256 min, uint256 max);
    error ZeroWinnerOnOverflow();
    error BatchTooLarge();
    /// @dev VRF callback dispatch — only the immutable coordinator can fulfill.
    error OnlyCoordinatorCanFulfill(address have, address want);
    /// @dev v1.1a NEW · Round metadata length caps for name + imageURI.
    error NameTooLong(uint256 length, uint256 max);
    error ImageURITooLong(uint256 length, uint256 max);

    // ── v1.1 dual-oracle NEW errors ──
    error OnlySupraRouter();
    error CannotDisableBoth();
    error InvalidOracle();
    error NotDeprecated();
    error SupraSeedTooLow(uint128 sent, uint128 required);
    error OnlySelfCall();
    error TransferFailed();
    error SupraAlreadyRegistered();
    error SupraNotRegistered();

    // ─────────────────────────────────────────────────────────────────────
    //  Constants (audit-fixed)
    // ─────────────────────────────────────────────────────────────────────

    uint16  public constant MAX_ENTRIES_PER_ADDRESS = 50;
    uint16  public constant MAX_ENTRIES_PER_TX = 10;
    uint256 public constant EMERGENCY_REFUND_DELAY = 72 hours;
    uint256 internal constant VRF_RETRY_TIMEOUT = 30 minutes;
    // v9 byte recovery: internal — used only in retry-bounty calc, no UI readers.
    uint256 internal constant VRF_RETRY_BOUNTY = 0.0001 ether;
    uint256 internal constant MAX_VRF_RETRY_BOUNTY_PER_ROUND = 0.005 ether;
    uint32  internal constant MAX_CHAINLINK_REQUESTS_PER_ROUND = 3;

    // Pot split · v1.1a carves 100 BPS from WINNER (was 7250) for THRONE.
    //   v1.1   : WINNER=7250, ..., total 10000 (no THRONE slice)
    //   v1.1a  : WINNER=7150, THRONE=100, ..., total 10000
    // See MINNOW-V1.1A-SPEC.md §4 for the BPS conservation proof + winnerShare
    // worst-case underflow check at MIN_THRESHOLD (winnerShare ≈ 0.00577 Ξ).
    uint16  public constant WINNER_BPS  = 7150;  // v1.1a: was 7250 in v1.1
    uint16  public constant SECOND_BPS  = 650;
    uint16  public constant THIRD_BPS   = 350;
    uint16  public constant SEED_BPS    = 1000;
    uint16  public constant RAKE_BPS    = 500;
    uint16  public constant FOUNDER_BPS = 50;
    uint16  public constant KEEPER_BPS  = 100;
    uint16  public constant VRF_REPLENISH_BPS = 100;
    uint256 public constant KEEPER_CAP = 0.01 ether;
    uint16  public constant BPS_DENOM  = 10000;

    uint256 public constant MIN_VRF_RESERVE_TO_ACTIVATE = 0.025 ether;

    address public constant BURN_TOKEN = 0x886fab7097311af73C74DD608001a0d267AbF351;

    address public constant VRF_COORDINATOR_MAINNET = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
    uint16  public constant VRF_REQUEST_CONFIRMATIONS = 3;
    uint32  public constant VRF_CALLBACK_GAS_LIMIT = 500000;
    uint32  internal constant VRF_NUM_WORDS = 1;

    // ── v1.1 dual-oracle · Supra dVRF V3 constants ──
    // v9 byte recovery: switched to internal — internal Supra call params, no UI readers.
    uint8   internal constant SUPRA_RNG_COUNT = 1;
    uint256 internal constant SUPRA_CONFIRMATIONS = 1;
    // Max gas price + callback gas limit are IMMUTABLE constructor args
    // (not constants) so the same code can deploy to mainnet (50 gwei / 500k)
    // and sepolia (1 gwei / 100k) with appropriate Supra getMinBalanceLimit
    // for each. The on-chain minimum scales linearly with maxGasPrice ×
    // callbackGasLimit, so tuning these tunes capital lock at deploy time.
    uint128 public immutable SUPRA_MAX_GAS_PRICE;
    uint128 public immutable SUPRA_CALLBACK_GAS_LIMIT;
    /// @notice v9 byte recovery: internal (zero external refs in frontend/tests/scripts).
    /// Advisory threshold for operator-monitor view; not used in contract logic.
    uint96  internal constant MIN_SUPRA_BALANCE = 0.025 ether;
    /// @notice v9 byte recovery: internal (zero external refs). Operational floor
    /// enforced by withdrawSupraBalance (pre-deprecate); used only inside SupraLib.
    uint128 internal constant SUPRA_OPERATIONAL_FLOOR = 0.02 ether;
    /// @notice Time delay after first health request before single-oracle force-activate is callable.
    uint256 public constant SINGLE_ORACLE_OVERRIDE_DELAY = 24 hours;

    // ── v1.1 new constants (per spec §2.2, §3.2, §5.5) ──

    /// @notice Minimum allowed threshold for a round.
    /// Math floor for winnerShare-underflow safety:
    ///   MAX_VRF_RETRY_BOUNTY_PER_ROUND / (1 - SUM_OTHER_BPS/BPS_DENOM)
    ///   = 0.005 / 0.725 ≈ 0.0069 ETH.
    /// 0.015 gives ~2.17x headroom. (sub-agent audit 2026-05-24)
    uint256 public constant MIN_THRESHOLD = 0.015 ether;

    /// @notice Default threshold for the no-arg createRound() overload.
    /// Operator-chosen (2026-05-24) at 0.05 ETH to encourage meaningful
    /// seed commitment while remaining tunable down to MIN_THRESHOLD.
    uint256 public constant DEFAULT_THRESHOLD = 0.05 ether;

    /// @notice Maximum allowed threshold for a round.
    /// Conservative ceiling against unreachable thresholds.
    uint256 public constant MAX_THRESHOLD = 1 ether;

    /// @notice VRF sub balance cap. At or above this, the per-round VRF
    /// replenish slice flows to the round winner instead of to Chainlink.
    uint256 internal constant MAX_VRF_RESERVE_BALANCE = 0.05 ether;

    /// @notice Maximum array length for any batch withdraw call.
    /// Bracket-independent — NOT derived from NUM_SLOTS. Future brackets
    /// (Dolphin 1000-slot etc.) keep this at ~100 for gas safety regardless
    /// of their NUM_SLOTS. Do not refactor as shared-with-NUM_SLOTS constant.
    /// (sub-agent audit 2026-05-24)
    uint256 public constant MAX_BATCH_SIZE = 100;

    // ── v1.1a NEW · Throne royalty mechanic ──
    // See MINNOW-V1.1A-SPEC.md §2 for full rationale. Top-3 creators ranked
    // by largest-ever round pot earn 1% of every future pot (split 70/20/10).
    // 90-day seasons. One-seat-per-creator (biggest pot wins their seat).
    // Throne UPDATE happens BEFORE PAYOUT — new ascenders earn their first
    // payout on their crowning round (operator-locked dramatic design).

    /// @notice 1% of pot carved from WINNER_BPS for the throne pool.
    uint16  public constant THRONE_BPS = 100;
    /// @notice Throne seat split — MUST sum to 100. Encoded as separate
    /// constants for audit clarity vs an array index lookup.
    uint16  public constant THRONE_SEAT_1_BPS_OF_THRONE = 70;
    uint16  public constant THRONE_SEAT_2_BPS_OF_THRONE = 20;
    uint16  public constant THRONE_SEAT_3_BPS_OF_THRONE = 10;
    /// @notice Season duration. After this elapsed since the last reset
    /// (anchored at activate()), the next finalizeSettlement wipes the
    /// throne to empty and re-anchors the timer.
    uint256 public constant SEASON_LENGTH = 90 days;

    // ── v1.1a NEW · Round metadata length caps ──
    /// @notice Max bytes for Round.name (UTF-8). Frontend's NAME_MAX=32
    /// reflects this cap. Multi-byte chars (emoji = 4 bytes) reduce
    /// effective char count.
    uint256 public constant MAX_NAME_BYTES = 32;
    /// @notice Max bytes for Round.imageURI. Fits IPFS CIDs (~46 chars),
    /// most HTTPS URLs, and Arweave URIs. Caps gas griefing potential.
    uint256 public constant MAX_IMAGE_URI_BYTES = 256;

    // ─────────────────────────────────────────────────────────────────────
    //  Immutables (bracket parameters set at deploy)
    // ─────────────────────────────────────────────────────────────────────

    uint256 public immutable MIN_SLOT;
    uint256 public immutable SLOT_STEP;
    uint16  public immutable NUM_SLOTS;
    // NOTE: v1's `uint256 public immutable THRESHOLD;` REMOVED in v1.1.
    // Threshold is per-round, lives on Round.threshold (set in createRound).
    // See spec §2.7 CRITICAL IMPLEMENTATION DIRECTIVE.

    uint256 public immutable SEED_PHASE_MAX;
    uint256 public immutable ACTIVE_TIMER;
    uint256 public immutable ACTIVE_PHASE_MAX;
    uint256 public immutable FINAL_COUNTDOWN;

    bytes32 public immutable VRF_KEY_HASH;
    uint256 public immutable VRF_SUB_ID;

    /// @notice Chainlink VRF coordinator. IMMUTABLE in v1.1 — cannot be swapped
    /// post-deploy. (v1 inherited a mutable `s_vrfCoordinator` from
    /// VRFConsumerBaseV2Plus exposed via `setCoordinator()`; v1.1 removes that
    /// attack surface entirely. Codex 2026-05-24.)
    IVRFCoordinatorV2Plus public immutable s_vrfCoordinator;

    /// @notice Supra dVRF V3 router. IMMUTABLE — analogous to s_vrfCoordinator
    /// (no setter surface, hardened against post-deploy swap).
    address public immutable s_supraRouter;

    /// @notice Supra Deposit Contract proxy. IMMUTABLE. Holds the contract's
    /// own Supra subscription balance (Option X / contract-owned sub model).
    address public immutable s_supraDepositContract;

    // ─────────────────────────────────────────────────────────────────────
    //  Storage
    // ─────────────────────────────────────────────────────────────────────

    enum Phase {
        NONE,
        SEEDING,
        ACTIVE,
        FINAL_COUNTDOWN,
        READY_TO_REQUEST_RANDOMNESS,
        WAITING_FOR_RANDOMNESS,
        RANDOMNESS_FULFILLED,
        SETTLED,
        REFUNDED
    }

    // Round struct now lives in BurnBombTypes (shared with BulkWithdrawLib for
    // direct storage access). Layout/semantics unchanged from v1.1a — see
    // contracts/src/lib/BurnBombTypes.sol for the full field-by-field doc.

    uint256 public currentRoundId;
    mapping(uint256 => BurnBombTypes.Round) public rounds;

    mapping(uint256 => mapping(uint16 => address)) public slotOwner;
    mapping(uint256 => uint16[]) private _claimedSlots;

    mapping(uint256 => mapping(address => uint16)) public addressEntryCount;
    mapping(uint256 => mapping(address => uint16[])) public addressSlots;

    mapping(uint256 => mapping(address => uint256)) public seedContribution;
    mapping(uint256 => mapping(address => bool)) public seedDividendClaimed;

    mapping(uint256 => mapping(address => uint256)) public claimablePayout;

    // v1.1 dual-oracle: renamed for clarity (was vrfRequestIdToRoundId).
    mapping(uint256 => uint256) public chainlinkRequestIdToRoundId;
    mapping(uint256 => uint256) public supraNonceToRoundId;

    // ── v1.1 dual-oracle · per-oracle health check state ──
    uint256 public chainlinkHealthRequestId;
    uint256 public supraHealthNonce;
    bool    public chainlinkHealthPassed;
    bool    public supraHealthPassed;
    /// @notice Timestamp of the first dual-oracle health request. Anchors the
    /// SINGLE_ORACLE_OVERRIDE_DELAY clock for forceActivateSingleOracle.
    uint256 public firstHealthRequestedAt;
    /// @notice True iff activate() was bypassed via forceActivateSingleOracle.
    /// One-shot, irreversible — production UI surfaces a warning.
    bool    public degradedAtActivation;

    // ── v1.1 dual-oracle · per-oracle disable flags ──
    bool public chainlinkDisabled;
    bool public supraDisabled;

    /// @notice ETH accrued when auto-Supra deposit reverts. Operator-pull
    /// fallback so funds never strand.
    uint96 public pendingSupraReplenish;

    bool public adminFrozen;
    bool public deprecated;
    bool public activated;
    /// @notice v9: post-deploy Supra consumer-registration completion flag.
    /// Set by finalizeSupraRegistration(); one-way. Until true, all Supra
    /// request paths revert SupraNotRegistered. See spec v9 for full design.
    /// Public for auto-getter (matches canonical name from spec; opt #1
    /// internal+explicit-view was tested and produced no savings).
    bool public supraRegistered;

    address public founderPayout;
    address public pendingFounderPayout;

    // ── v1.1a NEW · Throne royalty state ──
    // throne[0] = seat 1 (highest); throne[2] = seat 3 (lowest). Empty seats
    // are address(0) with throneSize 0. Sorted descending by throneSize with
    // ties favoring incumbent. One-seat-per-creator enforced in _updateThrone.
    address[3] public throne;
    uint256[3] public throneSize;

    /// @notice 90-day season anchor. Set in activate() so the clock aligns
    /// with operational launch (NOT deploy time). Reset in finalizeSettlement
    /// when block.timestamp >= seasonStartedAt + SEASON_LENGTH.
    uint64 public seasonStartedAt;

    // ─────────────────────────────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────────────────────────────

    // v1.1 SIGNATURE CHANGE: appends `threshold` so off-chain consumers see
    // the per-round value without an extra read.
    // v1.1a SIGNATURE CHANGE: adds `name` + `imageURI` so off-chain consumers
    // can render branded rounds from the event stream alone (no contract read needed).
    event RoundCreated(
        uint256 indexed roundId,
        address indexed creator,
        uint256 createdAt,
        uint256 threshold,
        string name,
        string imageURI
    );
    // v1.1a NEW · Throne event surface (size-optimized per Codex audit)
    /// @notice Emitted ONCE per finalizeSettlement with the deterministic
    /// post-state snapshot of the throne. Indexers compute per-seat diffs
    /// by comparing successive ThroneSnapshot events from the same round-id
    /// stream — cleaner than reconstructing from interleaved per-seat events.
    event ThroneSnapshot(
        uint256 indexed roundId,
        address seat1Owner,
        uint256 seat1Size,
        address seat2Owner,
        uint256 seat2Size,
        address seat3Owner,
        uint256 seat3Size
    );
    /// @notice Emitted when the 90-day season auto-resets in finalizeSettlement.
    /// The accompanying ThroneSnapshot in the same tx shows the wiped (zeroed) state.
    event SeasonReset(uint64 oldSeasonStart, uint64 newSeasonStart);

    event SlotClaimed(uint256 indexed roundId, uint16 indexed slotIndex, address indexed claimer, uint256 value);
    event PhaseTransition(uint256 indexed roundId, Phase oldPhase, Phase newPhase);
    event ThresholdMet(uint256 indexed roundId, uint256 potAtThreshold);
    event FinalCountdownStarted(uint256 indexed roundId);
    event ReadyToRequestRandomness(uint256 indexed roundId);

    // v7's RandomnessRequested removed in v9 — superseded by DualOracleRequested below,
    // which carries both Chainlink requestId + Supra nonce in a single emit per round.
    // Spec MINNOW-V1.1-DUAL-ORACLE-SPEC-V9.md telemetry section updated to mark
    // DualOracleRequested as the canonical per-round oracle-fire event.
    /// @notice v1.1 dual-oracle SIGNATURE CHANGE: adds oracle id + latency.
    event RandomnessFulfilled(
        uint256 indexed roundId,
        uint256 randomWord,
        uint8 oracle,
        uint256 fulfillmentLatencySec
    );
    event RandomnessRetried(uint256 indexed roundId, address indexed caller, uint256 indexed newRequestId, uint256 bountyPaid);
    event VrfReserveReplenished(uint256 indexed roundId, uint256 amount);
    /// @notice v9: oracle field added per spec — Chainlink emits oracle=1, Supra emits oracle=2.
    /// Source audit BLOCKER-1 fix 2026-05-26: previously was 1-arg + only Chainlink emitted.
    event VrfHealthCheckRequested(uint256 indexed requestId, uint8 oracle);
    event VrfHealthCheckFulfilled(uint256 indexed requestId, uint256 randomWord, uint8 oracle);
    event BurnRakeForwardDeferred(uint256 indexed roundId, uint256 amount);
    event BurnRakeForwarded(uint256 indexed roundId, uint256 amount);

    // ── v1.1 dual-oracle · new events ──
    event DualOracleRequested(uint256 indexed roundId, uint256 chainlinkRequestId, uint256 supraNonce, uint256 requestedAt);
    /// @notice v9: idOrNonce added per audit round 3 MINOR-3 for indexer correlation
    /// (restored after dead-weight scan freed bytecode budget 2026-05-26).
    event LateFulfillmentIgnored(uint256 indexed roundId, uint8 oracle, uint256 randomWord, uint256 idOrNonce);
    /// @notice v9: post-deploy Supra consumer-registration completion event,
    /// RESTORED per operator decision 2026-05-26 — auditable on-chain confirmation
    /// of finalize completion is operationally important for deploy verification.
    event SupraRegistrationFinalized(address indexed contractAddr, uint256 at);
    event OrphanCallback(uint8 oracle, uint256 idOrNonce);
    event OracleRequestFailed(uint256 indexed roundId, uint8 oracle);
    event SupraSubscriptionFunded(uint256 amount, address indexed beneficiary);
    event SupraReplenishDeferred(uint256 amount);
    // v9: indexed added on `to`/`by` per source audit MAJOR-3 — matches canonical spec ABI for indexer filtering.
    event SupraReplenishWithdrawn(address indexed to, uint96 amount);
    event SupraBalanceWithdrawn(address indexed to, uint128 amount);
    event SingleOracleActivationOverride(uint8 oracleAccepted, uint256 at);
    event OracleDisabled(uint8 oracle, address indexed by, uint256 at);
    event OracleEnabled(uint8 oracle, address indexed by, uint256 at);

    // v1.1 NEW: VRF replenish slice flowed (partially or fully) to winner
    // because the shared sub was at/above MAX_VRF_RESERVE_BALANCE.
    event VrfReplenishOverflowToWinner(uint256 indexed roundId, address indexed winner, uint256 amount);

    // v1.1 NEW: sub balance recovered on retire.
    event VrfSubscriptionCancelled(address indexed recipient, uint256 amountRecovered);

    // R1 MINOR-1 (2026-05-27): ABI-discoverability re-declarations for events
    // emitted from AdminLib via DELEGATECALL. The runtime log uses the main
    // contract address, so indexers/frontends building from THIS contract's
    // ABI need the event signatures here to decode them. Zero runtime cost:
    // events are not emitted from main (AdminLib does the actual `emit`), so
    // no bytecode is added; this only enriches the ABI surface.
    event VrfReserveToppedUp(address indexed funder, uint256 amount);
    event HealthCheckRetryReset(uint8 oracle, uint256 at);

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
    event RoundRefunded(uint256 indexed roundId);

    event PayoutWithdrawn(uint256 indexed roundId, address indexed account, address indexed recipient, uint256 amount);
    event SeedDividendWithdrawn(uint256 indexed roundId, address indexed account, uint256 amount);
    event RefundClaimed(uint256 indexed roundId, address indexed account, uint16 indexed slotIndex, uint256 amount);

    event FounderPayoutProposed(address indexed current, address indexed proposed);
    event FounderPayoutAccepted(address indexed old, address indexed accepted);

    event EmergencyRefundEnabled(uint256 indexed roundId);
    event AdminFrozen(address indexed owner);
    event Deprecated(address indexed owner, uint256 timestamp);
    event Activated(address indexed owner, uint256 timestamp);

    // ─────────────────────────────────────────────────────────────────────
    //  Modifiers
    // ─────────────────────────────────────────────────────────────────────

    modifier adminNotFrozen() {
        if (adminFrozen) revert AdminIsFrozen();
        _;
    }

    modifier notDeprecated() {
        if (deprecated) revert ContractDeprecated();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Constructor
    //
    //  v1.1 CHANGE: _threshold parameter REMOVED (per spec §2.7).
    //  Threshold is now per-round; bracket-level safety is provided by
    //  MIN_THRESHOLD/MAX_THRESHOLD constants enforced in createRound.
    //  v1's `if (_threshold < 10 * MAX_VRF_RETRY_BOUNTY_PER_ROUND) ...`
    //  safety check is also removed — equivalent safety lives in the
    //  ThresholdOutOfRange check at round-creation time.
    // ─────────────────────────────────────────────────────────────────────

    /// @param _chainlinkInitiallyDisabled If true, contract deploys with
    /// `chainlinkDisabled = true`. Allows operator to fire Supra-only
    /// healthcheck (no Chainlink top-up required) and activate Supra-only.
    /// Later `enableOracle(1)` flips Chainlink on for dual-oracle operation.
    /// Use case: avoid v1.1a-style stuck Chainlink subscription funds at
    /// deploy time. Default `false` for legacy/dual-oracle deploys.
    constructor(
        address _vrfCoordinator,
        address _supraRouter,
        address _supraDepositContract,
        bytes32 _vrfKeyHash,
        uint128 _supraMaxGasPrice,
        uint128 _supraCallbackGasLimit,
        uint256 _minSlot,
        uint256 _slotStep,
        uint16 _numSlots,
        uint256 _seedPhaseMax,
        uint256 _activeTimer,
        uint256 _activePhaseMax,
        uint256 _finalCountdown,
        address _founderPayout,
        bool _chainlinkInitiallyDisabled
    ) payable {
        if (_vrfCoordinator == address(0)) revert BurnBomb_ZeroAddress();
        if (_supraRouter == address(0)) revert BurnBomb_ZeroAddress();
        if (_supraDepositContract == address(0)) revert BurnBomb_ZeroAddress();
        if (_founderPayout == address(0)) revert BurnBomb_ZeroAddress();
        if (_vrfKeyHash == bytes32(0)) revert InvalidConstructorParam();

        if (_supraMaxGasPrice == 0) revert InvalidConstructorParam();
        if (_supraCallbackGasLimit == 0) revert InvalidConstructorParam();
        SUPRA_MAX_GAS_PRICE = _supraMaxGasPrice;
        SUPRA_CALLBACK_GAS_LIMIT = _supraCallbackGasLimit;

        if (_minSlot == 0) revert InvalidConstructorParam();
        if (_slotStep == 0) revert InvalidConstructorParam();
        if (_numSlots < 3 || _numSlots > 10000) revert InvalidConstructorParam();
        if (_seedPhaseMax == 0) revert InvalidConstructorParam();
        if (_activeTimer == 0) revert InvalidConstructorParam();
        if (_activePhaseMax < _activeTimer) revert InvalidConstructorParam();
        if (_finalCountdown == 0) revert InvalidConstructorParam();

        // MAX_THRESHOLD must be reachable: sum of all slots at face value must
        // be ≥ MAX_THRESHOLD. Otherwise a creator could pick a threshold that
        // can never be crossed even if every slot fills.
        //   sum of slots = MIN_SLOT × N + SLOT_STEP × (N×(N-1)/2)
        uint256 maxPossiblePot =
            _minSlot * uint256(_numSlots) + _slotStep * (uint256(_numSlots) * (uint256(_numSlots) - 1) / 2);
        if (MAX_THRESHOLD > maxPossiblePot) revert InvalidConstructorParam();

        VRF_KEY_HASH = _vrfKeyHash;
        MIN_SLOT = _minSlot;
        SLOT_STEP = _slotStep;
        NUM_SLOTS = _numSlots;
        SEED_PHASE_MAX = _seedPhaseMax;
        ACTIVE_TIMER = _activeTimer;
        ACTIVE_PHASE_MAX = _activePhaseMax;
        FINAL_COUNTDOWN = _finalCountdown;

        founderPayout = _founderPayout;

        // v1.1: bind coordinator IMMUTABLY — no setCoordinator surface (Codex 2026-05-24).
        s_vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);

        // Self-own Chainlink VRF subscription
        VRF_SUB_ID = s_vrfCoordinator.createSubscription();
        s_vrfCoordinator.addConsumer(VRF_SUB_ID, address(this));

        // ── v1.1 dual-oracle · Supra self-registration (Option X) ──
        s_supraRouter = _supraRouter;
        s_supraDepositContract = _supraDepositContract;

        uint128 supraMin = IDepositContract(_supraDepositContract).getMinBalanceLimit(
            SUPRA_MAX_GAS_PRICE,
            SUPRA_CALLBACK_GAS_LIMIT
        );
        if (msg.value < supraMin) revert SupraSeedTooLow(uint128(msg.value), supraMin);
        // v9: Supra's addClientToWhitelist is NOT payable in practice (reverts on
        // any msg.value > 0). Funding is a separate depositFundClient call.
        // addContractToWhitelist is DEFERRED to finalizeSupraRegistration()
        // because address(this).code.length == 0 inside the constructor and
        // Supra's addContractToWhitelist enforces extcodesize(target) > 0.
        // supraRegistered remains FALSE until finalizeSupraRegistration() is called.
        IDepositContract(_supraDepositContract).addClientToWhitelist(
            SUPRA_MAX_GAS_PRICE,
            SUPRA_CALLBACK_GAS_LIMIT
        );
        IDepositContract(_supraDepositContract).depositFundClient{value: msg.value}();

        // Optional Chainlink-disabled-at-deploy: skips Chainlink fire in
        // requestVrfHealthCheck + lets activate() succeed without CL flag /
        // CL reserve. Operator can `enableOracle(1)` post-activation to wire
        // Chainlink in once they're ready (e.g. after v1.1a recovery).
        // NOTE: this bypasses the B3 pre-activation disable guard by design —
        // committed at construction time, locked in the deploy tx for audit.
        if (_chainlinkInitiallyDisabled) {
            chainlinkDisabled = true;
            emit OracleDisabled(1, msg.sender, block.timestamp);
        }
    }

    /// @notice v9: Post-deploy completion of Supra consumer registration.
    /// Permissionless (msg.sender to Supra is address(this), which IS the
    /// registered client). Idempotent — second call reverts. One-way state
    /// transition. No notDeprecated/adminNotFrozen gate (per v9 spec
    /// Lifecycle invariant 2). Must be called once before requestVrfHealthCheck.
    function finalizeSupraRegistration() external {
        if (supraRegistered) revert SupraAlreadyRegistered();
        IDepositContract(s_supraDepositContract).addContractToWhitelist(
            address(this),
            SUPRA_MAX_GAS_PRICE,
            SUPRA_CALLBACK_GAS_LIMIT
        );
        supraRegistered = true;
        emit SupraRegistrationFinalized(address(this), block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  VRF callback dispatch · INLINED (replaces VRFConsumerBaseV2Plus)
    //
    //  rawFulfillRandomWords is the entry point Chainlink coordinators call
    //  to deliver fulfilled randomness. Gate it by msg.sender == the IMMUTABLE
    //  s_vrfCoordinator so the consumer accepts callbacks ONLY from the
    //  coordinator bound at deploy. No setCoordinator() surface means there
    //  is no admin path to swap the trusted source post-deploy — closes the
    //  freezeAdmin-bypass vector inherited from VRFConsumerBaseV2Plus in v1.
    // ─────────────────────────────────────────────────────────────────────

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(s_vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(s_vrfCoordinator));
        }
        fulfillRandomWords(requestId, randomWords);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Pricing helpers
    // ─────────────────────────────────────────────────────────────────────

    function slotValue(uint16 slotIndex) public view returns (uint256) {
        return MIN_SLOT + uint256(slotIndex) * SLOT_STEP;
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Round lifecycle
    // ─────────────────────────────────────────────────────────────────────

    /// @notice v1.1a: ONLY entry point for opening a round. Creator commits
    /// a slot of their choosing in the same transaction, paying its face value.
    /// Skin-in-the-game enforced at the contract level (v1.1's gas-only
    /// `createRound()` variants are REMOVED in v1.1a per spec §5).
    /// @param threshold      Must be in [MIN_THRESHOLD, MAX_THRESHOLD].
    /// @param slotIdx        Slot index to claim. msg.value must equal slotValue(slotIdx).
    /// @param name           UTF-8 round name; max MAX_NAME_BYTES (32). Empty = default rendering.
    /// @param imageURI       Image URI (ipfs/https/ar); max MAX_IMAGE_URI_BYTES (256). Empty = default.
    function createRoundAndEnter(
        uint256 threshold,
        uint16 slotIdx,
        string calldata name,
        string calldata imageURI
    )
        external
        payable
        whenNotPaused
        returns (uint256 roundId)
    {
        // Activation / deprecation / single-active-round guard (library pure
        // helper to keep the validation block off main bytecode).
        LifecycleLib.checkCreateRoundActivation(
            activated,
            deprecated,
            currentRoundId == 0 ? 0 : rounds[currentRoundId].phase,
            currentRoundId
        );
        // Metadata + threshold + slot-range bounds (kept inline — small, and
        // mixed with NameTooLong custom error reverts).
        if (bytes(name).length > MAX_NAME_BYTES) {
            revert NameTooLong(bytes(name).length, MAX_NAME_BYTES);
        }
        if (bytes(imageURI).length > MAX_IMAGE_URI_BYTES) {
            revert ImageURITooLong(bytes(imageURI).length, MAX_IMAGE_URI_BYTES);
        }
        if (threshold < MIN_THRESHOLD || threshold > MAX_THRESHOLD) {
            revert ThresholdOutOfRange(threshold, MIN_THRESHOLD, MAX_THRESHOLD);
        }
        if (slotIdx >= NUM_SLOTS) revert SlotOutOfRange();
        uint256 requiredValue = slotValue(slotIdx);
        if (msg.value != requiredValue) revert WrongValue();

        roundId = currentRoundId + 1;
        currentRoundId = roundId;

        LifecycleLib.createRoundSetup(
            rounds, roundId, threshold, SEED_PHASE_MAX, msg.sender, name, imageURI
        );

        // Reuse the EXACT v1.1 entry path. _enterSingleInternal handles all
        // address-cap, slot-taken, claimed-slot-array, address-slots, and
        // seed-contribution accounting — and any same-tx auto-transition
        // (threshold-cross to ACTIVE, sold-out fast-track).
        _enterSingleInternal(roundId, slotIdx, requiredValue);
    }

    /// @notice Single-slot entry. msg.value must equal exact slot value.
    function enter(uint256 roundId, uint16 slotIndex)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        _advancePhase(roundId);
        _enterSingle(roundId, slotIndex, msg.value);
        _advancePhase(roundId);
    }

    /// @notice Batch entry. msg.value must equal exact sum of slot values.
    function enterBatch(uint256 roundId, uint16[] calldata slotIndexes)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        if (slotIndexes.length == 0) revert EmptyBatch();
        if (slotIndexes.length > MAX_ENTRIES_PER_TX) revert TxCapExceeded();

        _advancePhase(roundId);

        uint256 totalRequired = 0;
        for (uint256 i = 0; i < slotIndexes.length; i++) {
            uint16 idx = slotIndexes[i];
            uint256 v = slotValue(idx);
            totalRequired += v;
            _enterSingleInternal(roundId, idx, v);
        }

        if (msg.value != totalRequired) revert BatchValueMismatch();

        _advancePhase(roundId);
    }

    function _enterSingle(uint256 roundId, uint16 slotIndex, uint256 value) internal {
        uint256 v = slotValue(slotIndex);
        if (value != v) revert WrongValue();
        _enterSingleInternal(roundId, slotIndex, v);
    }

    /// @dev Thin wrapper over LifecycleLib.enterSingleInternal — packs the
    /// shared constants once per call. Body lives in the library to save
    /// EIP-170 bytecode (called from createRoundAndEnter, enter, enterBatch).
    function _enterSingleInternal(uint256 roundId, uint16 slotIndex, uint256 value) internal {
        LifecycleLib.enterSingleInternal(
            rounds,
            slotOwner,
            _claimedSlots,
            addressEntryCount,
            addressSlots,
            seedContribution,
            roundId,
            slotIndex,
            value,
            msg.sender,
            LifecycleLib.LifecycleConstants({
                maxEntriesPerAddress: MAX_ENTRIES_PER_ADDRESS,
                numSlots: NUM_SLOTS,
                activeTimer: ACTIVE_TIMER,
                activePhaseMax: ACTIVE_PHASE_MAX,
                finalCountdown: FINAL_COUNTDOWN
            })
        );
    }

    /// @notice Permissionless phase-advance.
    function tick(uint256 roundId) external {
        _advancePhase(roundId);
    }

    /// @dev Body in LifecycleLib.advancePhase (DELEGATECALL).
    function _advancePhase(uint256 roundId) internal {
        LifecycleLib.advancePhase(rounds, roundId, FINAL_COUNTDOWN);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Settlement
    // ─────────────────────────────────────────────────────────────────────

    function topUpVrfReserve() external payable {
        AdminLib.topUpVrfReserveBody(
            s_vrfCoordinator,
            VRF_SUB_ID,
            vrfReserveBalance(),
            MAX_VRF_RESERVE_BALANCE,
            msg.value,
            msg.sender
        );
    }

    /// @notice v10 F1 (post v9 R5 stuck-deploy 2026-05-26): external Supra
    /// deposit top-up. Symmetric to `topUpVrfReserve()` for the Chainlink
    /// subscription. Anyone-callable; only effect is increasing the contract's
    /// Supra deposit balance (which can only ever be drained via
    /// `withdrawSupraBalance` by the owner). Closes the operational-asymmetry
    /// gap that prevented v9 R5 from recovering from a chicken-and-egg deadlock
    /// when seeded at exactly the Supra min balance. See preflight §0.10.
    /// Uses low-level call with precomputed depositFundClient() selector
    /// (`0xf948ae29`) for EIP-170 bytecode budget, avoids the full interface
    /// dispatch overhead. Reuses SupraSubscriptionFunded event for byte savings.
    /// EVENT SEMANTICS NOTE (sub-agent R0.1 MINOR-2 2026-05-27): the same
    /// SupraSubscriptionFunded event is emitted by two distinct code paths
    /// with different `beneficiary` semantics:
    ///   - external top-up (this F1 path): `beneficiary = msg.sender` (funder)
    ///   - internal `_replenishSupra` path: `beneficiary = address(this)` (self)
    /// Off-chain indexers MUST distinguish by `beneficiary == address(bomb)`
    /// to attribute correctly. A dedicated `SupraBalanceToppedUp(address indexed
    /// funder, uint256 amount)` event is queued for R1 budget pass.
    /// SELECTOR PROVENANCE: `cast sig "depositFundClient()"` = `0xf948ae29`.
    /// Codex R0 BLOCKER-1 fix 2026-05-27: prior revision hardcoded `0xb3c818c7`
    /// which is actually `withdrawFundClient(uint128)`. See preflight §0.10 /
    /// §0.15: external interface invariants verified against deployed mainnet
    /// bytecode, not memory. Selector regression test in
    /// `test/BurnBombMinnowV1_1.topup-selector.test.ts`.
    function topUpSupraBalance() external payable {
        // Selector 0xf948ae29 = bytes4(keccak256("depositFundClient()")).
        // Inline assembly for EIP-170 fit, Solidity's abi.encodeWithSelector
        // pipeline costs ~30 extra bytes vs raw mstore+call.
        // No msg.value/supraRegistered guards: zero-value deposit is a benign
        // no-op; the bomb is unconditionally a Supra client from constructor
        // step 1 (independent of addContractToWhitelist).
        address target = s_supraDepositContract;
        bool ok;
        assembly ("memory-safe") {
            mstore(0, shl(224, 0xf948ae29))
            ok := call(gas(), target, callvalue(), 0, 4, 0, 0)
        }
        if (!ok) revert TransferFailed();
        emit SupraSubscriptionFunded(msg.value, msg.sender);
    }

    function requestVrfHealthCheck() external onlyOwner {
        if (activated) revert AlreadyActivated();
        // v9: unconditional supraRegistered guard. NOT gated by !supraDisabled
        // because B3 makes disableOracle pre-activation impossible, so the
        // bypass that &&!supraDisabled would create is closed at the source.
        if (!supraRegistered) revert SupraNotRegistered();
        // Re-request is allowed only when no prior request is pending unfulfilled.
        if (chainlinkHealthRequestId != 0 && !chainlinkHealthPassed && !chainlinkDisabled) revert VrfStillPending();
        if (supraHealthNonce != 0 && !supraHealthPassed && !supraDisabled) revert VrfStillPending();
        // MIN VRF reserve guard only applies when Chainlink is enabled (Chainlink
        // request would otherwise fail at the coordinator anyway). Lets operators
        // who deployed with `_chainlinkInitiallyDisabled=true` fire Supra-only
        // healthcheck with zero Chainlink funding.
        if (!chainlinkDisabled && vrfReserveBalance() < MIN_VRF_RESERVE_TO_ACTIVATE) revert VrfReserveTooLow();

        // Dual-oracle request — library skips an oracle that already passed
        // its health check (preserves original `&& !*HealthPassed` guards).
        (uint256 clReqId, uint256 sNonce) = SupraLib.dualOracleRequest(
            chainlinkDisabled, supraDisabled,
            chainlinkHealthPassed, supraHealthPassed,
            0
        );
        if (clReqId != 0) {
            chainlinkHealthRequestId = clReqId;
            emit VrfHealthCheckRequested(clReqId, 1);
        }
        if (sNonce != 0) {
            supraHealthNonce = sNonce;
            // v9: symmetric emit for Supra — source audit BLOCKER-1 fix.
            emit VrfHealthCheckRequested(sNonce, 2);
        }
        if (firstHealthRequestedAt == 0) firstHealthRequestedAt = block.timestamp;
    }

    /// @notice Abandon a stuck pre-activation health request and clear the
    /// pending ID for that oracle. Body in AdminLib.retryStuckHealthCheckBody.
    /// Preflight §0.12 / Codex M1 2026-05-25.
    function retryStuckHealthCheck(uint8 oracle) external onlyOwner adminNotFrozen {
        if (activated) revert AlreadyActivated();
        (bool clearCl, bool clearSupra) = AdminLib.retryStuckHealthCheckBody(
            firstHealthRequestedAt,
            oracle,
            chainlinkHealthPassed,
            supraHealthPassed,
            chainlinkHealthRequestId,
            supraHealthNonce
        );
        if (clearCl) chainlinkHealthRequestId = 0;
        if (clearSupra) supraHealthNonce = 0;
    }

    function settle(uint256 roundId) external nonReentrant {
        _advancePhase(roundId);

        BurnBombTypes.Round storage r = rounds[roundId];
        if (Phase(r.phase) != Phase.READY_TO_REQUEST_RANDOMNESS) revert WrongPhase();

        (uint256 clReqId, uint256 sNonce) = SupraLib.dualOracleRequest(
            chainlinkDisabled, supraDisabled, false, false, roundId
        );

        r.chainlinkRequestId = clReqId;
        r.supraNonce = sNonce;
        r.vrfRequestedAt = block.timestamp;
        r.firstVrfRequestedAt = block.timestamp;
        r.phase = uint8(Phase.WAITING_FOR_RANDOMNESS);
        if (clReqId != 0) chainlinkRequestIdToRoundId[clReqId] = roundId;
        if (sNonce != 0) supraNonceToRoundId[sNonce] = roundId;

        emit PhaseTransition(roundId, Phase.READY_TO_REQUEST_RANDOMNESS, Phase.WAITING_FOR_RANDOMNESS);
        emit DualOracleRequested(roundId, clReqId, sNonce, block.timestamp);
    }

    // ── v1.1 dual-oracle · external wrappers for self-call from SupraLib ──
    // Inlined the body (was a one-line forward to _requestChainlink/_requestSupra)
    // to drop one dispatch frame from deployed bytecode. Behavior preserved.
    function _requestChainlinkExternal() external returns (uint256 requestId) {
        if (msg.sender != address(this)) revert OnlySelfCall();
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: VRF_KEY_HASH,
                subId: VRF_SUB_ID,
                requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: VRF_NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );
    }

    function _requestSupraExternal() external returns (uint256 nonce) {
        if (msg.sender != address(this)) revert OnlySelfCall();
        // v9: defense-in-depth guard (single source of truth per spec).
        // requestVrfHealthCheck has the top-level guard; this is the wrapper
        // guard that all settle/retry paths route through.
        if (!supraRegistered) revert SupraNotRegistered();
        // Reference: github.com/Entropy-Foundation/supra-vrf-examples
        // 4-arg form (no client seed). clientWalletAddress = address(this) per
        // Option X (contract owns its own sub).
        nonce = ISupraRouterContract(s_supraRouter).generateRequest(
            "supraCallback(uint256,uint256[])",
            SUPRA_RNG_COUNT,
            SUPRA_CONFIRMATIONS,
            address(this)
        );
    }

    /// @notice Chainlink VRF callback. Routes both round + health fulfillments
    /// through _processFulfillment for first-wins / late-noop handling.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        if (randomWords.length == 0) return; // graceful noop; oracle infra requires no revert

        if (requestId != 0 && requestId == chainlinkHealthRequestId && !chainlinkHealthPassed) {
            chainlinkHealthPassed = true;
            emit VrfHealthCheckFulfilled(requestId, randomWords[0], 1);
            return;
        }

        uint256 roundId = chainlinkRequestIdToRoundId[requestId];
        if (roundId == 0) {
            emit OrphanCallback(1, requestId);
            return;
        }
        _processFulfillment(roundId, randomWords[0], 1, requestId);
    }

    /// @notice Supra dVRF callback. Function selector matches the string
    /// passed to generateRequest. Routes via _processFulfillment.
    function supraCallback(uint256 nonce, uint256[] calldata rngList) external {
        if (msg.sender != s_supraRouter) revert OnlySupraRouter();
        if (rngList.length == 0) return; // graceful noop

        if (nonce != 0 && nonce == supraHealthNonce && !supraHealthPassed) {
            supraHealthPassed = true;
            emit VrfHealthCheckFulfilled(nonce, rngList[0], 2);
            return;
        }

        uint256 roundId = supraNonceToRoundId[nonce];
        if (roundId == 0) {
            emit OrphanCallback(2, nonce);
            return;
        }
        _processFulfillment(roundId, rngList[0], 2, nonce);
    }

    /// @notice Shared first-wins / late-noop finalization. Never reverts on
    /// stale callbacks (oracle infrastructure requires callbacks not error).
    function _processFulfillment(uint256 roundId, uint256 randomWord, uint8 oracle, uint256 idOrNonce) internal {
        BurnBombTypes.Round storage r = rounds[roundId];
        // Single branch: any non-WAITING_FOR_RANDOMNESS phase is a late/stale
        // callback (covers RANDOMNESS_FULFILLED, SETTLED, REFUNDED, and earlier
        // phases where a callback shouldn't arrive but might). Never reverts.
        if (Phase(r.phase) != Phase.WAITING_FOR_RANDOMNESS) {
            emit LateFulfillmentIgnored(roundId, oracle, randomWord, idOrNonce);
            return;
        }

        r.randomWord = randomWord;
        r.fulfillingOracle = oracle;
        r.phase = uint8(Phase.RANDOMNESS_FULFILLED);

        // v9: latencySec restored per operator decision 2026-05-26 — telemetry on
        // Supra vs Chainlink fulfillment speed is operationally important.
        uint256 latencySec = block.timestamp > r.firstVrfRequestedAt
            ? block.timestamp - r.firstVrfRequestedAt
            : 0;
        emit PhaseTransition(roundId, Phase.WAITING_FOR_RANDOMNESS, Phase.RANDOMNESS_FULFILLED);
        emit RandomnessFulfilled(roundId, randomWord, oracle, latencySec);
    }

    /// @notice Retry randomness for a stuck round. Guards + bounty + mapping
    /// cleanup live in AdminLib.requestRandomnessAgainPre (EIP-170 win).
    function requestRandomnessAgain(uint256 roundId) external nonReentrant {
        BurnBombTypes.Round storage r = rounds[roundId];
        uint256 bounty = AdminLib.requestRandomnessAgainPre(
            r,
            chainlinkRequestIdToRoundId,
            supraNonceToRoundId,
            VRF_RETRY_TIMEOUT,
            MAX_CHAINLINK_REQUESTS_PER_ROUND,
            VRF_RETRY_BOUNTY,
            MAX_VRF_RETRY_BOUNTY_PER_ROUND
        );

        (uint256 clReqId, uint256 sNonce) = SupraLib.dualOracleRequest(
            chainlinkDisabled, supraDisabled, false, false, roundId
        );

        r.chainlinkRequestId = clReqId;
        r.supraNonce = sNonce;
        r.vrfRequestedAt = block.timestamp;
        r.retryCount += 1;
        if (clReqId != 0) chainlinkRequestIdToRoundId[clReqId] = roundId;
        if (sNonce != 0) supraNonceToRoundId[sNonce] = roundId;

        if (bounty > 0) {
            (bool ok, ) = msg.sender.call{value: bounty}("");
            if (!ok) revert TransferFailed();
        }

        // Emit a representative event for indexers. Use clReqId if present, else sNonce.
        emit RandomnessRetried(roundId, msg.sender, clReqId != 0 ? clReqId : sNonce, bounty);
    }

    /// @notice Compute target, rank top 3, credit pull-payouts, send rake, pay keeper.
    /// v1.1 CHANGE: VRF replenish path branches on shared-sub balance vs
    /// MAX_VRF_RESERVE_BALANCE; overflow (full or partial) credits the winner.
    function finalizeSettlement(uint256 roundId) external nonReentrant {
        BurnBombTypes.Round storage r = rounds[roundId];
        if (Phase(r.phase) != Phase.RANDOMNESS_FULFILLED) revert WrongPhase();

        uint256 pot = r.potTotal;
        uint16 target = uint16(r.randomWord % NUM_SLOTS);

        (uint16 w1, uint16 w2, uint16 w3) = SettlementLib.rankTop3(_claimedSlots, roundId, target);

        address winner = slotOwner[roundId][w1];
        address second = slotOwner[roundId][w2];
        address third  = slotOwner[roundId][w3];

        r.winnerSlot = w1;
        r.secondSlot = w2;
        r.thirdSlot  = w3;

        uint256 keeperBounty = pot * KEEPER_BPS / BPS_DENOM;
        if (keeperBounty > KEEPER_CAP) keeperBounty = KEEPER_CAP;

        uint256 secondShare  = pot * SECOND_BPS  / BPS_DENOM;
        uint256 thirdShare   = pot * THIRD_BPS   / BPS_DENOM;
        uint256 seedPool     = pot * SEED_BPS    / BPS_DENOM;
        uint256 burnRake     = pot * RAKE_BPS    / BPS_DENOM;
        uint256 founderShare = pot * FOUNDER_BPS / BPS_DENOM;
        uint256 vrfReplenish = pot * VRF_REPLENISH_BPS / BPS_DENOM;
        // v1.1a NEW: throne pool is part of fixedSlices, so winnerShare is
        // automatically reduced by it. Throne payout distribution happens
        // AFTER the standard credit block + season/throne update (see below).
        uint256 thronePool   = pot * THRONE_BPS  / BPS_DENOM;

        uint256 winnerShare = pot - (
            keeperBounty + secondShare + thirdShare + seedPool + burnRake
            + founderShare + vrfReplenish + thronePool + r.totalRetryBountyPaid
        );

        r.seedDividendPool = seedPool;
        address founderAtSettle = founderPayout;
        r.founderPayoutAtSettle = founderAtSettle;

        // Credit pull-payouts via library (matches inline fall-through rules:
        // any seat collision merges into the winner credit).
        SettlementLib.creditPayouts(
            claimablePayout, roundId,
            winner, second, third, founderAtSettle, msg.sender,
            winnerShare, secondShare, thirdShare, founderShare, keeperBounty
        );

        r.phase = uint8(Phase.SETTLED);

        // ── v1.1a · Throne royalty (season reset + update + payout + snapshot)
        // Body in SettlementLib.settleThrone — preserves the operator-locked
        // order (season → update → payout → snapshot) and returns the
        // empty-seat overflow for caller to route to winner.
        {
            (uint64 newStart, uint256 emptySeatOverflow) = SettlementLib.settleThrone(
                throne, throneSize, claimablePayout,
                seasonStartedAt, SEASON_LENGTH,
                roundId, r.creator, pot, thronePool
            );
            if (newStart != seasonStartedAt) seasonStartedAt = newStart;
            if (emptySeatOverflow > 0) {
                if (winner == address(0)) revert ZeroWinnerOnOverflow();
                claimablePayout[roundId][winner] += emptySeatOverflow;
            }
        }

        // ── v1.1 dual-oracle · VRF replenish split 40% Chainlink / 60% Supra ──
        if (vrfReplenish > 0) {
            uint256 chainlinkSlice = (vrfReplenish * 40) / 100;
            uint256 supraSlice = vrfReplenish - chainlinkSlice;

            // Chainlink branch — body lives in SettlementLib.chainlinkReplenish
            // (DELEGATECALL; events emit from main contract; ETH flows from
            // address(this) into the coordinator).
            SettlementLib.chainlinkReplenish(
                claimablePayout,
                s_vrfCoordinator,
                VRF_SUB_ID,
                MAX_VRF_RESERVE_BALANCE,
                roundId,
                winner,
                chainlinkSlice
            );

            // Supra branch: deposit to own sub. Falls back to operator-pull on revert.
            if (supraSlice > 0) {
                _replenishSupra(supraSlice);
            }
        }

        // Send burn rake as plain ETH to $BURN contract · BEST EFFORT.
        (bool rakeOk, ) = BURN_TOKEN.call{value: burnRake}("");
        if (!rakeOk) {
            r.pendingBurnRake = burnRake;
            emit BurnRakeForwardDeferred(roundId, burnRake);
        }

        emit PhaseTransition(roundId, Phase.RANDOMNESS_FULFILLED, Phase.SETTLED);
        emit RoundSettled(
            roundId,
            winner,
            w1,
            target,
            pot,
            winnerShare,
            second,
            secondShare,
            third,
            thirdShare,
            seedPool,
            burnRake,
            founderAtSettle,
            founderShare,
            keeperBounty,
            msg.sender
        );
    }

    /// @notice Retry a deferred BURN rake transfer. Permissionless.
    /// NOT gated by !deprecated: pre-deprecation SETTLED rounds with pending
    /// rake can still be flushed by anyone after deprecation. (sub-agent 2026-05-24)
    function forwardPendingBurnRake(uint256 roundId) external nonReentrant {
        uint256 amount = BulkWithdrawLib.forwardBurnRakePrep(rounds, roundId);
        (bool ok, ) = BURN_TOKEN.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit BurnRakeForwarded(roundId, amount);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  v1.1 dual-oracle · Supra subscription management
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Auto-replenish the contract's Supra sub. Falls back to the
    /// operator-pull bucket if the Deposit Contract's depositFundClient reverts.
    /// Body lives in SupraLib.tryDeposit; main contract owns the event emit
    /// + pending-bucket state write.
    function _replenishSupra(uint256 amount) internal {
        if (amount == 0) return;
        // v9 source audit MAJOR-2 fix: pre-finalize deferral guard. Unreachable in
        // v9 normal flow (settled rounds require activation which requires finalization),
        // but defense-in-depth per spec. If reached, accumulate to operator-pull bucket
        // instead of calling addContractToWhitelist-gated tryDeposit.
        if (!supraRegistered) {
            pendingSupraReplenish += uint96(amount);
            emit SupraReplenishDeferred(amount);
            return;
        }
        bool funded = SupraLib.tryDeposit(s_supraDepositContract, amount);
        if (funded) {
            emit SupraSubscriptionFunded(amount, address(this));
        } else {
            pendingSupraReplenish += uint96(amount);
            emit SupraReplenishDeferred(amount);
        }
    }

    /// @notice Read-through to the authoritative Supra balance held by the
    /// Deposit Contract under this contract's address. No local cache.
    function supraSubscriptionBalance() public view returns (uint128) {
        return IDepositContract(s_supraDepositContract).checkClientFund(address(this));
    }

    /// @notice Owner pull of the Supra sub balance. Pre-deprecate: bounded by
    /// SUPRA_OPERATIONAL_FLOOR. Post-deprecate: full balance recoverable.
    /// adminNotFrozen so deprecate-side recovery happens before any freeze.
    /// Validation + Deposit Contract pull live in SupraLib.pullSupraBalance;
    /// main contract owns the ETH transfer + event.
    function withdrawSupraBalance(uint128 amount, address to)
        external
        onlyOwner
        adminNotFrozen
    {
        uint128 actual = SupraLib.pullSupraBalance(
            s_supraDepositContract,
            deprecated,
            SUPRA_OPERATIONAL_FLOOR,
            amount,
            to
        );
        (bool ok, ) = to.call{value: actual}("");
        if (!ok) revert TransferFailed();
        emit SupraBalanceWithdrawn(to, actual);
    }

    /// @notice Operator-pull bucket for any Supra replenishes that reverted.
    /// onlyOwner here (contract has no separate manager role; spec's
    /// onlyOwnerOrManager reduces to onlyOwner in this codebase).
    /// Validation lives in SupraLib.validateReplenishWithdraw; main contract
    /// owns the storage write, ETH transfer, and event.
    function withdrawSupraReplenish(address to) external onlyOwner adminNotFrozen {
        uint96 amount = SupraLib.validateReplenishWithdraw(to, pendingSupraReplenish);
        pendingSupraReplenish = 0;
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit SupraReplenishWithdrawn(to, amount);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  v1.1 dual-oracle · per-oracle disable / enable
    // ─────────────────────────────────────────────────────────────────────

    function disableOracle(uint8 oracle) external onlyOwner adminNotFrozen {
        // Codex B3 2026-05-25: disable is an OPERATIONAL response (e.g. one
        // oracle published a security advisory mid-game). It must NOT be
        // callable pre-activation, where it could bypass the dual-oracle
        // health-check gate (operator could disable one, request only the
        // other, activate as soon as one passes — sidestepping the 24h
        // forceActivateSingleOracle delay).
        if (!activated) revert NotActivated();
        if (oracle == 1) {
            if (supraDisabled) revert CannotDisableBoth();
            chainlinkDisabled = true;
        } else if (oracle == 2) {
            if (chainlinkDisabled) revert CannotDisableBoth();
            supraDisabled = true;
        } else revert InvalidOracle();
        emit OracleDisabled(oracle, msg.sender, block.timestamp);
    }

    /// @notice Enable is NOT adminNotFrozen-gated — restoring an oracle from
    /// disabled is the strictly-safer direction.
    function enableOracle(uint8 oracle) external onlyOwner {
        if (oracle == 1) chainlinkDisabled = false;
        else if (oracle == 2) supraDisabled = false;
        else revert InvalidOracle();
        emit OracleEnabled(oracle, msg.sender, block.timestamp);
    }

    // _rankTop3 + _distance moved to SettlementLib for EIP-170 size win.

    // ─────────────────────────────────────────────────────────────────────
    //  v1.1a · Throne view (mutation logic lives in ThroneLib)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Throne state + season info. `stale=true` indicates the stored
    /// throne corresponds to an expired season; the next finalizeSettlement
    /// will wipe it. UIs should render "season expired — fresh throne on next
    /// round" when stale==true rather than showing the stale seats.
    function getThrone()
        external
        view
        returns (
            address[3] memory seats,
            uint256[3] memory sizes,
            uint64 seasonStart,
            uint64 seasonEnd,
            bool stale
        )
    {
        seats = throne;
        sizes = throneSize;
        seasonStart = seasonStartedAt;
        seasonEnd = seasonStartedAt + uint64(SEASON_LENGTH);
        stale = block.timestamp >= uint256(seasonEnd);
    }

    function vrfReserveBalance() public view returns (uint256) {
        (, uint96 nativeBalance, , , ) = s_vrfCoordinator.getSubscription(VRF_SUB_ID);
        return uint256(nativeBalance);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Withdrawals (pull-payment everywhere)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice v9 byte recovery: withdrawPayoutTo dropped (zero external refs in
    /// frontend/tests/scripts — confirmed by 2026-05-26 dead-weight scan). Users
    /// who want to redirect payout: call withdrawPayout then transfer off-chain.
    function withdrawPayout(uint256 roundId) external nonReentrant {
        uint256 amount = BulkWithdrawLib.payoutSingle(
            claimablePayout, roundId, msg.sender, payable(msg.sender)
        );
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function withdrawSeedDividend(uint256 roundId) external nonReentrant {
        uint256 amount = BulkWithdrawLib.seedDividendSingle(
            roundId, msg.sender, rounds, seedDividendClaimed, seedContribution
        );
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function withdrawRefund(uint256 roundId, uint16 slotIndex) external nonReentrant {
        BurnBombTypes.Round storage r = rounds[roundId];
        if (Phase(r.phase) != Phase.REFUNDED) revert WrongPhase();
        uint256 amount = BulkWithdrawLib.refundSingle(
            roundId, slotIndex, msg.sender, slotOwner, rounds,
            address(this).balance, MIN_SLOT, SLOT_STEP
        );
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  v1.1 NEW · Bulk withdraw functions (spec §5)
    //
    //  All three: nonReentrant + effects-before-interactions + single
    //  per-batch ETH transfer at the end. MAX_BATCH_SIZE cap guards
    //  against OOG even though Minnow's NUM_SLOTS naturally bounds refund.
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Batch-claim refunds for multiple slots in a single REFUNDED round.
    /// @dev Atomic: any wrong-owner slot reverts the entire batch.
    function withdrawRefundBatch(uint256 roundId, uint16[] calldata slotIndices)
        external
        nonReentrant
    {
        BurnBombTypes.Round storage r = rounds[roundId];
        if (Phase(r.phase) != Phase.REFUNDED) revert WrongPhase();
        if (slotIndices.length == 0) revert EmptyBatch();
        if (slotIndices.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 total = BulkWithdrawLib.processRefundBatch(
            roundId,
            slotIndices,
            msg.sender,
            slotOwner,
            r.totalRetryBountyPaid,
            r.potTotal,
            address(this).balance,
            MIN_SLOT,
            SLOT_STEP
        );

        (bool ok, ) = msg.sender.call{value: total}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Batch-claim payouts across multiple SETTLED rounds.
    /// @dev Zero-claimable rounds silently skip; phase check is per-round
    /// strict (any non-SETTLED round in the array reverts the batch).
    function withdrawPayoutBatch(uint256[] calldata roundIds) external nonReentrant {
        if (roundIds.length == 0) revert EmptyBatch();
        if (roundIds.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 total = BulkWithdrawLib.processPayoutBatch(
            roundIds, msg.sender, rounds, claimablePayout
        );

        if (total == 0) revert NothingToWithdraw();
        (bool ok, ) = msg.sender.call{value: total}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Batch-claim seed dividends across multiple SETTLED rounds.
    /// @dev Already-claimed or zero-contribution rounds silently skip.
    function withdrawSeedDividendBatch(uint256[] calldata roundIds) external nonReentrant {
        if (roundIds.length == 0) revert EmptyBatch();
        if (roundIds.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 total = BulkWithdrawLib.processSeedDividendBatch(
            roundIds, msg.sender, rounds, seedDividendClaimed, seedContribution
        );

        if (total == 0) revert NothingToWithdraw();
        (bool ok, ) = msg.sender.call{value: total}("");
        if (!ok) revert TransferFailed();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Founder payout · two-step rotation (survives freezeAdmin)
    // ─────────────────────────────────────────────────────────────────────

    function proposeFounderPayoutAddress(address newAddress) external onlyOwner {
        if (newAddress == address(0)) revert BurnBomb_ZeroAddress();
        pendingFounderPayout = newAddress;
        emit FounderPayoutProposed(founderPayout, newAddress);
    }

    function acceptFounderPayoutAddress() external {
        address proposed = pendingFounderPayout;
        if (proposed == address(0)) revert NoPendingProposal();
        if (msg.sender != proposed) revert NotProposedRecipient();

        address old = founderPayout;
        founderPayout = proposed;
        pendingFounderPayout = address(0);

        emit FounderPayoutAccepted(old, proposed);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Lifecycle: activate + deprecate
    // ─────────────────────────────────────────────────────────────────────

    function activate() external onlyOwner notDeprecated {
        AdminLib.validateActivate(
            activated,
            vrfReserveBalance(),
            MIN_VRF_RESERVE_TO_ACTIVATE,
            chainlinkDisabled,
            supraDisabled,
            chainlinkHealthPassed,
            supraHealthPassed
        );
        activated = true;
        // v1.1a: anchor the throne season clock at the operational launch moment.
        seasonStartedAt = uint64(block.timestamp);
        emit Activated(msg.sender, block.timestamp);
    }

    /// @notice v1.1 dual-oracle · single-oracle activation escape hatch.
    /// Callable only after BOTH oracles have been requested AND the
    /// SINGLE_ORACLE_OVERRIDE_DELAY (24h) has elapsed since first health
    /// request AND exactly one oracle has actually passed. One-shot,
    /// irreversible, transparent — marks degradedAtActivation=true so the
    /// production UI surfaces a "single-oracle mode" warning.
    function forceActivateSingleOracle(uint8 oracleAccepted)
        external
        onlyOwner
        adminNotFrozen
        notDeprecated
    {
        // v9 source audit MAJOR-1 fix: defensive guard for accepting Supra without registration.
        // Unreachable in normal flow (requestVrfHealthCheck would have reverted SupraNotRegistered
        // first, so supraHealthNonce would be 0 and AdminLib would revert MustRequestBothFirst),
        // but explicit per spec for defense-in-depth.
        if (oracleAccepted == 2 && !supraRegistered) revert SupraNotRegistered();
        AdminLib.validateForceActivate(
            activated,
            chainlinkHealthRequestId,
            supraHealthNonce,
            chainlinkHealthPassed,
            supraHealthPassed,
            firstHealthRequestedAt,
            SINGLE_ORACLE_OVERRIDE_DELAY,
            oracleAccepted
        );
        activated = true;
        degradedAtActivation = true;
        seasonStartedAt = uint64(block.timestamp);
        emit SingleOracleActivationOverride(oracleAccepted, block.timestamp);
        emit Activated(msg.sender, block.timestamp);
    }

    function deprecate() external onlyOwner {
        if (deprecated) revert AlreadyDeprecated();
        deprecated = true;
        emit Deprecated(msg.sender, block.timestamp);
    }

    /// @notice v1.1 NEW · Recover VRF sub balance after graceful retire.
    /// Triple-gated: must be deprecated AND current round terminal AND no
    /// pending VRF request. Carries `adminNotFrozen` so recovery must happen
    /// BEFORE freezeAdmin (intentional runbook).
    /// Canonical runbook: deprecate() → wait for current round to
    /// SETTLED/REFUNDED → confirm pendingRequestExists == false →
    /// cancelVrfSubscription(recipient) → optionally freezeAdmin afterward.
    function cancelVrfSubscription(address payable recipient)
        external
        onlyOwner
        adminNotFrozen
    {
        AdminLib.cancelVrfSubscriptionBody(
            rounds, s_vrfCoordinator, VRF_SUB_ID, currentRoundId, deprecated, recipient
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Admin (revocable via freezeAdmin)
    // ─────────────────────────────────────────────────────────────────────

    function pause() external onlyOwner adminNotFrozen {
        _pause();
    }

    function unpause() external onlyOwner adminNotFrozen {
        _unpause();
    }

    /// @notice Permissionless after the 72h emergency window elapses (preflight
    /// §0.3 + Codex B1 2026-05-25). Players are never gated on owner availability
    /// to recover funds from a stuck round.
    /// @dev `AdminLib.emergencyResolveBody` enforces the EMERGENCY_REFUND_DELAY
    /// itself — calling it before the window reverts inside the library.
    function emergencyResolveStuckRound(uint256 roundId) external {
        AdminLib.emergencyResolveBody(rounds, roundId, EMERGENCY_REFUND_DELAY);
    }

    /// @notice OVERRIDE · renounceOwnership disabled. v1's ownership came from
    /// Chainlink's ConfirmedOwner which did not expose renounce. v1.1 switched
    /// to OZ Ownable2Step which DOES — explicit override reverts to preserve
    /// the v1 behavior + operator's "never renounce" runbook (per memory
    /// `project_burntoken_operational_model.md`). freezeAdmin is the intended
    /// way to lock admin capabilities, not renounce.
    /// (Codex 2026-05-24 re-audit pass.)
    function renounceOwnership() public pure override {
        revert AdminIsFrozen();
    }

    function freezeAdmin() external onlyOwner {
        if (adminFrozen) revert AlreadyFrozen();
        if (paused()) revert CannotFreezeWhilePaused();
        adminFrozen = true;
        emit AdminFrozen(msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Views
    // ─────────────────────────────────────────────────────────────────────

    function getRound(uint256 roundId) external view returns (BurnBombTypes.Round memory) {
        return rounds[roundId];
    }

    // v10: getRoundTiming() removed — fully derivable from getRound(roundId).Round
    // struct already exposes phase + seedEndsAt + activeTimerEndsAt + activeEndsAt
    // + finalCountdownEndsAt. Frontend computes nextDeadline client-side. EIP-170.

    function getClaimedSlots(uint256 roundId) external view returns (uint16[] memory) {
        return _claimedSlots[roundId];
    }

    function getAddressSlots(uint256 roundId, address player) external view returns (uint16[] memory) {
        return addressSlots[roundId][player];
    }

    // isSlotAvailable() view removed in v1.1a · derivable client-side from
    // slotOwner(roundId, slotIndex) == address(0) + slotIndex < NUM_SLOTS().

    // NOTE · v1.1a: previewSeedDividend() and previewRefund() views from v1.1
    // are REMOVED to fit EIP-170. Both are deterministic functions of raw
    // public state — frontends compute them client-side:
    //   previewSeedDividend = r.seedDividendPool * seedContribution[r][a] / r.seedPotTotal
    //     (only meaningful when r.phase == SETTLED + !seedDividendClaimed[r][a])
    //   previewRefund = slotValue(i) - (slotValue(i) * r.totalRetryBountyPaid / r.potTotal)
    //     (only meaningful when r.phase == REFUNDED + slotOwner[r][i] != address(0))
    // All inputs (rounds(r), seedContribution, seedDividendClaimed, slotOwner)
    // remain readable via the auto-generated public getters.

    // ─────────────────────────────────────────────────────────────────────
    //  ETH handling · reject direct sends EXCEPT Supra Deposit Contract refunds
    // ─────────────────────────────────────────────────────────────────────
    //
    // The Supra Deposit Contract (s_supraDepositContract) returns ETH to the
    // contract's address when withdrawFundClient is called. We MUST accept that
    // inbound ETH or Supra reserve recovery is broken (Codex B2 2026-05-25,
    // preflight §0.13). Allow receive ONLY from that single trusted address.

    receive() external payable {
        if (msg.sender != s_supraDepositContract) revert();
    }

    fallback() external payable {
        revert();
    }
}
