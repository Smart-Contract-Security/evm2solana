// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title SwapContract — UUPS upgradeable
/// @notice TRUU-to-PRD migration swap.
///         - One cumulative position per wallet; deposits top it up.
///         - Tax is GLOBAL: it depends only on how many weeks have passed since
///           `startDate`, not on when any individual deposit landed. It starts at
///           52% and decreases 1% per week, reaching 0% after 52 weeks (1 year).
///           From then on the swap continues at 0% tax; deposits stay open.
///         - Claiming taxes the claimed amount at the current global rate and
///           starts a 9-day vesting tranche (10% immediate, +10%/day, full day 9).
contract SwapContract is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public truuToken;
    IERC20 public prdToken;
    address public foundationWallet;
    uint256 public startDate;

    /// @notice A wallet's single cumulative migration position.
    /// @dev `amount` is the still-claimable TRUU→PRD balance (1:1). The dates are
    ///      informational only — the tax is global and does NOT depend on them.
    struct Position {
        uint256 amount;
        uint256 firstDepositAt;
        uint256 lastDepositAt;
    }

    /// @notice A post-claim chunk vesting independently (10% immediate, 10%/day, full at day 9).
    struct VestingTranche {
        uint256 amount;
        uint256 vestingStart;
        uint256 withdrawn;
    }

    mapping(address => Position) internal _positions;
    mapping(address => VestingTranche[]) internal _vestingTranches;

    uint256 public totalAllocatedPRD;

    /// @notice TRUU still backing unclaimed positions. Incremented on deposit and
    ///         decremented by the claimed amount on claim. TRUU in the contract above
    ///         this figure belongs to claimed positions (or was sent in directly) and
    ///         is the only TRUU the owner may withdraw — see {collapseTRUU}.
    uint256 public totalUnclaimedTRUU;

    uint256 public emergencyInitiatedAt;
    bool public depositsFrozen;
    mapping(address => bool) public inactive;

    /// @notice Per-address registry flag, owner-managed.
    mapping(address => bool) public registry;

    uint256 public constant EMERGENCY_DELAY = 5 days;
    uint256 public constant PENALTY_WEEKS = 52;
    uint256 public constant VEST_DAYS = 9;

    event Deposited(address indexed user, uint256 truuAmount, uint256 prdAmount);
    event Claimed(address indexed user, uint256 totalBalance, uint256 penaltyAmount, uint256 userAmount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed owner, uint256 amount);
    event EmergencyInitiated(address indexed owner, uint256 executeAfter);
    event EmergencyCancelled(address indexed owner);
    event PRDDeposited(address indexed owner, uint256 amount);
    event PRDWithdrawn(address indexed owner, uint256 amount);
    event TRUUWithdrawn(address indexed owner, uint256 amount);
    event AccountDeactivated(address indexed account);
    event AccountActivated(address indexed account);
    event Synced(address indexed account, bool state);

    /// @dev Reserved storage to allow appending state variables in future upgrades.
    uint256[49] private __gap;

    /// @dev Locks the implementation so it can only be initialized via the proxy.
    constructor() {
        _disableInitializers();
    }

    function initialize(address _truuToken, address _prdToken, address _foundationWallet, uint256 _startDate)
        public
        initializer
    {
        require(_truuToken != address(0), "Invalid TRUU address");
        require(_prdToken != address(0), "Invalid PRD address");
        require(_foundationWallet != address(0), "Invalid foundation address");
        require(_startDate > block.timestamp, "Start date must be in the future");

        __Ownable_init(_foundationWallet);

        truuToken = IERC20(_truuToken);
        prdToken = IERC20(_prdToken);
        foundationWallet = _foundationWallet;
        startDate = _startDate;
    }

    /// @dev Gates upgrades to the owner (point this at governance). Renouncing
    ///      ownership permanently disables upgrades.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ---------- Admin: active/inactive ----------

    function deactivate(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "Invalid address");
            inactive[accounts[i]] = true;
            emit AccountDeactivated(accounts[i]);
        }
    }

    function activate(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            inactive[accounts[i]] = false;
            emit AccountActivated(accounts[i]);
        }
    }

    // ---------- Admin: registry ----------

    /// @notice Batch-set registry entries: applies `state` to every address in
    ///         `accounts` in a single call (one tx for the whole array to save gas).
    function sync(address[] calldata accounts, bool state) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "Invalid address");
            registry[accounts[i]] = state;
            emit Synced(accounts[i], state);
        }
    }

    // ---------- Core: deposit (tops up the caller's single position) ----------

    /// @notice Deposit TRUU (1:1 PRD credit) into the caller's single position.
    ///         Repeated deposits accumulate into the same position; the global tax
    ///         schedule (see `currentPenaltyPercent`) is unaffected by deposit timing.
    function deposit(uint256 truuAmount) external nonReentrant {
        require(!depositsFrozen, "Deposits frozen");
        require(block.timestamp >= startDate, "Swap not started");
        require(registry[msg.sender], "closed");
        require(!inactive[msg.sender], "Account inactive");
        require(truuAmount > 0, "Deposit too small");

        truuToken.safeTransferFrom(msg.sender, address(this), truuAmount);

        Position storage p = _positions[msg.sender];
        if (p.firstDepositAt == 0) {
            p.firstDepositAt = block.timestamp;
        }
        p.lastDepositAt = block.timestamp;
        p.amount += truuAmount;

        totalAllocatedPRD += truuAmount;
        totalUnclaimedTRUU += truuAmount;

        emit Deposited(msg.sender, truuAmount, truuAmount);
    }

    // ---------- Core: claim (taxed at the current global rate) ----------

    /// @notice Claim `amount` PRD from the caller's position. The whole claimed
    ///         amount is taxed at the current global penalty rate, and the
    ///         post-tax amount begins a new 9-day vesting tranche.
    function claim(uint256 amount) external nonReentrant {
        require(!inactive[msg.sender], "Account inactive");
        require(amount > 0, "Amount must be > 0");

        Position storage p = _positions[msg.sender];
        require(p.amount >= amount, "Not enough unclaimed balance");

        uint256 pct = currentPenaltyPercent();
        uint256 penaltyAmt = amount * pct / 100;
        uint256 userAmt = amount - penaltyAmt;

        p.amount -= amount;
        // The claimed TRUU is now the project's: release it from the unclaimed pool so
        // the owner can withdraw it via {collapseTRUU}.
        totalUnclaimedTRUU -= amount;

        require(prdToken.balanceOf(address(this)) >= userAmt + penaltyAmt, "Insufficient PRD in contract");

        _vestingTranches[msg.sender].push(
            VestingTranche({amount: userAmt, vestingStart: block.timestamp, withdrawn: 0})
        );

        if (penaltyAmt > 0) {
            totalAllocatedPRD -= penaltyAmt;
            prdToken.safeTransfer(foundationWallet, penaltyAmt);
        }

        emit Claimed(msg.sender, amount, penaltyAmt, userAmt);
    }

    // ---------- Core: withdraw (sweeps all vested across tranches) ----------

    function withdraw() external nonReentrant {
        require(!inactive[msg.sender], "Account inactive");

        VestingTranche[] storage vts = _vestingTranches[msg.sender];
        require(vts.length > 0, "Nothing claimed yet");

        uint256 totalAvailable;
        for (uint256 i = 0; i < vts.length; i++) {
            VestingTranche storage v = vts[i];
            uint256 vested = _trancheVested(v);
            uint256 available = vested - v.withdrawn;
            if (available > 0) {
                v.withdrawn += available;
                totalAvailable += available;
            }
        }

        require(totalAvailable > 0, "Nothing to withdraw");

        totalAllocatedPRD -= totalAvailable;
        prdToken.safeTransfer(msg.sender, totalAvailable);

        emit Withdrawn(msg.sender, totalAvailable);
    }

    // ---------- Funding / surplus ----------

    function depositPRD(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        prdToken.safeTransferFrom(msg.sender, address(this), amount);
        emit PRDDeposited(msg.sender, amount);
    }

    function withdrawSurplusPRD() external onlyOwner nonReentrant {
        uint256 balance = prdToken.balanceOf(address(this));
        require(balance > totalAllocatedPRD, "No surplus PRD");
        uint256 surplus = balance - totalAllocatedPRD;
        prdToken.safeTransfer(owner(), surplus);
        emit PRDWithdrawn(owner(), surplus);
    }

    /// @notice Owner withdrawal of TRUU from positions that have already been CLAIMED.
    /// @dev Only TRUU no longer backing an unclaimed position may leave: the withdrawable
    ///      amount is `balanceOf(this) - totalUnclaimedTRUU`. TRUU still backing unclaimed
    ///      positions stays locked until those users claim. This mirrors how
    ///      {withdrawSurplusPRD} protects allocated PRD. Emits {TRUUWithdrawn}.
    function collapseTRUU(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be > 0");
        uint256 balance = truuToken.balanceOf(address(this));
        require(balance > totalUnclaimedTRUU, "No claimed TRUU");
        uint256 withdrawable = balance - totalUnclaimedTRUU;
        require(amount <= withdrawable, "Exceeds claimed TRUU");
        truuToken.safeTransfer(owner(), amount);
        emit TRUUWithdrawn(owner(), amount);
    }

    /// @notice TRUU the owner may withdraw right now: balance minus the TRUU still
    ///         backing unclaimed positions.
    function getWithdrawableTRUU() external view returns (uint256) {
        uint256 balance = truuToken.balanceOf(address(this));
        return balance > totalUnclaimedTRUU ? balance - totalUnclaimedTRUU : 0;
    }

    // ---------- Emergency ----------

    function initiateEmergencyWithdraw() external onlyOwner {
        require(emergencyInitiatedAt == 0, "Already initiated");
        emergencyInitiatedAt = block.timestamp;
        depositsFrozen = true;
        emit EmergencyInitiated(owner(), block.timestamp + EMERGENCY_DELAY);
    }

    function cancelEmergencyWithdraw() external onlyOwner {
        require(emergencyInitiatedAt != 0, "Not initiated");
        emergencyInitiatedAt = 0;
        depositsFrozen = false;
        emit EmergencyCancelled(owner());
    }

    function emergencyWithdrawPRD() external onlyOwner {
        require(emergencyInitiatedAt != 0, "Not initiated");
        require(block.timestamp >= emergencyInitiatedAt + EMERGENCY_DELAY, "Timelock active");
        uint256 surplus = prdToken.balanceOf(address(this)) - totalAllocatedPRD;
        require(surplus > 0, "No surplus prd");
        emergencyInitiatedAt = 0;
        prdToken.safeTransfer(owner(), surplus);
        emit EmergencyWithdraw(owner(), surplus);
    }

    // ---------- Views: position / aggregates (frontend-compatible names) ----------

    /// @notice TRUU→PRD still claimable by `user` (their single position balance).
    function unclaimedBalance(address user) public view returns (uint256) {
        return _positions[user].amount;
    }

    /// @notice The caller's full position record (amount + first/last deposit times).
    function getPosition(address user) external view returns (Position memory) {
        return _positions[user];
    }

    /// @notice True if the user has executed at least one claim.
    function hasClaimed(address user) external view returns (bool) {
        return _vestingTranches[user].length > 0;
    }

    /// @notice Total post-penalty PRD across all of the user's claims (cumulative).
    function vestedTotal(address user) external view returns (uint256 total) {
        VestingTranche[] storage vts = _vestingTranches[user];
        for (uint256 i = 0; i < vts.length; i++) {
            total += vts[i].amount;
        }
    }

    /// @notice Vesting start of the user's FIRST claim (or 0 if none) — kept for UI compat.
    function vestingStart(address user) external view returns (uint256) {
        VestingTranche[] storage vts = _vestingTranches[user];
        if (vts.length == 0) return 0;
        return vts[0].vestingStart;
    }

    /// @notice Cumulative PRD withdrawn across all the user's vesting tranches.
    function totalWithdrawn(address user) external view returns (uint256 total) {
        VestingTranche[] storage vts = _vestingTranches[user];
        for (uint256 i = 0; i < vts.length; i++) {
            total += vts[i].withdrawn;
        }
    }

    /// @notice PRD currently withdrawable across all the user's vesting tranches.
    function getWithdrawable(address user) external view returns (uint256 total) {
        VestingTranche[] storage vts = _vestingTranches[user];
        for (uint256 i = 0; i < vts.length; i++) {
            VestingTranche storage v = vts[i];
            uint256 vested = _trancheVested(v);
            total += vested - v.withdrawn;
        }
    }

    /// @notice Total vested PRD (regardless of withdrawn status) across all claims.
    function getVested(address user) external view returns (uint256 total) {
        VestingTranche[] storage vts = _vestingTranches[user];
        for (uint256 i = 0; i < vts.length; i++) {
            total += _trancheVested(vts[i]);
        }
    }

    function getLockedPRD() external view returns (uint256) {
        return prdToken.balanceOf(address(this));
    }

    function getLockedTRUU() external view returns (uint256) {
        return truuToken.balanceOf(address(this));
    }

    function getSurplusPRD() external view returns (uint256) {
        uint256 balance = prdToken.balanceOf(address(this));
        return balance > totalAllocatedPRD ? balance - totalAllocatedPRD : 0;
    }

    function vestingTrancheCount(address user) external view returns (uint256) {
        return _vestingTranches[user].length;
    }

    /// @notice Returns (amount, vestingStart, withdrawn, currentlyVested) for one vesting tranche.
    function getVestingTranche(address user, uint256 idx)
        external
        view
        returns (uint256 amount, uint256 vestingStartTs, uint256 withdrawn, uint256 currentlyVested)
    {
        VestingTranche storage v = _vestingTranches[user][idx];
        return (v.amount, v.vestingStart, v.withdrawn, _trancheVested(v));
    }

    // ---------- Views: tax schedule + previews ----------

    /// @notice End of the taxed window. Tax is 0% from this timestamp onward.
    function endDate() public view returns (uint256) {
        return startDate + PENALTY_WEEKS * 7 days;
    }

    /// @notice The global tax percent right now (52% at startDate, -1%/week, 0% after 52 weeks).
    function currentPenaltyPercent() public view returns (uint256) {
        return _penaltyPercentAt(block.timestamp);
    }

    /// @notice Alias of {currentPenaltyPercent} kept for frontend compatibility.
    function getCurrentPenaltyPercent() external view returns (uint256) {
        return _penaltyPercentAt(block.timestamp);
    }

    /// @notice The global tax percent that would apply at an arbitrary timestamp.
    function getPenaltyPercentAt(uint256 timestamp) external view returns (uint256) {
        return _penaltyPercentAt(timestamp);
    }

    /// @notice Preview a `claim(amount)` right now: post-tax amount, tax taken, and the rate.
    function previewClaim(address, uint256 amount)
        external
        view
        returns (uint256 userAmount, uint256 penaltyAmount, uint256 effectivePenaltyPercent)
    {
        uint256 pct = _penaltyPercentAt(block.timestamp);
        penaltyAmount = amount * pct / 100;
        userAmount = amount - penaltyAmount;
        effectivePenaltyPercent = pct;
    }

    // ---------- Internal ----------

    /// @dev Global penalty schedule: 52% at/before startDate, -1% per elapsed week,
    ///      0% once 52 weeks have passed since startDate.
    function _penaltyPercentAt(uint256 timestamp) internal view returns (uint256) {
        if (timestamp <= startDate) return PENALTY_WEEKS;
        uint256 weeksElapsed = (timestamp - startDate) / 7 days;
        if (weeksElapsed >= PENALTY_WEEKS) return 0;
        return PENALTY_WEEKS - weeksElapsed;
    }

    function _trancheVested(VestingTranche storage v) internal view returns (uint256) {
        uint256 total = v.amount;
        if (block.timestamp <= v.vestingStart) return total / 10; // 10% immediate
        uint256 daysSinceClaim = (block.timestamp - v.vestingStart) / 1 days;
        if (daysSinceClaim >= VEST_DAYS) return total;
        return total * (daysSinceClaim + 1) / 10;
    }
}
