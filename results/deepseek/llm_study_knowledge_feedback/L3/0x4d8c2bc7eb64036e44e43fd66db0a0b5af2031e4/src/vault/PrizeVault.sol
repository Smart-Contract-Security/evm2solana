// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

import {IPrizeVault} from "./IPrizeVault.sol";
import {IHatToken} from "../token/IHatToken.sol";

/// @title PrizeVault
/// @notice The accounting layer for prize-pool inflows and per-stage emission.
///
/// Inflows
/// -------
/// - From HatTrickHook: a HAT-denominated `receivePrizeShare(amount)` call
///   on every swap (the α_prize portion of the fee). PrizeVault custodies
///   the HAT.
/// - From an owner top-up `seedPrizePool(amount)` (e.g. from pack-sale
///   USDC swapped to HAT pre-TGE). Out-of-band for simplicity.
///
/// Outflows
/// --------
/// - `mintEmission`: PrizeVault is the only address allowed to call
///   HatToken.mintEmission(). Per-stage emission is bounded by a budget
///   the owner sets pre-TGE. After FULL_TIME the schedule is exhausted.
/// - `claimEmission`: a user claims their stage emission after the
///   ScoringEngine has authorised it via setStageAllowance().
///
/// Scoring-engine integration: rather than copying scoring math here, we
/// expose a single `setStageAllowance(user, stageId, amount)` that the
/// ScoringEngine (and only the ScoringEngine) calls after settling a
/// stage. Users then pull their own allowance via `claimEmission()`.
contract PrizeVault is IPrizeVault {
    // Protocol phase constants
    uint8 private constant PHASE_TGE = 1;
    uint8 private constant PHASE_LIVE = 2;
    uint8 private constant PHASE_SETTLED = 3;

    address public immutable registry;
    address public immutable hat;

    address private _owner;

    /// @dev Sum of HAT held that's earmarked for the final-ranking grand
    /// prize. Distinct from per-stage emission, which is minted on claim.
    uint64 public override prizePoolBalance;

    /// @dev Per-stage emission budget in HAT (set pre-TGE, frozen).
    mapping(uint64 => uint64) public stageEmissionBudget;
    mapping(uint64 => uint64) public stageEmissionSpent;
    bool public emissionScheduleFrozen;

    /// @dev Per-(user, stage) emission allowance set by ScoringEngine.
    mapping(uint64 => mapping(address => uint64)) public stageAllowance;
    mapping(uint64 => mapping(address => bool)) public stageClaimed;

    event PrizeShareReceived(uint64 amount);
    event PrizePoolSeeded(uint64 amount);
    event StageEmissionBudgetSet(uint64 stageId, uint64 budget);
    event StageEmissionFrozen();
    event StageAllowanceSet(uint64 stageId, address user, uint64 amount);
    event EmissionClaimed(uint64 stageId, address user, uint64 amount);
    event GrandPrizePaid(address to, uint64 amount);

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        _;
    }

    constructor(address _registry, address _hat, address _initialOwner) {
        registry = _registry;
        hat      = _hat;
        _owner   = _initialOwner;
    }

    // ─── pre-TGE: emission schedule ──────────────────────────────────────

    /// @notice Set the per-stage emission budget. Must be called before
    /// `freezeEmissionSchedule()` and before TGE. Frozen after that.
    function setStageEmissionBudget(uint64 stageId, uint64 budget) external onlyOwner {
        if (emissionScheduleFrozen) {
            revert("AlreadyInitialised");
        }
        (bool ok, bytes memory data) = registry.call{accounts: []}(abi.encodeWithSignature("phase()"));
        require(ok, "registry call failed");
        uint8 phase = abi.decode(data, (uint8));
        if (phase >= PHASE_TGE) {
            revert("WrongPhase");
        }
        stageEmissionBudget[stageId] = budget;
        emit StageEmissionBudgetSet(stageId, budget);
    }

    function freezeEmissionSchedule() external onlyOwner {
        emissionScheduleFrozen = true;
        emit StageEmissionFrozen();
    }

    // ─── hook → prize pool ───────────────────────────────────────────────

    function receivePrizeShare(uint64 hatAmount) external override {
        (bool ok, bytes memory data) = registry.call{accounts: []}(abi.encodeWithSignature("hatTrickHook()"));
        require(ok, "registry call failed");
        address hook = abi.decode(data, (address));
        require(tx.accounts.dataAccount.key == hook, "Not authorized");
        // The hook has already settled the HAT to this contract via
        // poolManager.take(... PrizeVault); we just account for it.
        prizePoolBalance += hatAmount;
        emit PrizeShareReceived(hatAmount);
    }

    /// @notice Owner top-up (pre-TGE seed from pack-sale revenue, etc.).
    /// Caller must approve this contract for `amount` of HAT first.
    function seedPrizePool(uint64 amount) external onlyOwner {
        (bool ok, ) = hat.call{accounts: []}(abi.encodeWithSignature("transferFrom(address,address,uint64)", tx.accounts.dataAccount.key, address(this), amount));
        require(ok, "transferFrom failed");
        prizePoolBalance += amount;
        emit PrizePoolSeeded(amount);
    }

    // ─── scoring engine integration ──────────────────────────────────────

    /// @notice ScoringEngine calls this after settling a stage. Records the
    /// per-user emission allowance for the stage and adjusts `stageEmissionSpent`
    /// by the DELTA against any prior allowance for the same (stage, user).
    /// Idempotent: calling with the same amount is a no-op; lowering an
    /// allowance refunds budget; raising consumes more. Reverts if the user
    /// has already CLAIMED — allowance is locked once spent.
    function setStageAllowance(uint64 stageId, address user, uint64 amount) external {
        (bool ok, bytes memory data) = registry.call{accounts: []}(abi.encodeWithSignature("scoringEngine()"));
        require(ok, "registry call failed");
        address scoringEngine = abi.decode(data, (address));
        require(tx.accounts.dataAccount.key == scoringEngine, "Not authorized");

        (ok, data) = registry.call{accounts: []}(abi.encodeWithSignature("phase()"));
        require(ok, "registry call failed");
        uint8 phase = abi.decode(data, (uint8));
        if (phase < PHASE_LIVE) {
            revert("WrongPhase");
        }
        if (stageClaimed[stageId][user]) {
            revert("AlreadyInitialised");
        }

        uint64 prev = stageAllowance[stageId][user];
        uint64 spent = stageEmissionSpent[stageId];
        // delta-adjust to avoid double-debit on a re-run.
        if (amount >= prev) {
            uint64 newSpent = spent + (amount - prev);
            if (newSpent > stageEmissionBudget[stageId]) {
                revert("PotentialOverflow");
            }
            stageEmissionSpent[stageId] = newSpent;
        } else {
            stageEmissionSpent[stageId] = spent - (prev - amount);
        }
        stageAllowance[stageId][user] = amount;
        emit StageAllowanceSet(stageId, user, amount);
    }

    // ─── user claim ──────────────────────────────────────────────────────

    function claimEmission(address to, uint64 amount) external override nonReentrant {
        uint64 stageIdMax = 256;
        // The user provides the (stageId, amount) pair via a separate path
        // — see claim(uint64 stageId) below. This signature exists to
        // satisfy IPrizeVault for explicit-amount callers. We treat it as
        // an alias for the most-recent unclaimed stage.
        uint64 stageId = _findUnclaimedStage(tx.accounts.dataAccount.key, stageIdMax);
        require(stageId != type(uint64).max, "no unclaimed stage");
        _claim(stageId, tx.accounts.dataAccount.key, to);
        // amount param is ignored — full allowance always claimed.
        if (amount != 0) {} // silence warning
    }

    /// @notice Claim a specific stage's allowance. Mints HAT to msg.sender.
    function claim(uint64 stageId) external nonReentrant {
        _claim(stageId, tx.accounts.dataAccount.key, tx.accounts.dataAccount.key);
    }

    function _claim(uint64 stageId, address user, address to) internal {
        if (stageClaimed[stageId][user]) {
            revert("AlreadyInitialised");
        }
        uint64 amount = stageAllowance[stageId][user];
        if (amount == 0) {
            revert("ZeroAmount");
        }
        stageClaimed[stageId][user] = true;
        (bool ok, ) = hat.call{accounts: []}(abi.encodeWithSignature("mintEmission(address,uint64)", to, amount));
        require(ok, "mintEmission failed");
        emit EmissionClaimed(stageId, user, amount);
    }

    function _findUnclaimedStage(address user, uint64 maxStage) internal view returns (uint64) {
        for (uint64 i = 0; i < maxStage; ++i) {
            if (stageAllowance[i][user] != 0 && !stageClaimed[i][user]) return i;
        }
        return type(uint64).max;
    }

    function stageEmissionRemaining(uint64 stageId) external view override returns (uint64) {
        uint64 budget = stageEmissionBudget[stageId];
        uint64 spent  = stageEmissionSpent[stageId];
        return budget > spent ? budget - spent : 0;
    }

    // ─── grand prize (SETTLED only) ──────────────────────────────────────

    /// @notice Pay the grand prize after the protocol reaches SETTLED.
    /// Permissioned to owner because the ranking is determined off-chain
    /// from on-chain scores (an alternative would be to have ScoringEngine
    /// produce the ranking on-chain, but for 1k+ entrants that's gas-prohibitive).
    function payGrandPrize(address to, uint64 amount) external onlyOwner nonReentrant {
        (bool ok, bytes memory data) = registry.call{accounts: []}(abi.encodeWithSignature("phase()"));
        require(ok, "registry call failed");
        uint8 phase = abi.decode(data, (uint8));
        if (phase < PHASE_SETTLED) {
            revert("WrongPhase");
        }
        if (amount > prizePoolBalance) {
            revert("PotentialOverflow");
        }
        prizePoolBalance -= amount;
        (ok, ) = hat.call{accounts: []}(abi.encodeWithSignature("transfer(address,uint64)", to, amount));
        require(ok, "transfer failed");
        emit GrandPrizePaid(to, amount);
    }
}