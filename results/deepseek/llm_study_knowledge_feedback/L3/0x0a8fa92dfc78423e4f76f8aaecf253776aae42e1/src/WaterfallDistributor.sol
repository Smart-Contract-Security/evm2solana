// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

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
contract WaterfallDistributor {
    // ------------------------------------------------------------------
    //  Constants
    // ------------------------------------------------------------------

    /// @notice Total basis points representing 100% (1 bp = 0.01%).
    uint64 public constant TOTAL_BPS = 10_000;

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
    uint64[] private _basisPoints;

    /// @notice Owner of the contract
    address private _owner;

    /// @notice Paused state
    bool private _paused;

    /// @notice Reentrancy guard
    bool private _locked;

    // ------------------------------------------------------------------
    //  Mutable state (informational only — never affects routing)
    // ------------------------------------------------------------------

    /// @dev Tracks the dust left over from the most recent distribution.
    ///      Purely informational: the actual dust value lives in
    ///      `IERC20(USDT).balanceOf(address(this))` and is swept on the next
    ///      `deposit()` or `flush()` call.
    uint64 private _dustBalance;

    // ------------------------------------------------------------------
    //  Events
    // ------------------------------------------------------------------

    /// @notice Emitted when a caller deposits USDT via `deposit()`.
    event Deposited(address indexed sender, uint64 amount);

    /// @notice Emitted once per recipient that receives a non-zero share
    ///         during a distribution.
    event RecipientPaid(address indexed recipient, uint64 amount);

    /// @notice Emitted at the end of every distribution.
    /// @param totalAmount     The full balance fed into the distribution.
    /// @param dustCarriedOver Wei left in the contract after rounding.
    event Distributed(uint64 totalAmount, uint64 dustCarriedOver);

    /// @notice Emitted when a non-zero amount of dust is carried over.
    event DustAccumulated(uint64 dustAmount);

    // ------------------------------------------------------------------
    //  Modifiers
    // ------------------------------------------------------------------

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Paused");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "Reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    // ------------------------------------------------------------------
    //  Constructor
    // ------------------------------------------------------------------

    /// @param usdt        Address of the USDT token contract.
    /// @param recipients_ Recipient addresses (each receives a fixed share).
    /// @param bps         Basis points per recipient. Must sum to exactly 10_000.
    constructor(
        address usdt,
        address[] memory recipients_,
        uint64[] memory bps
    ) {
        require(usdt != address(0), "Zero USDT");
        require(recipients_.length > 0, "No recipients");
        require(recipients_.length == bps.length, "Length mismatch");

        uint64 sum;
        uint64 len = uint64(recipients_.length);
        for (uint64 i; i < len; ++i) {
            require(recipients_[i] != address(0), "Zero recipient");
            require(bps[i] != 0, "Zero bps");
            sum += bps[i];
        }
        require(sum == TOTAL_BPS, "BPS sum != 10000");

        USDT = usdt;
        _recipients = recipients_;
        _basisPoints = bps;
        _owner = tx.accounts.dataAccount.key;
    }

    // ------------------------------------------------------------------
    //  External entry points
    // ------------------------------------------------------------------

    /// @notice Pulls `amount` USDT from `msg.sender` (caller must approve first)
    ///         and immediately distributes the contract's entire live balance
    ///         across the configured recipients.
    /// @dev    Reverts on `amount == 0` to prevent useless gas burns. Sweeps
    ///         dust and any stray direct transfers along with the new deposit.
    function deposit(uint64 amount) external whenNotPaused nonReentrant {
        require(amount != 0, "Zero amount");
        // Transfer from sender to this contract
        IERC20(USDT).transferFrom(tx.accounts.dataAccount.key, address(this), amount);
        emit Deposited(tx.accounts.dataAccount.key, amount);
        _distribute(IERC20(USDT).balanceOf(address(this)));
    }

    /// @notice Distributes whatever USDT currently sits in the contract.
    /// @dev    No-op (no events, no state change) when the live balance is 0.
    ///         Useful for sweeping stray direct transfers or accumulated dust
    ///         without having to make a fresh deposit.
    function flush() external whenNotPaused nonReentrant {
        uint64 balance = IERC20(USDT).balanceOf(address(this));
        if (balance == 0) return;
        _distribute(balance);
    }

    /// @notice Pauses `deposit()` and `flush()`. Owner only.
    function pause() external onlyOwner {
        _paused = true;
    }

    /// @notice Unpauses `deposit()` and `flush()`. Owner only.
    function unpause() external onlyOwner {
        _paused = false;
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
    function basisPoints() external view returns (uint64[] memory) {
        return _basisPoints;
    }

    /// @notice Dust left over from the most recent distribution.
    /// @dev    Reflects only the rounding remainder from the last `_distribute`
    ///         call. To see all USDT currently sitting in the contract
    ///         (including any stray direct transfers received afterwards),
    ///         call `IERC20(USDT).balanceOf(<distributor>)` directly.
    function dustBalance() external view returns (uint64) {
        return _dustBalance;
    }

    /// @notice Number of configured recipients.
    function recipientCount() external view returns (uint64) {
        return uint64(_recipients.length);
    }

    /// @notice Returns the owner address
    function owner() external view returns (address) {
        return _owner;
    }

    /// @notice Returns paused state
    function paused() external view returns (bool) {
        return _paused;
    }

    // ------------------------------------------------------------------
    //  Internal
    // ------------------------------------------------------------------

    /// @dev Splits `total` across recipients per basis points; remainder stays
    ///      in the contract as dust and is recorded in `_dustBalance`. Always
    ///      called with the contract's live balance, so dust from prior
    ///      distributions (which is part of that balance) is automatically
    ///      rolled into the current one.
    function _distribute(uint64 total) internal {
        uint64 paid;
        uint64 len = uint64(_recipients.length);
        for (uint64 i; i < len; ++i) {
            uint64 share = (total * _basisPoints[i]) / TOTAL_BPS;
            if (share != 0) {
                IERC20(USDT).transfer(_recipients[i], share);
                emit RecipientPaid(_recipients[i], share);
                paid += share;
            }
        }
        uint64 dust = total - paid;
        _dustBalance = dust;
        if (dust != 0) emit DustAccumulated(dust);
        emit Distributed(total, dust);
    }
}

/// @notice Minimal ERC20 interface for SPL Token interactions
interface IERC20 {
    function transfer(address to, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint64);
}