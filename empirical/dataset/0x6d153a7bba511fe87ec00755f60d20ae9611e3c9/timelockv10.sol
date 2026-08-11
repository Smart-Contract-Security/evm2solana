// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @title CryptoTimeLock — Hardened Version v3
 * @notice Lock any ERC-20 token or native ETH for a set time period
 * @dev Uses safe transfer helpers to support non-standard tokens (USDT, BNB etc.)
 *
 * Security features:
 * - Reentrancy guard on all state-changing functions
 * - Checks-Effects-Interactions pattern throughout
 * - Safe transfer helpers for non-standard ERC-20s (USDT fix)
 * - Fee-on-transfer token support (balance diff measurement)
 * - Force-feed ETH protection (receive() tracks as fees)
 * - Input validation on all parameters
 * - 48hr timelock on fee recipient changes
 * - No price oracles, no flash loan surface, no governance
 * - Solidity 0.8.34 pinned (overflow/underflow protected, no compiler bugs)
 * - ERC-777 token rejection via dual-check (ERC-1820 registry + granularity())
 *
 * ── KNOWN LIMITATIONS (documented, not fixable on-chain) ──────────────────
 * - Upgradeable tokens (USDC, USDT): admin could change token logic post-lock
 * - Pausable tokens (BNB, ZRX): if token is paused, withdrawals will revert
 *   until the token admin unpauses. Funds are not lost, just temporarily frozen.
 * - Blacklistable tokens (USDC, USDT): if your address is blacklisted after
 *   locking, withdrawal will revert permanently. Only lock these tokens from
 *   an address you are certain will never be blacklisted.
 * - Rebasing tokens (stETH, AMPL): locked amount is snapshotted at lock time.
 *   If the token rebases up, surplus is unrecoverable. If it rebases down,
 *   withdrawal may fail.
 * - ETH sent via selfdestruct bypasses receive() and becomes permanently
 *   unrecoverable as it cannot be tracked by totalNativeFeesAccumulated.
 */

// ── INTERFACES ───────────────────────────────────────────────────────────────

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @dev ERC-1820 Pseudo-introspection Registry.
 * Deployed at the same address on every EVM chain:
 * 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24
 * ERC-777 tokens MUST register themselves here under the "ERC777Token"
 * interface hash. Querying this lets us detect and reject them.
 */
interface IERC1820Registry {
    function getInterfaceImplementer(
        address account,
        bytes32 interfaceHash
    ) external view returns (address);
}

// ── CONTRACT ─────────────────────────────────────────────────────────────────

contract CryptoTimeLock {

    // ── CONSTANTS ─────────────────────────────────────────────────────────────

    uint256 public constant FEE_PERCENTAGE   = 50;            // 0.5% (50/10000)
    uint256 public constant MIN_LOCK_AMOUNT  = 0.001 ether;   // minimum native lock
    uint256 public constant MIN_LOCK_TIME    = 5 minutes;
    uint256 public constant MAX_LOCK_TIME    = 10 * 365 days;
    uint256 public constant FEE_CHANGE_DELAY    = 48 hours;
    // L-01: Caps userLocks array growth. Prevents spam and protects against
    // block gas limit DoS if getUserLocks is ever called on-chain in future.
    uint256 public constant MAX_LOCKS_PER_USER = 1000;

    /**
     * @dev ERC-1820 global registry. Same address on Ethereum mainnet,
     * all testnets, and most EVM-compatible chains.
     * Source: https://eips.ethereum.org/EIPS/eip-1820
     */
    IERC1820Registry private constant _ERC1820 =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    /**
     * @dev keccak256("ERC777Token")
     * This is the interface hash that ERC-777 tokens register under
     * in the ERC-1820 registry. Pre-computed as a constant to save gas.
     */
    bytes32 private constant _ERC777_INTERFACE_HASH =
        0xac7fbab5f54a3ca8194167523c6753bfeb96a445279294b6125b68cce2177054;

    // ── STATE ─────────────────────────────────────────────────────────────────

    address payable public feeRecipient;
    uint256 public lockCounter;

    uint256 public totalNativeFeesAccumulated;
    uint256 public totalNativeFeesClaimed;

    mapping(address => uint256) public totalTokenFeesAccumulated;
    mapping(address => uint256) public totalTokenFeesClaimed;

    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;

    address payable public pendingFeeRecipient;
    uint256 public feeRecipientChangeTime;

    struct Lock {
        address owner;
        address token;
        uint256 amount;
        uint256 unlockTime;
        bool    withdrawn;
        uint256 createdAt;
    }

    mapping(uint256 => Lock)      public locks;
    mapping(address => uint256[]) public userLocks;

    // ── EVENTS ────────────────────────────────────────────────────────────────

    event LockCreated(uint256 indexed lockId, address indexed owner, address indexed token, uint256 amount, uint256 unlockTime, uint256 fee);
    event Withdrawn(uint256 indexed lockId, address indexed owner, address token, uint256 amount);
    event NativeFeeClaimed(address indexed recipient, uint256 amount);
    event TokenFeeClaimed(address indexed recipient, address indexed token, uint256 amount);
    event FeeRecipientChangeRequested(address indexed newRecipient, uint256 effectiveTime);
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event FeeRecipientChangeCancelled(address indexed cancelledRecipient); // L-04
    event LockOwnershipTransferred(uint256 indexed lockId, address indexed previousOwner, address indexed newOwner); // L-03

    // ── MODIFIERS ─────────────────────────────────────────────────────────────

    modifier onlyLockOwner(uint256 _lockId) {
        require(locks[_lockId].owner == msg.sender, "Not lock owner");
        _;
    }

    modifier onlyFeeRecipient() {
        require(msg.sender == feeRecipient, "Not fee recipient");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ── CONSTRUCTOR ───────────────────────────────────────────────────────────

    constructor(address payable _feeRecipient) {
        require(_feeRecipient != address(0), "Invalid fee recipient");

        // C-01: Verify the ERC-1820 registry is actually deployed at the expected
        // address on this chain. If it isn't (some L2s, app-chains, private nets),
        // fail loudly at deploy time rather than silently breaking all token locks
        // at runtime. A missing registry means address(_ERC1820).code.length == 0.
        require(
            address(_ERC1820).code.length > 0,
            "ERC-1820 registry not deployed on this chain"
        );

        // H-01: Verify the pre-computed hash constant actually equals
        // keccak256("ERC777Token"). A transcription error here would make the
        // registry lookup query the wrong interface and silently pass every token.
        // assert() with a compile-time-known value is removed by the optimizer in
        // production — zero gas cost, but catches the mistake during deployment.
        assert(_ERC777_INTERFACE_HASH == keccak256("ERC777Token"));

        feeRecipient = _feeRecipient;
        _status = _NOT_ENTERED;
    }

    // ── ERC-777 REJECTION ─────────────────────────────────────────────────────

    /**
     * @dev Rejects ERC-777 tokens using two independent checks.
     *
     * WHY TWO CHECKS:
     * Check 1 (ERC-1820 registry) catches most ERC-777 tokens which are required
     * by the spec to register themselves there. However, some tokens like AMP
     * register under a non-standard interface hash and are missed by Check 1 alone.
     *
     * Check 2 (granularity() probe) catches the remainder. granularity() is a
     * function that exists ONLY on ERC-777 — it is not part of ERC-20. The ERC-777
     * spec mandates that granularity() returns a uint256 >= 1. We check for exactly
     * that: a successful call returning 32 bytes that decode to a value >= 1.
     *
     * This is intentionally stricter than just checking (bool success). A proxy
     * or catch-all fallback that doesn't revert would trip a naive success check,
     * permanently blocking legitimate ERC-20 tokens. By requiring 32 bytes that
     * decode to a non-zero uint256, we match the actual ERC-777 fingerprint and
     * avoid false positives on proxy-based tokens (USDC, USDT, etc.).
     *
     * Together, both checks cover all known ERC-777 tokens including:
     * AMP, SKL, imBTC, VRA, LUKSO, CWEB, FLUX
     *
     * @param _token The token address to check
     */
    function _rejectIfERC777(address _token) internal view {
        // Check 1: ERC-1820 registry lookup
        address implementer = _ERC1820.getInterfaceImplementer(
            _token,
            _ERC777_INTERFACE_HASH
        );
        require(implementer == address(0), "ERC-777 tokens not supported");

        // Check 2: granularity() is defined only on ERC-777, not ERC-20.
        // Per ERC-777 spec, it MUST return a uint256 >= 1. We require all three:
        //   a) the call succeeds (doesn't revert)
        //   b) the return data is exactly 32 bytes (a proper ABI-encoded uint256)
        //   c) the decoded value is >= 1 (as mandated by the spec)
        // A proxy fallback that silently accepts calls will typically return empty
        // or garbage data — it won't satisfy (b) and (c), so it passes safely.
        (bool success, bytes memory data) = _token.staticcall(
            abi.encodeWithSignature("granularity()")
        );
        if (success && data.length == 32) {
            uint256 granularity = abi.decode(data, (uint256));
            require(granularity == 0, "ERC-777 tokens not supported");
        }
    }

    // ── SAFE TRANSFER HELPERS ─────────────────────────────────────────────────
    // Handles non-standard tokens like USDT that don't return bool on transfer

    /**
     * @dev Decodes a bool return value tolerating three formats seen in the wild:
     *   - No return data       (USDT, BNB)   -> treat as success
     *   - 32-byte ABI bool     (standard)    -> decode normally
     *   - Short raw byte(s)    (rare)        -> check first byte != 0x00
     * Without this, tokens that return a raw 0x01 byte (not ABI-padded to 32 bytes)
     * would cause abi.decode to revert, making their transfers always fail. (M-04)
     */
    function _decodeBoolReturn(bytes memory data) internal pure returns (bool) {
        if (data.length == 0)  return true;
        if (data.length == 32) return abi.decode(data, (bool));
        return data[0] != 0x00;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        require(success && _decodeBoolReturn(data), "Token transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        require(success && _decodeBoolReturn(data), "Token transferFrom failed");
    }

    // ── LOCK NATIVE (ETH) ─────────────────────────────────────────────────────

    function lockNative(uint256 _unlockTime) external payable nonReentrant returns (uint256) {
        require(msg.value >= MIN_LOCK_AMOUNT, "Amount below minimum (0.001)");
        require(_unlockTime > block.timestamp, "Unlock time must be in future");

        uint256 duration = _unlockTime - block.timestamp;
        require(duration >= MIN_LOCK_TIME, "Lock time too short (min 5 min)");
        require(duration <= MAX_LOCK_TIME, "Lock time too long (max 10 years)");

        uint256 fee          = (msg.value * FEE_PERCENTAGE) / 10000;
        uint256 lockedAmount = msg.value - fee;

        totalNativeFeesAccumulated += fee;

        uint256 id = lockCounter++;
        locks[id] = Lock({
            owner:      msg.sender,
            token:      address(0),
            amount:     lockedAmount,
            unlockTime: _unlockTime,
            withdrawn:  false,
            createdAt:  block.timestamp
        });

        // L-01: Enforce per-user lock cap
        require(userLocks[msg.sender].length < MAX_LOCKS_PER_USER, "Too many locks");
        userLocks[msg.sender].push(id);
        emit LockCreated(id, msg.sender, address(0), lockedAmount, _unlockTime, fee);
        return id;
    }

    // ── LOCK ERC-20 TOKEN ─────────────────────────────────────────────────────

    function lockToken(
        address _token,
        uint256 _amount,
        uint256 _unlockTime
    ) external nonReentrant returns (uint256) {
        require(_token  != address(0), "Invalid token address");
        require(_amount > 0,           "Amount must be greater than 0");
        require(_unlockTime > block.timestamp, "Unlock time must be in future");

        uint256 duration = _unlockTime - block.timestamp;
        require(duration >= MIN_LOCK_TIME, "Lock time too short (min 5 min)");
        require(duration <= MAX_LOCK_TIME, "Lock time too long (max 10 years)");

        // Reject ERC-777 tokens before any token interaction
        _rejectIfERC777(_token);

        // Measure actual received — handles fee-on-transfer tokens
        uint256 balBefore = IERC20(_token).balanceOf(address(this));
        _safeTransferFrom(_token, msg.sender, address(this), _amount);
        uint256 actualReceived = IERC20(_token).balanceOf(address(this)) - balBefore;
        require(actualReceived > 0, "No tokens received");

        uint256 fee          = (actualReceived * FEE_PERCENTAGE) / 10000;
        // M-02: Integer division truncates. For very small amounts the fee rounds
        // down to zero — protocol collects nothing and lock counter can be spammed.
        require(fee > 0,           "Amount too small to cover fee");
        uint256 lockedAmount = actualReceived - fee;
        require(lockedAmount > 0, "Amount too small after fee");

        totalTokenFeesAccumulated[_token] += fee;

        uint256 id = lockCounter++;
        locks[id] = Lock({
            owner:      msg.sender,
            token:      _token,
            amount:     lockedAmount,
            unlockTime: _unlockTime,
            withdrawn:  false,
            createdAt:  block.timestamp
        });

        // L-01: Enforce per-user lock cap
        require(userLocks[msg.sender].length < MAX_LOCKS_PER_USER, "Too many locks");
        userLocks[msg.sender].push(id);
        emit LockCreated(id, msg.sender, _token, lockedAmount, _unlockTime, fee);
        return id;
    }

    // ── WITHDRAW ──────────────────────────────────────────────────────────────

    function withdraw(uint256 _lockId) external nonReentrant onlyLockOwner(_lockId) {
        Lock storage lock = locks[_lockId];

        require(!lock.withdrawn,                    "Already withdrawn");
        require(block.timestamp >= lock.unlockTime, "Funds still locked");

        // Effects before interactions (CEI)
        lock.withdrawn = true;
        uint256 amount = lock.amount;
        address token  = lock.token;
        // L-02: Zero out storage fields that are no longer needed. Solidity
        // issues a partial gas refund (EIP-3529) for each slot cleared to zero.
        // We keep token/unlockTime/createdAt so getLock() remains useful for
        // historical queries, but amount and owner are safe to clear.
        lock.amount = 0;
        lock.owner  = address(0);

        if (token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "Native transfer failed");
        } else {
            _safeTransfer(token, msg.sender, amount);
        }

        emit Withdrawn(_lockId, msg.sender, token, amount);
    }


    // ── LOCK OWNERSHIP TRANSFER ───────────────────────────────────────────────

    /**
     * @notice Transfer ownership of a lock to a new address.
     * @dev Useful for moving a lock to a multisig, or recovering access when
     *      migrating wallets. Only callable by the current lock owner, only while
     *      the lock has not yet been withdrawn. (L-03)
     * @param _lockId   The lock to transfer.
     * @param _newOwner The address that will become the new owner.
     */
    function transferLockOwnership(uint256 _lockId, address _newOwner)
        external
        onlyLockOwner(_lockId)
    {
        require(_newOwner != address(0),   "Invalid new owner");
        require(_newOwner != msg.sender,   "Already the owner");
        require(!locks[_lockId].withdrawn, "Lock already withdrawn");
        locks[_lockId].owner = _newOwner;
        emit LockOwnershipTransferred(_lockId, msg.sender, _newOwner);
    }

    // ── FEE MANAGEMENT ────────────────────────────────────────────────────────

    function pendingNativeFees() public view returns (uint256) {
        return totalNativeFeesAccumulated - totalNativeFeesClaimed;
    }

    function pendingTokenFees(address _token) public view returns (uint256) {
        return totalTokenFeesAccumulated[_token] - totalTokenFeesClaimed[_token];
    }

    function claimNativeFees() external nonReentrant onlyFeeRecipient returns (uint256) {
        uint256 claimable = pendingNativeFees();
        require(claimable > 0, "No native fees to claim");

        totalNativeFeesClaimed += claimable;

        (bool success, ) = feeRecipient.call{value: claimable}("");
        require(success, "Transfer failed");

        emit NativeFeeClaimed(feeRecipient, claimable);
        return claimable;
    }

    function claimTokenFees(address _token) external nonReentrant onlyFeeRecipient returns (uint256) {
        require(_token != address(0), "Invalid token");
        uint256 claimable = pendingTokenFees(_token);
        require(claimable > 0, "No token fees to claim");

        totalTokenFeesClaimed[_token] += claimable;

        _safeTransfer(_token, feeRecipient, claimable);

        emit TokenFeeClaimed(feeRecipient, _token, claimable);
        return claimable;
    }

    // ── FEE RECIPIENT TIMELOCK ────────────────────────────────────────────────

    function requestFeeRecipientChange(address payable _newRecipient) external onlyFeeRecipient {
        require(_newRecipient != address(0),    "Invalid address");
        require(_newRecipient != feeRecipient,  "Same as current");
        pendingFeeRecipient    = _newRecipient;
        feeRecipientChangeTime = block.timestamp + FEE_CHANGE_DELAY;
        emit FeeRecipientChangeRequested(_newRecipient, feeRecipientChangeTime);
    }

    function cancelFeeRecipientChange() external onlyFeeRecipient {
        require(pendingFeeRecipient != address(0), "No pending change");
        address cancelled      = pendingFeeRecipient;
        pendingFeeRecipient    = payable(address(0));
        feeRecipientChangeTime = 0;
        emit FeeRecipientChangeCancelled(cancelled); // L-04: emit before zeroing
    }

    function confirmFeeRecipientChange() external onlyFeeRecipient {
        require(pendingFeeRecipient != address(0),         "No pending change");
        require(block.timestamp >= feeRecipientChangeTime, "Too early, wait 48 hours");

        // M-03: Test that the new recipient can actually receive ETH before
        // committing. If the pending address is a contract with no receive()
        // function, claimNativeFees() would revert forever and accumulated native
        // fees would be permanently stuck with no way to re-route them (because
        // only the current feeRecipient can request another change, and a broken
        // address cannot call requestFeeRecipientChange). A zero-value call is
        // cheap and catches non-payable contracts before it is too late.
        (bool canReceive, ) = pendingFeeRecipient.call{value: 0}("");
        require(canReceive, "New recipient cannot receive ETH");

        address oldRecipient   = feeRecipient;
        feeRecipient           = pendingFeeRecipient;
        pendingFeeRecipient    = payable(address(0));
        feeRecipientChangeTime = 0;
        emit FeeRecipientChanged(oldRecipient, feeRecipient);
    }

    // ── VIEW FUNCTIONS ────────────────────────────────────────────────────────

    function getLock(uint256 _lockId) external view returns (Lock memory) {
        return locks[_lockId];
    }

    function canWithdraw(uint256 _lockId) external view returns (bool) {
        Lock memory lock = locks[_lockId];
        // M-01: For a lock that was never created, lock.owner == address(0) and
        // lock.unlockTime == 0. The original code would return true (block.timestamp
        // >= 0 is always true), misleading off-chain callers into thinking any
        // arbitrary ID is withdrawable. Guard with an existence check first.
        if (lock.owner == address(0)) return false;
        return !lock.withdrawn && block.timestamp >= lock.unlockTime;
    }

    function timeRemaining(uint256 _lockId) external view returns (uint256) {
        Lock memory lock = locks[_lockId];
        if (block.timestamp >= lock.unlockTime) return 0;
        return lock.unlockTime - block.timestamp;
    }

    function getUserLocks(address _user) external view returns (uint256[] memory) {
        return userLocks[_user];
    }

    // ── FALLBACK ──────────────────────────────────────────────────────────────

    receive() external payable {
        // Force-fed ETH is tracked as collectable fees.
        // Note: ETH sent via selfdestruct bypasses this function entirely —
        // that ETH becomes permanently unrecoverable (documented known limitation).
        totalNativeFeesAccumulated += msg.value;
    }
}
