// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title WaterfallDistributor
/// @notice Trustless, immutable ERC20 (USDT) waterfall splitter. Recipients and
///         basis-point shares are fixed at deployment and can never be changed
///         — not even by the contract owner. The owner's only privilege is the
///         pause / unpause circuit breaker.
/// @dev    Designed for Tether on Ethereum mainnet, whose `transfer` /
///         `transferFrom` do not return a bool. All token movements use
///         OpenZeppelin's `SafeERC20` to handle the non-standard ABI safely.
///
///         Distribution semantics: both `deposit()` and `flush()` distribute
///         the contract's full live USDT balance after any pull-in. This means
///         accumulated dust from prior rounds and any stray direct transfers
///         are always included in the next distribution.
contract WaterfallDistributor is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------
    //  Constants
    // ------------------------------------------------------------------

    /// @notice Total basis points representing 100% (1 bp = 0.01%).
    uint256 public constant TOTAL_BPS = 10_000;

    // ------------------------------------------------------------------
    //  Immutable / quasi-immutable state
    // ------------------------------------------------------------------

    /// @notice Address of the USDT token this distributor splits.
    /// @dev    Immutable so it can never be repointed at a different token.
    address public immutable USDT;

    /// @dev Recipients and basis points are written once in the constructor and
    ///      never modified again. They are not declared `immutable` only because
    ///      Solidity does not yet support immutable arrays — there is no setter.
    address[] private _recipients;
    uint256[] private _basisPoints;

    // ------------------------------------------------------------------
    //  Mutable state (informational only — never affects routing)
    // ------------------------------------------------------------------

    /// @dev Tracks the dust left over from the most recent distribution.
    ///      Purely informational: the actual dust value lives in
    ///      `IERC20(USDT).balanceOf(address(this))` and is swept on the next
    ///      `deposit()` or `flush()` call.
    uint256 private _dustBalance;

    // ------------------------------------------------------------------
    //  Events
    // ------------------------------------------------------------------

    /// @notice Emitted when a caller deposits USDT via `deposit()`.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted once per recipient that receives a non-zero share
    ///         during a distribution.
    event RecipientPaid(address indexed recipient, uint256 amount);

    /// @notice Emitted at the end of every distribution.
    /// @param totalAmount     The full balance fed into the distribution.
    /// @param dustCarriedOver Wei left in the contract after rounding.
    event Distributed(uint256 totalAmount, uint256 dustCarriedOver);

    /// @notice Emitted when a non-zero amount of dust is carried over.
    event DustAccumulated(uint256 dustAmount);

    // ------------------------------------------------------------------
    //  Errors
    // ------------------------------------------------------------------

    error ZeroAddress();
    error EmptyRecipients();
    error LengthMismatch();
    error InvalidBasisPoints(uint256 sum);
    error ZeroBasisPoints();
    error ZeroAmount();

    // ------------------------------------------------------------------
    //  Constructor
    // ------------------------------------------------------------------

    /// @param usdt        Address of the USDT token contract.
    /// @param recipients_ Recipient addresses (each receives a fixed share).
    /// @param bps         Basis points per recipient. Must sum to exactly 10_000.
    constructor(
        address usdt,
        address[] memory recipients_,
        uint256[] memory bps
    ) Ownable(msg.sender) {
        if (usdt == address(0)) revert ZeroAddress();
        if (recipients_.length == 0) revert EmptyRecipients();
        if (recipients_.length != bps.length) revert LengthMismatch();

        uint256 sum;
        uint256 len = recipients_.length;
        for (uint256 i; i < len; ++i) {
            if (recipients_[i] == address(0)) revert ZeroAddress();
            if (bps[i] == 0) revert ZeroBasisPoints();
            sum += bps[i];
        }
        if (sum != TOTAL_BPS) revert InvalidBasisPoints(sum);

        USDT = usdt;
        _recipients = recipients_;
        _basisPoints = bps;
    }

    // ------------------------------------------------------------------
    //  External entry points
    // ------------------------------------------------------------------

    /// @notice Pulls `amount` USDT from `msg.sender` (caller must approve first)
    ///         and immediately distributes the contract's entire live balance
    ///         across the configured recipients.
    /// @dev    Reverts on `amount == 0` to prevent useless gas burns. Sweeps
    ///         dust and any stray direct transfers along with the new deposit.
    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
        _distribute(IERC20(USDT).balanceOf(address(this)));
    }

    /// @notice Distributes whatever USDT currently sits in the contract.
    /// @dev    No-op (no events, no state change) when the live balance is 0.
    ///         Useful for sweeping stray direct transfers or accumulated dust
    ///         without having to make a fresh deposit.
    function flush() external whenNotPaused nonReentrant {
        uint256 balance = IERC20(USDT).balanceOf(address(this));
        if (balance == 0) return;
        _distribute(balance);
    }

    /// @notice Pauses `deposit()` and `flush()`. Owner only.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses `deposit()` and `flush()`. Owner only.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ------------------------------------------------------------------
    //  Read-only helpers
    // ------------------------------------------------------------------

    /// @notice Returns the configured recipients in order.
    function recipients() external view returns (address[] memory) {
        return _recipients;
    }

    /// @notice Returns the configured basis-point shares in the same order
    ///         as `recipients()`.
    function basisPoints() external view returns (uint256[] memory) {
        return _basisPoints;
    }

    /// @notice Dust left over from the most recent distribution.
    /// @dev    Reflects only the rounding remainder from the last `_distribute`
    ///         call. To see all USDT currently sitting in the contract
    ///         (including any stray direct transfers received afterwards),
    ///         call `IERC20(USDT).balanceOf(<distributor>)` directly.
    function dustBalance() external view returns (uint256) {
        return _dustBalance;
    }

    /// @notice Number of configured recipients.
    function recipientCount() external view returns (uint256) {
        return _recipients.length;
    }

    // ------------------------------------------------------------------
    //  Internal
    // ------------------------------------------------------------------

    /// @dev Splits `total` across recipients per basis points; remainder stays
    ///      in the contract as dust and is recorded in `_dustBalance`. Always
    ///      called with the contract's live balance, so dust from prior
    ///      distributions (which is part of that balance) is automatically
    ///      rolled into the current one.
    function _distribute(uint256 total) internal {
        uint256 paid;
        uint256 len = _recipients.length;
        for (uint256 i; i < len; ++i) {
            uint256 share = (total * _basisPoints[i]) / TOTAL_BPS;
            if (share != 0) {
                IERC20(USDT).safeTransfer(_recipients[i], share);
                emit RecipientPaid(_recipients[i], share);
                paid += share;
            }
        }
        uint256 dust = total - paid;
        _dustBalance = dust;
        if (dust != 0) emit DustAccumulated(dust);
        emit Distributed(total, dust);
    }
}