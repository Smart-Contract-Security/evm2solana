// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IPrizeVault} from "./IPrizeVault.sol";
import {IHatToken} from "../token/IHatToken.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {ProtocolPhase} from "../protocol/ProtocolPhase.sol";
import {Errors} from "../util/Errors.sol";

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
contract PrizeVault is Ownable, ReentrancyGuard, IPrizeVault {
    using SafeERC20 for IERC20;

    IProtocolRegistry public immutable registry;
    IHatToken         public immutable hat;

    /// @dev Sum of HAT held that's earmarked for the final-ranking grand
    /// prize. Distinct from per-stage emission, which is minted on claim.
    uint256 public override prizePoolBalance;

    /// @dev Per-stage emission budget in HAT (set pre-TGE, frozen).
    mapping(uint256 => uint256) public stageEmissionBudget;
    mapping(uint256 => uint256) public stageEmissionSpent;
    bool public emissionScheduleFrozen;

    /// @dev Per-(user, stage) emission allowance set by ScoringEngine.
    mapping(uint256 => mapping(address => uint256)) public stageAllowance;
    mapping(uint256 => mapping(address => bool)) public stageClaimed;

    event PrizeShareReceived(uint256 amount);
    event PrizePoolSeeded(uint256 amount);
    event StageEmissionBudgetSet(uint256 indexed stageId, uint256 budget);
    event StageEmissionFrozen();
    event StageAllowanceSet(uint256 indexed stageId, address indexed user, uint256 amount);
    event EmissionClaimed(uint256 indexed stageId, address indexed user, uint256 amount);
    event GrandPrizePaid(address indexed to, uint256 amount);

    constructor(IProtocolRegistry _registry, IHatToken _hat, address _initialOwner)
        Ownable(_initialOwner)
    {
        registry = _registry;
        hat      = _hat;
    }

    // ─── pre-TGE: emission schedule ──────────────────────────────────────

    /// @notice Set the per-stage emission budget. Must be called before
    /// `freezeEmissionSchedule()` and before TGE. Frozen after that.
    function setStageEmissionBudget(uint256 stageId, uint256 budget) external onlyOwner {
        if (emissionScheduleFrozen) revert Errors.AlreadyInitialised();
        if (uint8(registry.phase()) >= uint8(ProtocolPhase.Phase.TGE)) revert Errors.WrongPhase();
        stageEmissionBudget[stageId] = budget;
        emit StageEmissionBudgetSet(stageId, budget);
    }

    function freezeEmissionSchedule() external onlyOwner {
        emissionScheduleFrozen = true;
        emit StageEmissionFrozen();
    }

    // ─── hook → prize pool ───────────────────────────────────────────────

    function receivePrizeShare(uint256 hatAmount) external override {
        if (msg.sender != registry.hatTrickHook()) revert Errors.NotAuthorized();
        // The hook has already settled the HAT to this contract via
        // poolManager.take(... PrizeVault); we just account for it.
        prizePoolBalance += hatAmount;
        emit PrizeShareReceived(hatAmount);
    }

    /// @notice Owner top-up (pre-TGE seed from pack-sale revenue, etc.).
    /// Caller must approve this contract for `amount` of HAT first.
    function seedPrizePool(uint256 amount) external onlyOwner {
        IERC20(address(hat)).safeTransferFrom(msg.sender, address(this), amount);
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
    function setStageAllowance(uint256 stageId, address user, uint256 amount) external {
        if (msg.sender != registry.scoringEngine()) revert Errors.NotAuthorized();
        if (uint8(registry.phase()) < uint8(ProtocolPhase.Phase.LIVE)) revert Errors.WrongPhase();
        if (stageClaimed[stageId][user]) revert Errors.AlreadyInitialised();

        uint256 prev = stageAllowance[stageId][user];
        uint256 spent = stageEmissionSpent[stageId];
        // delta-adjust to avoid double-debit on a re-run.
        if (amount >= prev) {
            uint256 newSpent = spent + (amount - prev);
            if (newSpent > stageEmissionBudget[stageId]) revert Errors.PotentialOverflow();
            stageEmissionSpent[stageId] = newSpent;
        } else {
            stageEmissionSpent[stageId] = spent - (prev - amount);
        }
        stageAllowance[stageId][user] = amount;
        emit StageAllowanceSet(stageId, user, amount);
    }

    // ─── user claim ──────────────────────────────────────────────────────

    function claimEmission(address to, uint256 amount) external override nonReentrant {
        uint256 stageIdMax = 256;
        // The user provides the (stageId, amount) pair via a separate path
        // — see claim(uint256 stageId) below. This signature exists to
        // satisfy IPrizeVault for explicit-amount callers. We treat it as
        // an alias for the most-recent unclaimed stage.
        uint256 stageId = _findUnclaimedStage(msg.sender, stageIdMax);
        require(stageId != type(uint256).max, "no unclaimed stage");
        _claim(stageId, msg.sender, to);
        // amount param is ignored — full allowance always claimed.
        if (amount != 0) {} // silence warning
    }

    /// @notice Claim a specific stage's allowance. Mints HAT to msg.sender.
    function claim(uint256 stageId) external nonReentrant {
        _claim(stageId, msg.sender, msg.sender);
    }

    function _claim(uint256 stageId, address user, address to) internal {
        if (stageClaimed[stageId][user]) revert Errors.AlreadyInitialised();
        uint256 amount = stageAllowance[stageId][user];
        if (amount == 0) revert Errors.ZeroAmount();
        stageClaimed[stageId][user] = true;
        hat.mintEmission(to, amount);
        emit EmissionClaimed(stageId, user, amount);
    }

    function _findUnclaimedStage(address user, uint256 maxStage) internal view returns (uint256) {
        for (uint256 i = 0; i < maxStage; ++i) {
            if (stageAllowance[i][user] != 0 && !stageClaimed[i][user]) return i;
        }
        return type(uint256).max;
    }

    function stageEmissionRemaining(uint256 stageId) external view override returns (uint256) {
        uint256 budget = stageEmissionBudget[stageId];
        uint256 spent  = stageEmissionSpent[stageId];
        return budget > spent ? budget - spent : 0;
    }

    // ─── grand prize (SETTLED only) ──────────────────────────────────────

    /// @notice Pay the grand prize after the protocol reaches SETTLED.
    /// Permissioned to owner because the ranking is determined off-chain
    /// from on-chain scores (an alternative would be to have ScoringEngine
    /// produce the ranking on-chain, but for 1k+ entrants that's gas-prohibitive).
    function payGrandPrize(address to, uint256 amount) external onlyOwner nonReentrant {
        if (uint8(registry.phase()) < uint8(ProtocolPhase.Phase.SETTLED)) revert Errors.WrongPhase();
        if (amount > prizePoolBalance) revert Errors.PotentialOverflow();
        prizePoolBalance -= amount;
        IERC20(address(hat)).safeTransfer(to, amount);
        emit GrandPrizePaid(to, amount);
    }
}
