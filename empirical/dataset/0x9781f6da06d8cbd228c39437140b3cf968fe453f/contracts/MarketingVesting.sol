// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MarketingVesting
/// @notice Discrete monthly-cliff vesting of vXVO to a fixed beneficiary.
///         8 equal tranches unlock at 30-day intervals starting at `start`.
///         Funded by transferring `totalAmount` of `token` into this contract
///         after deployment. Adminless and immutable once deployed — no pause,
///         no migration, no admin recovery. Anyone may call `release()`;
///         tokens always flow to `beneficiary`.
contract MarketingVesting {
    using SafeERC20 for IERC20;

    /// @notice The vested ERC-20 token.
    IERC20 public immutable token;

    /// @notice Address that receives every release. Immutable.
    address public immutable beneficiary;

    /// @notice Unix timestamp when the schedule starts. The first tranche
    ///         unlocks at `start + TRANCHE_INTERVAL`.
    uint64 public immutable start;

    /// @notice Total tokens to be vested over the full schedule. Must be
    ///         evenly divisible by TRANCHE_COUNT.
    uint256 public immutable totalAmount;

    /// @notice Number of monthly tranches.
    uint256 public constant TRANCHE_COUNT = 8;

    /// @notice Seconds per tranche (= 30 days; a calendar-month simplification).
    uint256 public constant TRANCHE_INTERVAL = 30 days;

    /// @notice Cumulative tokens already pulled by `release()`.
    uint256 public released;

    event Released(uint256 amount);

    constructor(
        address _token,
        address _beneficiary,
        uint64 _start,
        uint256 _totalAmount
    ) {
        require(_token != address(0), "token zero");
        require(_beneficiary != address(0), "beneficiary zero");
        require(_totalAmount > 0, "total zero");
        require(
            _totalAmount % TRANCHE_COUNT == 0,
            "total not divisible by tranches"
        );

        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = _start;
        totalAmount = _totalAmount;
    }

    /// @notice Total tokens unlocked at a given timestamp, cumulatively. Does
    ///         not subtract amounts already released — see `releasable()`.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        if (timestamp < start) return 0;
        uint256 elapsed = (timestamp - start) / TRANCHE_INTERVAL;
        if (elapsed >= TRANCHE_COUNT) return totalAmount;
        return (totalAmount / TRANCHE_COUNT) * elapsed;
    }

    /// @notice Tokens currently claimable: vested minus already released.
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice Pull all currently-claimable tokens into the beneficiary wallet.
    ///         Permissionless: anyone can call. Tokens always go to
    ///         `beneficiary`, regardless of who calls.
    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "nothing to release");
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit Released(amount);
    }

    /// @notice Unix timestamp at which tranche `index` (0-indexed) unlocks.
    ///         For e.g. 250M/month × 8 months: trancheUnlockTime(0) returns
    ///         start + 30 days (first 250M claimable), …, trancheUnlockTime(7)
    ///         returns start + 240 days (final 250M, completing the 2B total).
    function trancheUnlockTime(uint256 index) external view returns (uint64) {
        require(index < TRANCHE_COUNT, "invalid tranche");
        return start + uint64(TRANCHE_INTERVAL * (index + 1));
    }

    /// @notice Total tokens locked at a given timestamp (totalAmount - vested).
    ///         View-only convenience for UIs.
    function lockedAmount(uint64 timestamp) external view returns (uint256) {
        return totalAmount - vestedAmount(timestamp);
    }
}
