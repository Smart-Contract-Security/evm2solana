// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

    /// @dev Owner address for access control.
    address private _owner;

    /// @dev Pause state.
    bool private _paused;

    /// @dev Reentrancy guard state.
    uint256 private _status;

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

    /// @notice Emitted when ownership is transferred.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when the contract is paused.
    event Paused(address account);

    /// @notice Emitted when the contract is unpaused.
    event Unpaused(address account);

    // ------------------------------------------------------------------
    //  Errors
    // ------------------------------------------------------------------

    // Custom errors are not supported on Solana; using string revert messages instead.

    // ------------------------------------------------------------------
    //  Modifiers
    // ------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier nonReentrant() {
        require(_status != 2, "ReentrancyGuard: reentrant call");
        _status = 2;
        _;
        _status = 1;
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
        uint256[] memory bps
    ) {
        require(usdt != address(0), "ZeroAddress");
        require(recipients_.length != 0, "EmptyRecipients");
        require(recipients_.length == bps.length, "LengthMismatch");

        uint256 sum;
        uint256 len = recipients_.length;
        for (uint256 i; i < len; ++i) {
            require(recipients_[i] != address(0), "ZeroAddress");
            require(bps[i] != 0, "ZeroBasisPoints");
            sum += bps[i];
        }
        require(sum == TOTAL_BPS, "InvalidBasisPoints");

        USDT = usdt;
        _recipients = recipients_;
        _basisPoints = bps;
        _owner = msg.sender;
        _status = 1; // _NOT_ENTERED
        emit OwnershipTransferred(address(0), msg.sender);
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
        require(amount != 0, "ZeroAmount");
        _safeTransferFrom(USDT, msg.sender, address(this), amount);
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

    /// @notice Returns the current owner address.
    function owner() external view returns (address) {
        return _owner;
    }

    /// @notice Returns true if the contract is paused.
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
    function _distribute(uint256 total) internal {
        uint256 paid;
        uint256 len = _recipients.length;
        for (uint256 i; i < len; ++i) {
            uint256 share = (total * _basisPoints[i]) / TOTAL_BPS;
            if (share != 0) {
                _safeTransfer(USDT, _recipients[i], share);
                emit RecipientPaid(_recipients[i], share);
                paid += share;
            }
        }
        uint256 dust = total - paid;
        _dustBalance = dust;
        if (dust != 0) emit DustAccumulated(dust);
        emit Distributed(total, dust);
    }

    function _pause() internal {
        require(!_paused, "Pausable: paused");
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        require(_paused, "Pausable: not paused");
        _paused = false;
        emit Unpaused(msg.sender);
    }

    // ------------------------------------------------------------------
    //  SafeERC20 inline implementations (replaces OpenZeppelin library)
    // ------------------------------------------------------------------

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        require(success, "SafeERC20: transfer failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: transfer returned false");
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        require(success, "SafeERC20: transferFrom failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: transferFrom returned false");
        }
    }
}

/// @notice Minimal IERC20 interface for Solana compatibility.
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}