// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SpacePortMigrationLogic
 * @notice Delegate-call target for seeding SpacePort state from an external snapshot.
 *
 *         IMPORTANT: this contract is NEVER deployed as a standalone entity with state of its
 *         own. It is only invoked via DELEGATECALL from SpacePort.migrate(...), so all storage
 *         reads and writes in these functions target the PORT's storage, not this contract's.
 *
 *         For delegatecall to hit the correct slots, the storage layout declared here must
 *         exactly mirror SpacePort's layout (same inheritance chain, same variable order, same
 *         types). The port enforces access control at the `migrate()` entry point
 *         (`PointNotOwnedByCaller` + `!_migrationFinalized`), so the seed* functions here do
 *         not re-check caller permissions.
 *
 *         Migration model:
 *         - Each space is seeded with at most one basket (basket 0) carrying its inviter,
 *           activation date, and remaining invite count.
 *         - Members keep their joinIndex but are normalized to basket 0. The space's
 *           memberIndex is advanced past every seeded joinIndex so future onboards don't
 *           collide with historical records.
 *         - `$URBIT` escrow is moved on-chain during `seedSpace`: the hub owner approves the
 *           port for `basketRemainingInvites * INVITE_PRICE` and the migration pulls those
 *           tokens into SpacePort's address. This guarantees the post-migration invariant
 *           `escrowUrbit == remainingInvites * INVITE_PRICE` per basket without any off-chain
 *           coordination of token movement.
 */
contract SpacePortMigrationLogic is ReentrancyGuard {
    using SafeERC20 for IERC20;
    /*
     * ======================================================================
     * Migration-local immutables (do not occupy slots).
     * ======================================================================
     */

    /// @dev Same `$URBIT` token SpacePort uses. Passed at deploy time; the migration logic
    ///      uses this to pull tokens from the hub owner during `seedSpace` and exists purely
    ///      as a delegatecall convenience — SpacePort itself reads `i_urbitToken` from its
    ///      own immutable slot.
    address private immutable i_urbitToken;

    /// @dev Mirror of SpacePort's `INVITE_PRICE`. Constants don't take storage slots.
    uint256 private constant INVITE_PRICE = 1e18;

    constructor(address urbitToken) {
        i_urbitToken = urbitToken;
    }

    /*
     * ======================================================================
     * Storage layout — MUST match SpacePort slot-for-slot.
     * Parent ReentrancyGuard contributes its `_status` at slot 0.
     * Immutables in SpacePort do not occupy slots; not replicated here.
     * (i_azimuth, i_urbitToken, i_migrationLogic are immutables in the port.)
     * ======================================================================
     */

    uint32  private _ownerId;
    uint32  private _proposedOwnerId;
    address private _planetMarket;
    address private _managementProxy;
    address private _duesContract;
    bool    private _subsidizedInvites;
    uint32  private _maxSubsidizedInvites;
    bool    private _creationWhitelistEnabled;
    bool    private _migrationFinalized;
    mapping(uint32 => bool) private _creationWhitelist;

    struct MetadataEntry {
        string key;
        string value;
    }

    struct MemberInfo {
        uint32 basketIndex;
        uint32 joinIndex;
    }

    struct Basket {
        address inviter;
        uint256 activationDate;
        uint32  remainingInvites;
        uint32  totalInvitesIssued;
        uint256 escrowUrbit;
        bool    exists;
    }

    struct Space {
        uint32  ownerId;
        bool    isDestroyed;
        string  spaceId;
        bool    exists;
        string  metadataUri;
        string  about;
        uint32  nextBasketIndex;
        uint32  memberIndex;
    }

    mapping(bytes32 => Space) private _spaces;
    mapping(bytes32 => mapping(uint32 => Basket)) private _baskets;
    mapping(bytes32 => mapping(uint32 => bool)) private _isMember;
    mapping(bytes32 => mapping(uint32 => bool)) private _isBanned;
    mapping(bytes32 => mapping(uint32 => bool)) private _hasQuit;
    mapping(bytes32 => mapping(uint32 => MemberInfo)) private _memberInfo;
    mapping(bytes32 => mapping(uint32 => uint256)) private _onboardNonce;
    mapping(bytes32 => MetadataEntry[]) private _spaceMetadata;

    /*
     * ======================================================================
     * Events — must mirror SpacePort signatures so topic hashes match. When
     * emitted via delegatecall from the port, they appear on the port's address.
     * ======================================================================
     */

    event SpaceOpened(uint32 indexed leaderUrbitId, bytes32 indexed spaceKey, string spaceId);
    event AboutUpdated(bytes32 indexed spaceKey, string about);
    event MetadataUriUpdated(bytes32 indexed spaceKey, string metadataUri);
    event MetadataEntrySet(bytes32 indexed spaceKey, string key, string value);

    event BasketOpened(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        address indexed inviter,
        uint256 activationDate,
        uint32 inviteCount
    );
    event BasketInviterChanged(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        address indexed oldInviter,
        address newInviter
    );
    event InvitesAdded(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        address indexed depositor,
        uint32 count,
        uint256 amount
    );

    event InviteClaimed(
        bytes32 indexed spaceKey,
        uint32 indexed spaceOwnerUrbitId,
        uint32 indexed invitedUrbitId,
        address recipient,
        uint256 stipend,
        uint32 basketIndex,
        uint32 joinIndex
    );
    event UrbitIdBanned(bytes32 indexed spaceKey, uint32 indexed bannedUrbitId);
    event UrbitIdQuit(bytes32 indexed spaceKey, uint32 indexed quittingUrbitId);

    /*
     * ======================================================================
     * Errors
     * ======================================================================
     */

    error SpaceDoesNotExist();
    error AlreadyBanned(uint32 urbitId);
    error SpaceKeyMismatch();

    /*
     * ======================================================================
     * Seed functions — invoked via SpacePort.migrate(abi.encodeCall(...))
     * ======================================================================
     */

    /// @notice Create a space at `spaceKey` with the given top-level fields and, optionally, a
    ///         single seeded basket 0. Bypasses normal ownership and whitelist checks.
    /// @dev The caller is responsible for passing a `spaceKey` that matches
    ///      `keccak256(abi.encode(ownerId, spaceId))`; the port's `spaceKeyOf` does the same.
    ///      A mismatch would make the space unreachable through normal lookups.
    ///
    ///      Idempotent: if the space already exists, returns without writing or transferring
    ///      tokens. This makes partial-rerun migration safe — the orchestrator can retry the
    ///      same sequence of seed calls after a failed run, and previously-seeded state is
    ///      left untouched.
    ///
    ///      When `hasBasket` is true, this writes a basket 0 carrying the inviter, activation
    ///      date, and remaining/total invite counts. The basket's `escrowUrbit` is computed as
    ///      `basketRemainingInvites * INVITE_PRICE` and an equivalent amount of `$URBIT` is
    ///      pulled from `msg.sender` (the hub owner) into the port's address via
    ///      `transferFrom` — the hub owner must approve the port for at least this amount
    ///      ahead of the call. This guarantees the post-migration invariant
    ///      `escrowUrbit == remainingInvites * INVITE_PRICE` and rules out unbacked balances.
    ///
    ///      `nextBasketIndex` is set to 1 if a basket was seeded, else 0.
    /// @param spaceKey Deterministic key (must equal `keccak256(abi.encode(ownerId, spaceId))`).
    /// @param ownerId Urbit ID that owned the space on the source hub.
    /// @param spaceId Slug.
    /// @param metadataUri Off-chain metadata URI.
    /// @param about Free-form description.
    /// @param memberIndex Total InviteClaimed events ever emitted on the source hub for this
    ///                    space — future joinIndex values start from here, avoiding collision
    ///                    with historical records.
    /// @param hasBasket If true, seed basket 0 with the basket* parameters; otherwise leave the
    ///                  space basket-less (must call `addBasket` later to start onboarding).
    /// @param basketInviter Basket 0's inviter address. Ignored when `hasBasket` is false.
    /// @param basketActivationDate Basket 0's activation timestamp. Ignored when `hasBasket` is false.
    /// @param basketRemainingInvites Spendable invites left in basket 0. Drives the `$URBIT`
    ///                               pulled from `msg.sender`. Ignored when `hasBasket` is false.
    /// @param basketTotalInvitesIssued Lifetime invites ever deposited into basket 0 (informational).
    function seedSpace(
        bytes32 spaceKey,
        uint32 ownerId,
        string calldata spaceId,
        string calldata metadataUri,
        string calldata about,
        uint32 memberIndex,
        bool hasBasket,
        address basketInviter,
        uint256 basketActivationDate,
        uint32 basketRemainingInvites,
        uint32 basketTotalInvitesIssued
    ) external {
        if (spaceKey != keccak256(abi.encode(ownerId, spaceId))) revert SpaceKeyMismatch();
        if (_spaces[spaceKey].exists) return; // idempotent: prior seed is authoritative

        Space storage s = _spaces[spaceKey];
        s.ownerId = ownerId;
        s.spaceId = spaceId;
        s.exists = true;
        s.metadataUri = metadataUri;
        s.about = about;
        s.memberIndex = memberIndex;

        emit SpaceOpened(ownerId, spaceKey, spaceId);
        if (bytes(about).length > 0) emit AboutUpdated(spaceKey, about);
        if (bytes(metadataUri).length > 0) emit MetadataUriUpdated(spaceKey, metadataUri);

        if (hasBasket) {
            uint256 escrowAmount = uint256(basketRemainingInvites) * INVITE_PRICE;

            Basket storage c = _baskets[spaceKey][0];
            c.inviter = basketInviter;
            c.activationDate = basketActivationDate;
            c.remainingInvites = basketRemainingInvites;
            c.totalInvitesIssued = basketTotalInvitesIssued;
            c.escrowUrbit = escrowAmount;
            c.exists = true;
            s.nextBasketIndex = 1;

            emit BasketOpened(spaceKey, 0, basketInviter, basketActivationDate, basketRemainingInvites);
            emit BasketInviterChanged(spaceKey, 0, address(0), basketInviter);

            if (escrowAmount > 0) {
                // Pull $URBIT from the hub owner so the declared escrow is always backed.
                // address(this) inside this delegatecall is SpacePort, so tokens land there.
                IERC20(i_urbitToken).safeTransferFrom(msg.sender, address(this), escrowAmount);
                emit InvitesAdded(spaceKey, 0, msg.sender, basketRemainingInvites, escrowAmount);
            }
        }
    }

    /// @notice Insert a historical member with a specific basket and joinIndex stamp.
    /// @dev Reverts if the space doesn't exist or the urbit ID is currently banned.
    ///      Idempotent: if the urbit ID is already a member, returns without modifying state.
    ///      Emits a synthetic `InviteClaimed` event (recipient=0, stipend=0) so client mirrors
    ///      can reconstruct membership from events on the port's address.
    /// @param spaceKey The space to add them to.
    /// @param urbitId The urbit ID joining.
    /// @param basketIndex Basket they should be stamped with. Typically 0 when rotation history
    ///                    is flattened to a single basket.
    /// @param joinIndex The joinIndex assigned to this member on the source hub.
    function seedMember(
        bytes32 spaceKey,
        uint32 urbitId,
        uint32 basketIndex,
        uint32 joinIndex
    ) external {
        Space storage s = _spaces[spaceKey];
        if (!s.exists) revert SpaceDoesNotExist();
        if (_isMember[spaceKey][urbitId]) return; // idempotent
        if (_isBanned[spaceKey][urbitId]) revert AlreadyBanned(urbitId);

        _isMember[spaceKey][urbitId] = true;
        _memberInfo[spaceKey][urbitId] = MemberInfo({basketIndex: basketIndex, joinIndex: joinIndex});

        if (joinIndex >= s.memberIndex) {
            s.memberIndex = joinIndex + 1;
        }

        emit InviteClaimed(spaceKey, s.ownerId, urbitId, address(0), 0, basketIndex, joinIndex);
    }

    /// @notice Mark a historical ban. If the urbit ID is a current member, they're removed.
    /// @dev Idempotent: no-op if the urbit ID is already banned.
    function seedBan(bytes32 spaceKey, uint32 urbitId) external {
        if (!_spaces[spaceKey].exists) revert SpaceDoesNotExist();
        if (_isBanned[spaceKey][urbitId]) return; // idempotent
        _isBanned[spaceKey][urbitId] = true;
        _isMember[spaceKey][urbitId] = false;
        emit UrbitIdBanned(spaceKey, urbitId);
    }

    /// @notice Mark a historical quit. If the urbit ID is a current member, they're removed.
    /// @dev Idempotent: no-op if the urbit ID is already marked quit.
    function seedQuit(bytes32 spaceKey, uint32 urbitId) external {
        if (!_spaces[spaceKey].exists) revert SpaceDoesNotExist();
        if (_hasQuit[spaceKey][urbitId]) return; // idempotent
        _hasQuit[spaceKey][urbitId] = true;
        _isMember[spaceKey][urbitId] = false;
        emit UrbitIdQuit(spaceKey, urbitId);
    }

    /// @notice Set an on-chain metadata entry. Mirrors `SpacePort.setMetadataEntries` upsert
    ///         semantics: if `key` already exists, the value is replaced; otherwise the entry
    ///         is appended.
    /// @dev Idempotent: calling with an unchanged (key, value) does not emit a duplicate event.
    function seedMetadataEntry(
        bytes32 spaceKey,
        string calldata key,
        string calldata value
    ) external {
        if (!_spaces[spaceKey].exists) revert SpaceDoesNotExist();
        MetadataEntry[] storage entries = _spaceMetadata[spaceKey];
        bytes32 keyHash = keccak256(bytes(key));
        for (uint256 i = 0; i < entries.length; i++) {
            if (keccak256(bytes(entries[i].key)) == keyHash) {
                if (keccak256(bytes(entries[i].value)) == keccak256(bytes(value))) {
                    return; // unchanged — no-op
                }
                entries[i].value = value;
                emit MetadataEntrySet(spaceKey, key, value);
                return;
            }
        }
        entries.push(MetadataEntry({key: key, value: value}));
        emit MetadataEntrySet(spaceKey, key, value);
    }
}
