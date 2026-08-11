// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
    address private _owner;

    address public immutable registry;
    address public immutable hat;

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

    /// @dev Reentrancy guard state
    uint256 private _status;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PrizeShareReceived(uint256 amount);
    event PrizePoolSeeded(uint256 amount);
    event StageEmissionBudgetSet(uint256 indexed stageId, uint256 budget);
    event StageEmissionFrozen();
    event StageAllowanceSet(uint256 indexed stageId, address indexed user, uint256 amount);
    event EmissionClaimed(uint256 indexed stageId, address indexed user, uint256 amount);
    event GrandPrizePaid(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(tx.accounts[0].key == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier nonReentrant() {
        require(_status != 2, "ReentrancyGuard: reentrant call");
        _status = 2;
        _;
        _status = 1;
    }

    constructor(address _registry, address _hat, address _initialOwner) {
        require(_initialOwner != address(0), "Ownable: owner is zero address");
        _owner = _initialOwner;
        emit OwnershipTransferred(address(0), _initialOwner);
        registry = _registry;
        hat      = _hat;
        _status = 1;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    // ─── pre-TGE: emission schedule ──────────────────────────────────────

    /// @notice Set the per-stage emission budget. Must be called before
    /// `freezeEmissionSchedule()` and before TGE. Frozen after that.
    function setStageEmissionBudget(uint256 stageId, uint256 budget) external onlyOwner {
        if (emissionScheduleFrozen) {
            revert("AlreadyInitialised");
        }
        // registry.phase() returns uint8, TGE is phase 1
        (bool success, bytes memory data) = registry.call(abi.encodeWithSignature("phase()"));
        require(success, "registry call failed");
        uint8 phase = abi.decode(data, (uint8));
        if (phase >= 1) {
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

    function receivePrizeShare(uint256 hatAmount) external override {
        (bool success, bytes memory data) = registry.call(abi.encodeWithSignature("hatTrickHook()"));
        require(success, "registry call failed");
        address hook = abi.decode(data, (address));
        if (tx.accounts[0].key != hook) {
            revert("NotAuthorized");
        }
        // The hook has already settled the HAT to this contract via
        // poolManager.take(... PrizeVault); we just account for it.
        prizePoolBalance += hatAmount;
        emit PrizeShareReceived(hatAmount);
    }

    /// @notice Owner top-up (pre-TGE seed from pack-sale revenue, etc.).
    /// Caller must approve this contract for `amount` of HAT first.
    function seedPrizePool(uint256 amount) external onlyOwner {
        // SafeERC20 transferFrom equivalent
        (bool success, bytes memory ret) = hat.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", tx.accounts[0].key, address(this), amount));
        require(success && (ret.length == 0 || abi.decode(ret, (bool))), "SafeERC20: transferFrom failed");
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
        (bool success, bytes memory data) = registry.call(abi.encodeWithSignature("scoringEngine()"));
        require(success, "registry call failed");
        address engine = abi.decode(data, (address));
        if (tx.accounts[0].key != engine) {
            revert("NotAuthorized");
        }
        (success, data) = registry.call(abi.encodeWithSignature("phase()"));
        require(success, "registry call failed");
        uint8 phase = abi.decode(data, (uint8));
        if (phase < 2) {
            revert("WrongPhase");
        }
        if (stageClaimed[stageId][user]) {
            revert("AlreadyInitialised");
        }

        uint256 prev = stageAllowance[stageId][user];
        uint256 spent = stageEmissionSpent[stageId];
        // delta-adjust to avoid double-debit on a re-run.
        if (amount >= prev) {
            uint256 newSpent = spent + (amount - prev);
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

    function claimEmission(address to, uint256 amount) external override nonReentrant {
        uint256 stageIdMax = 256;
        // The user provides the (stageId, amount) pair via a separate path
        // — see claim(uint256 stageId) below. This signature exists to
        // satisfy IPrizeVault for explicit-amount callers. We treat it as
        // an alias for the most-recent unclaimed stage.
        uint256 stageId = _findUnclaimedStage(tx.accounts[0].key, stageIdMax);
        require(stageId != type(uint256).max, "no unclaimed stage");
        _claim(stageId, tx.accounts[0].key, to);
        // amount param is ignored — full allowance always claimed.
        if (amount != 0) {} // silence warning
    }

    /// @notice Claim a specific stage's allowance. Mints HAT to msg.sender.
    function claim(uint256 stageId) external nonReentrant {
        _claim(stageId, tx.accounts[0].key, tx.accounts[0].key);
    }

    function _claim(uint256 stageId, address user, address to) internal {
        if (stageClaimed[stageId][user]) {
            revert("AlreadyInitialised");
        }
        uint256 amount = stageAllowance[stageId][user];
        if (amount == 0) {
            revert("ZeroAmount");
        }
        stageClaimed[stageId][user] = true;
        (bool success, ) = hat.call(abi.encodeWithSignature("mintEmission(address,uint256)", to, amount));
        require(success, "mintEmission failed");
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
        (bool success, bytes memory data) = registry.call(abi.encodeWithSignature("phase()"));
        require(success, "registry call failed");
        uint8 phase = abi.decode(data, (uint8));
        if (phase < 3) {
            revert("WrongPhase");
        }
        if (amount > prizePoolBalance) {
            revert("PotentialOverflow");
        }
        prizePoolBalance -= amount;
        (success, data) = hat.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transfer failed");
        emit GrandPrizePaid(to, amount);
    }
}