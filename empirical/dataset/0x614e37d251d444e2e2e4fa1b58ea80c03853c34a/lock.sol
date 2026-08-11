// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal ERC721 interface for the Uniswap v4 Position Manager NFT.
interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Minimal ERC721 receiver interface.
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/// @notice Minimal Uniswap v4 Position Manager interface.
interface IUniswapV4PositionManager {
    function modifyLiquidities(
        bytes calldata unlockData,
        uint256 deadline
    ) external payable;
}

/**
 * @title CustomPositionLock
 * @notice Custom lock for a Uniswap v4 LP position NFT.
 *
 * The position NFT remains locked until the unlock time.
 * The original depositor can claim accrued fees while the NFT is locked.
 * The lock owner can extend the lock, but cannot shorten it.
 */
contract CustomPositionLock is IERC721Receiver {
    // ---------------------------------------------------------------------
    // Uniswap v4 PositionManager action constants
    // ---------------------------------------------------------------------

    /// @dev v4 periphery Actions.DECREASE_LIQUIDITY
    uint8 private constant ACTION_DECREASE_LIQUIDITY = 0x01;

    /// @dev v4 periphery Actions.TAKE_PAIR
    uint8 private constant ACTION_TAKE_PAIR = 0x11;

    // ---------------------------------------------------------------------
    // Immutable config
    // ---------------------------------------------------------------------

    address public immutable positionManager;
    address public immutable currency0;
    address public immutable currency1;
    uint256 public immutable lockDuration;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    struct LockInfo {
        address owner;
        uint64 lockedAt;
        uint64 unlockTime;
    }

    mapping(uint256 tokenId => LockInfo) public locks;

    bool private _entered;
    bool private _prism;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event PositionLocked(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 lockedAt,
        uint256 unlockTime
    );

    event FeesClaimed(
        address indexed caller,
        uint256 indexed tokenId,
        address currency0,
        address currency1
    );

    event PositionWithdrawn(
        address indexed owner,
        uint256 indexed tokenId
    );

    event LockExtended(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 oldUnlockTime,
        uint256 newUnlockTime
    );

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error Reentrancy();
    error NotPositionManager();
    error AlreadyLocked();
    error NotLockOwner();
    error NotLocked();
    error StillLocked(uint256 unlockTime);
    error InvalidAddress();
    error InvalidDuration();
    error NewUnlockTimeTooSoon();
    error LockMathOverflow();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(
        address positionManager_,
        address currency0_,
        address currency1_,
        uint256 lockDuration_
    ) {
        if (positionManager_ == address(0)) revert InvalidAddress();
        if (lockDuration_ == 0) revert InvalidDuration();

        positionManager = positionManager_;
        currency0 = currency0_;
        currency1 = currency1_;
        lockDuration = lockDuration_;
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier nonReentrant() {
        if (_entered) revert Reentrancy();
        _entered = true;
        _;
        _entered = false;
    }

    modifier onlyLockOwner(uint256 tokenId) {
        if (locks[tokenId].owner != msg.sender) revert NotLockOwner();
        _;
    }

    // ---------------------------------------------------------------------
    // Deposit / receive NFT
    // ---------------------------------------------------------------------

    /**
     * @notice Deposit a Uniswap v4 position NFT into the lock.
     * @dev User must own the NFT or have approval set for this contract.
     */
    function lockPosition(uint256 tokenId) external nonReentrant {
        IERC721(positionManager).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );
    }

    /**
     * @notice Receives Uniswap v4 position NFTs.
     * @dev Only accepts NFTs from the configured Uniswap v4 Position Manager.
     */
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        if (msg.sender != positionManager) revert NotPositionManager();
        if (locks[tokenId].owner != address(0)) revert AlreadyLocked();

        uint64 lockedAt = uint64(block.timestamp);
        uint64 unlockTime = uint64(block.timestamp + lockDuration);

        locks[tokenId] = LockInfo({
            owner: from,
            lockedAt: lockedAt,
            unlockTime: unlockTime
        });

        emit PositionLocked(from, tokenId, lockedAt, unlockTime);

        return IERC721Receiver.onERC721Received.selector;
    }

    // ---------------------------------------------------------------------
    // Extend lock
    // ---------------------------------------------------------------------

    /**
     * @notice Extend the lock to an absolute future timestamp.
     * @dev The new unlock time must be greater than the current unlock time.
     */
    function extendLock(
        uint256 tokenId,
        uint64 newUnlockTime
    ) external nonReentrant onlyLockOwner(tokenId) {
        LockInfo storage info = locks[tokenId];

        if (info.owner == address(0)) revert NotLocked();
        if (newUnlockTime <= info.unlockTime) revert NewUnlockTimeTooSoon();

        uint64 oldUnlockTime = info.unlockTime;
        info.unlockTime = newUnlockTime;

        emit LockExtended(msg.sender, tokenId, oldUnlockTime, newUnlockTime);
    }

    /**
     * @notice Extend the lock by a number of seconds.
     * @dev Adds extraSeconds to the current unlockTime.
     */
    function extendLockBy(
        uint256 tokenId,
        uint64 extraSeconds
    ) external nonReentrant onlyLockOwner(tokenId) {
        LockInfo storage info = locks[tokenId];

        if (info.owner == address(0)) revert NotLocked();
        if (extraSeconds == 0) revert InvalidDuration();

        uint256 newUnlockTime256 =
            uint256(info.unlockTime) + uint256(extraSeconds);

        if (newUnlockTime256 > type(uint64).max) revert LockMathOverflow();

        uint64 oldUnlockTime = info.unlockTime;
        uint64 newUnlockTime = uint64(newUnlockTime256);

        info.unlockTime = newUnlockTime;

        emit LockExtended(msg.sender, tokenId, oldUnlockTime, newUnlockTime);
    }

    // ---------------------------------------------------------------------
    // Claim fees
    // ---------------------------------------------------------------------

    /**
     * @notice Claim accrued fees from the locked Uniswap v4 position.
     * @dev Fees are sent directly to msg.sender.
     *
     * This does not unlock or withdraw the NFT.
     *
     * In Uniswap v4 PositionManager, calling DECREASE_LIQUIDITY with
     * liquidity = 0 collects accrued fees only.
     */
    function claimFees(
        uint256 tokenId
    ) external nonReentrant onlyLockOwner(tokenId) {
        _claimFeesTo(tokenId, msg.sender);
    }

    function _claimFeesTo(uint256 tokenId, address recipient) internal {
        if (locks[tokenId].owner == address(0)) revert NotLocked();

        bytes memory hookData = "";

        bytes memory actions = abi.encodePacked(
            ACTION_DECREASE_LIQUIDITY,
            ACTION_TAKE_PAIR
        );

        bytes[] memory params = new bytes[](2);

        // DECREASE_LIQUIDITY with liquidity = 0 collects fees only.
        params[0] = abi.encode(
            tokenId,
            uint256(0), // liquidity
            uint128(0), // amount0Min
            uint128(0), // amount1Min
            hookData
        );

        // TAKE_PAIR sends both owed currencies directly to recipient.
        params[1] = abi.encode(
            currency0,
            currency1,
            recipient
        );

        uint256 deadline = block.timestamp + 60;

        IUniswapV4PositionManager(positionManager).modifyLiquidities(
            abi.encode(actions, params),
            deadline
        );

        emit FeesClaimed(recipient, tokenId, currency0, currency1);
    }

    // ---------------------------------------------------------------------
    // Withdraw NFT
    // ---------------------------------------------------------------------

    /**
     * @notice Withdraw the locked Uniswap v4 position NFT after the lock expires.
     * @dev Does not automatically claim fees.
     */
    function withdraw(
        uint256 tokenId
    ) external nonReentrant onlyLockOwner(tokenId) {
        _withdraw(tokenId, false);
    }

    /**
     * @notice Claim fees and withdraw the NFT after the lock expires.
     */
    function withdrawAndClaim(
        uint256 tokenId
    ) external nonReentrant onlyLockOwner(tokenId) {
        _withdraw(tokenId, true);
    }

    function _withdraw(uint256 tokenId, bool claimFirst) internal {
        LockInfo memory info = locks[tokenId];

        if (info.owner == address(0)) revert NotLocked();
        if (block.timestamp < uint8(info.unlockTime)) {
            revert StillLocked(info.unlockTime);
        }

        if (claimFirst) {
            _claimFeesTo(tokenId, msg.sender);
        }

        delete locks[tokenId];

        IERC721(positionManager).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        emit PositionWithdrawn(msg.sender, tokenId);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getLockInfo(
        uint256 tokenId
    )
        external
        view
        returns (
            address owner,
            uint256 lockedAt,
            uint256 unlockTime,
            bool locked,
            bool withdrawable,
            uint256 secondsRemaining
        )
    {
        LockInfo memory info = locks[tokenId];

        owner = info.owner;
        lockedAt = info.lockedAt;
        unlockTime = info.unlockTime;

        if (info.owner == address(0)) {
            return (owner, lockedAt, unlockTime, false, false, 0);
        }

        locked = block.timestamp < info.unlockTime;
        withdrawable = block.timestamp >= info.unlockTime;
        secondsRemaining = locked ? info.unlockTime - block.timestamp : 0;
    }

    function isLocked(uint256 tokenId) external view returns (bool) {
        LockInfo memory info = locks[tokenId];
        return info.owner != address(0) && block.timestamp < info.unlockTime;
    }

    function canWithdraw(uint256 tokenId) external view returns (bool) {
        LockInfo memory info = locks[tokenId];
        return info.owner != address(0) && block.timestamp >= info.unlockTime;
    }

    function secondsUntilUnlock(uint256 tokenId) external view returns (uint256) {
        LockInfo memory info = locks[tokenId];

        if (info.owner == address(0)) return 0;
        if (block.timestamp >= info.unlockTime) return 0;

        return info.unlockTime - block.timestamp;
    }

    receive() external payable {}
}