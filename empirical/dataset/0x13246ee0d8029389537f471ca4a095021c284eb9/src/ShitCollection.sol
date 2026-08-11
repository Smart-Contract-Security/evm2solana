// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IShitVerseFactoryLite {
    function isValidToken(address token) external view returns (bool);
}

abstract contract TransientReentrancyGuard {
    error Reentrancy();
    // keccak256("dogeshit.art.collection.reentrancy"). Inlined as a hex
    // literal — Solidity assembly only accepts direct number constants
    // by name, not constant expressions like keccak256(...).
    uint256 private constant _GUARD_SLOT =
        0x508e20f257d6b5a7012bffbb6c160e3f5986de2433628acfca3c918cb2cbbbfb;

    modifier nonReentrant() {
        assembly {
            if tload(_GUARD_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(_GUARD_SLOT, 1)
        }
        _;
        assembly { tstore(_GUARD_SLOT, 0) }
    }
}

/// @notice ShitCollection — permissionless art-collection redemption vault.
///   Anyone deposits an ERC20 reward + defines a set of factory-validated
///   arts and per-art amounts required to redeem.
///
///   Two art-destination modes:
///   - CREATOR_IMMEDIATE: arts flow straight from redeemer to creator.
///   - LOCKED: arts go to the vault for `lockDuration`; each redeemer
///     (NOT the creator) calls `claimLockedArts` after the lock to
///     pull their own contributed arts back.
///
/// @dev TRUST MODEL — permissionless but NOT fully trustless:
///   (1) Creators can drain their own reward pool any time via self-redeem
///       (hold the funds + can mint themselves the arts; alt-EOA bypasses
///       any same-address block). `deadline == 0` HARD-blocks `reclaim()`
///       and keeps redemption open forever, but does NOT block this drain —
///       read it as "creator gave up the formal refund hatch", not as
///       "funds are safe from creator".
///   (2) `owner` can withdraw ANY non-art ERC-20 — including active
///       collections' reward tokens — via `ownerWithdraw`. TRUSTED-ROLE
///       power, not dust rescue. Affected `redeem`/`reclaim` revert
///       until re-funded; `canRedeem` reflects this. Factory-validated
///       arts are off-limits (belong to LOCKED collections' creators).
///
/// @dev DualToken arts expose both ERC-20 and ERC-1155 over the same
///   `_balances`. Redeem uses the ERC-20 path; users approve once with
///   `type(uint256).max` (OZ never decrements max allowance).
contract ShitCollection is TransientReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 30-day floor. `openDuration == 0` is the special "permanent
    ///   pool" value and bypasses this; `lockDuration` has no such escape
    ///   hatch (LOCKED mode requires ≥ 30 days, CREATOR_IMMEDIATE forces 0).
    uint64 public constant MIN_DURATION = 30 days;

    /// @notice 96-year cap on any time period — human-scale upper bound
    ///   that catches typos like 9999 years.
    /// @dev INVARIANT: this cap also makes all uint64 `timestamp + duration`
    ///   arithmetic safe (createdAt + lockDuration, createdAt + openDuration),
    ///   keeping the sums ≪ uint64.max. The three `unchecked` blocks below
    ///   rely on this — do not raise MAX_DURATION without re-auditing them.
    uint64 public constant MAX_DURATION = 96 * 365 days;

    /// @notice Bounds redeem gas + create-time O(N²) dedup (≤120 cmp at N=16).
    uint256 public constant MAX_ARTS_PER_COLLECTION = 16;

    /// @notice Matches DualToken's editionSize; amounts must be whole multiples.
    uint256 public constant ART_UNIT = 1 ether;

    enum ArtDest { CREATOR_IMMEDIATE, LOCKED }

    IShitVerseFactoryLite public immutable FACTORY;

    /// @notice Trusted role — see TRUST MODEL (2) for scope.
    address public owner;

    // Packed layout — reorder changes storage AND getCollection ABI tuple.
    struct Collection {
        address creator;            // slot 0 [0:20]
        uint64  lockDuration;       // slot 0 [20:28]   — must be 0 for CREATOR_IMMEDIATE; 30d–96y for LOCKED
        ArtDest artDest;            // slot 0 [28]
        bool    reclaimed;          // slot 0 [29]
        address rewardToken;        // slot 1
        uint256 rewardAmount;       // slot 2
        uint64  maxRedemptions;     // slot 3 [0:8]
        uint64  redeemedCount;      // slot 3 [8:16]
        uint64  deadline;           // slot 3 [16:24]   — 0 = permanent pool (blocks reclaim entirely)
        uint64  createdAt;          // slot 3 [24:32]
        address[] arts;
        uint256[] amounts;
    }

    Collection[] private _collections;

    /// @dev (collectionId, redeemer) → outstanding LOCKED redemption count.
    ///   Incremented on LOCKED redeem, zeroed on `claimLockedArts`.
    mapping(uint256 => mapping(address => uint64)) private _userRedemptions;

    event CollectionCreated(
        uint256 indexed id,
        address indexed creator,
        address indexed rewardToken,
        uint256 rewardAmount,
        uint64  maxRedemptions,
        uint64  deadline,
        ArtDest artDest,
        uint64  lockDuration
    );
    event Redeemed(uint256 indexed id, address indexed user);
    event Reclaimed(uint256 indexed id, uint256 amountReturned);
    event LockedArtsClaimed(uint256 indexed id, address indexed user, uint64 count);
    event OwnerWithdrew(address indexed token, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error EmptyArtSet();
    error TooManyArts();
    error LengthMismatch();
    error ZeroAmount();
    error NonIntegerArtAmount();
    error NotShitVerseArt();
    error DuplicateArt();
    error InvalidLockConfig();
    error LockTooShort();
    error LockTooLong();
    error PoolDurationTooShort();
    error PoolDurationTooLong();
    error InvalidId();
    error Exhausted();
    error Expired();
    error NotCreator();
    error WrongMode();
    error StillLocked();
    error AlreadyReclaimed();
    error NothingToReclaim();
    error NothingToClaim();
    error DeadlineNotReached();
    error NoDeadline();
    error RewardCollidesWithArt();
    error NotOwner();
    error ArtNotWithdrawable();
    error ZeroOwner();
    error ZeroRecipient();
    error ZeroFactory();

    constructor(address factory, address owner_) {
        if (factory == address(0)) revert ZeroFactory();
        if (owner_  == address(0)) revert ZeroOwner();
        FACTORY = IShitVerseFactoryLite(factory);
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Create a collection. Pulls `rewardAmount * maxRedemptions`
    ///   from caller (must have approved). Fee-on-transfer / rebasing
    ///   reward tokens are NOT detected — creator's own footgun.
    function create(
        address[] calldata arts,
        uint256[] calldata amounts,
        address rewardToken,
        uint256 rewardAmount,
        uint64  maxRedemptions,
        uint64  openDuration,
        ArtDest artDest,
        uint64  lockDuration
    ) external nonReentrant returns (uint256 id) {
        if (arts.length == 0) revert EmptyArtSet();
        if (arts.length > MAX_ARTS_PER_COLLECTION) revert TooManyArts();
        if (arts.length != amounts.length) revert LengthMismatch();
        if (rewardAmount == 0 || maxRedemptions == 0) revert ZeroAmount();
        if (rewardToken == address(0)) revert ZeroAmount();
        if (openDuration != 0) {
            if (openDuration < MIN_DURATION) revert PoolDurationTooShort();
            if (openDuration > MAX_DURATION) revert PoolDurationTooLong();
        }

        if (artDest == ArtDest.LOCKED) {
            if (lockDuration < MIN_DURATION) revert LockTooShort();
            if (lockDuration > MAX_DURATION) revert LockTooLong();
        } else {
            if (lockDuration != 0) revert InvalidLockConfig();
        }

        // Reward/art disjointness keeps `redeemedCount × amounts[i]` and
        // `unused × rewardAmount` on non-overlapping slices of vault balance.
        uint256 nArts = arts.length;
        for (uint256 i; i < nArts;) {
            if (amounts[i] == 0) revert ZeroAmount();
            if (amounts[i] % ART_UNIT != 0) revert NonIntegerArtAmount();
            if (arts[i] == rewardToken) revert RewardCollidesWithArt();
            if (!FACTORY.isValidToken(arts[i])) revert NotShitVerseArt();
            for (uint256 j; j < i;) {
                if (arts[j] == arts[i]) revert DuplicateArt();
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }

        id = _collections.length;
        _collections.push();
        Collection storage c = _collections[id];
        c.creator        = msg.sender;
        c.rewardToken    = rewardToken;
        c.rewardAmount   = rewardAmount;
        c.maxRedemptions = maxRedemptions;
        uint64 dl;
        unchecked {
            dl = openDuration == 0 ? 0 : uint64(block.timestamp) + openDuration;
        }
        c.deadline       = dl;
        c.createdAt      = uint64(block.timestamp);
        c.artDest      = artDest;
        c.lockDuration   = lockDuration;
        c.arts    = arts;
        c.amounts = amounts;

        uint256 totalReward = rewardAmount * maxRedemptions;
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), totalReward);

        emit CollectionCreated(
            id, msg.sender, rewardToken,
            rewardAmount, maxRedemptions, dl,
            artDest, lockDuration
        );
    }

    /// @notice Surrender required arts; receive the reward.
    ///   Caller must have ERC-20 approved this contract on each art.
    function redeem(uint256 id) external nonReentrant {
        if (id >= _collections.length) revert InvalidId();
        Collection storage c = _collections[id];
        if (c.redeemedCount >= c.maxRedemptions) revert Exhausted();
        if (c.deadline != 0 && block.timestamp >= c.deadline) revert Expired();

        // CEI: bump before externals.
        unchecked { c.redeemedCount++; }

        address dest;
        if (c.artDest == ArtDest.CREATOR_IMMEDIATE) {
            dest = c.creator;
        } else {
            // LOCKED: arts → vault, redeemer reclaims via claimLockedArts.
            // Per-user count bounded by maxRedemptions → uint64 safe.
            dest = address(this);
            unchecked { _userRedemptions[id][msg.sender]++; }
        }

        // Cross-contract invariant: DualToken's ERC-20 `transferFrom` MUST
        // stay balance-equivalent to ERC-1155 `safeTransferFrom(_,_,0,_)`.
        uint256 n = c.arts.length;
        for (uint256 i; i < n;) {
            IERC20(c.arts[i]).safeTransferFrom(msg.sender, dest, c.amounts[i]);
            unchecked { ++i; }
        }

        IERC20(c.rewardToken).safeTransfer(msg.sender, c.rewardAmount);
        emit Redeemed(id, msg.sender);
    }

    /// @notice Creator pulls back unredeemed reward after `deadline`.
    ///   `deadline == 0` blocks reclaim entirely — see TRUST MODEL (1).
    function reclaim(uint256 id) external nonReentrant {
        if (id >= _collections.length) revert InvalidId();
        Collection storage c = _collections[id];
        if (msg.sender != c.creator) revert NotCreator();
        if (c.deadline == 0) revert NoDeadline();
        if (block.timestamp < c.deadline) revert DeadlineNotReached();
        if (c.reclaimed) revert AlreadyReclaimed();

        uint256 unused;
        unchecked { unused = c.maxRedemptions - c.redeemedCount; }
        if (unused == 0) revert NothingToReclaim();

        c.reclaimed = true;
        uint256 amount = unused * c.rewardAmount;
        IERC20(c.rewardToken).safeTransfer(c.creator, amount);
        emit Reclaimed(id, amount);
    }

    /// @notice Caller pulls back arts they surrendered in LOCKED mode,
    ///   after the lock window. Each redemption is recorded per-user;
    ///   this zeroes the caller's count.
    /// @dev Payout is `myRedemptions × amounts[i]`, NOT `balanceOf(this)` —
    ///   vault pools balances across collections sharing an art.
    function claimLockedArts(uint256 id) external nonReentrant {
        if (id >= _collections.length) revert InvalidId();
        Collection storage c = _collections[id];
        if (c.artDest != ArtDest.LOCKED) revert WrongMode();
        // unchecked: see MAX_DURATION invariant.
        unchecked {
            if (block.timestamp < uint256(c.createdAt) + uint256(c.lockDuration)) revert StillLocked();
        }

        uint64 mine = _userRedemptions[id][msg.sender];
        if (mine == 0) revert NothingToClaim();

        // CEI: zero the per-user count before externals.
        _userRedemptions[id][msg.sender] = 0;

        uint256 n = c.arts.length;
        for (uint256 i; i < n;) {
            uint256 owed = uint256(mine) * c.amounts[i];
            IERC20(c.arts[i]).safeTransfer(msg.sender, owed);
            unchecked { ++i; }
        }
        emit LockedArtsClaimed(id, msg.sender, mine);
    }

    /// @notice Trusted-role withdrawal of any non-art ERC-20, including
    ///   active-collection reward tokens. See TRUST MODEL (2).
    function ownerWithdraw(address token, uint256 amount, address to)
        external onlyOwner nonReentrant
    {
        if (to == address(0)) revert ZeroRecipient();
        if (FACTORY.isValidToken(token)) revert ArtNotWithdrawable();
        IERC20(token).safeTransfer(to, amount);
        emit OwnerWithdrew(token, to, amount);
    }

    /// @notice Single-step; renouncing blocked (would trap ownerWithdraw-able funds).
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroOwner();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function totalCollections() external view returns (uint256) {
        return _collections.length;
    }

    function getCollection(uint256 id) external view returns (Collection memory) {
        if (id >= _collections.length) revert InvalidId();
        return _collections[id];
    }

    function getCollectionArts(uint256 id)
        external view returns (address[] memory arts, uint256[] memory amounts)
    {
        if (id >= _collections.length) revert InvalidId();
        Collection storage c = _collections[id];
        return (c.arts, c.amounts);
    }

    /// @notice Reverts for non-LOCKED collections.
    function lockedArtsUnlockAt(uint256 id) external view returns (uint64) {
        if (id >= _collections.length) revert InvalidId();
        Collection storage c = _collections[id];
        if (c.artDest != ArtDest.LOCKED) revert WrongMode();
        // unchecked: see MAX_DURATION invariant.
        unchecked { return c.createdAt + c.lockDuration; }
    }

    /// @notice User's outstanding LOCKED redemptions on collection `id`.
    ///   Nonzero = arts claimable once the lock window elapses.
    function userRedemptions(uint256 id, address user) external view returns (uint64) {
        if (id >= _collections.length) revert InvalidId();
        return _userRedemptions[id][user];
    }

    /// @notice True ONLY when `redeem(id)` from `user` would succeed now.
    /// @dev Includes vault solvency check — `ownerWithdraw`, fee-on-transfer,
    ///   or rebasing can leave the vault unable to pay `rewardAmount`.
    function canRedeem(uint256 id, address user) external view returns (bool) {
        if (id >= _collections.length) return false;
        Collection storage c = _collections[id];
        if (c.redeemedCount >= c.maxRedemptions) return false;
        if (c.deadline != 0 && block.timestamp >= c.deadline) return false;
        if (IERC20(c.rewardToken).balanceOf(address(this)) < c.rewardAmount) return false;
        uint256 n = c.arts.length;
        for (uint256 i; i < n;) {
            uint256 needed = c.amounts[i];
            if (IERC20(c.arts[i]).balanceOf(user) < needed) return false;
            if (IERC20(c.arts[i]).allowance(user, address(this)) < needed) return false;
            unchecked { ++i; }
        }
        return true;
    }
}
