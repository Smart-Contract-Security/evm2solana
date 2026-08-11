// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAzimuth} from "../src/Interfaces/IAzimuth.sol";
import {IPlanetDispenser} from "../src/Interfaces/IPlanetDispenser.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SlugLib} from "../src/libraries/SlugLib.sol";

/**
 * @title SpacePort
 * @notice Registry for Spaces, each of which carries one or more Baskets
 *         — independent invite windows with their own inviter address, activation date, and
 *         invite-token escrow. Multiple baskets may be live at once; a basket can keep
 *         onboarding new members until it's explicitly closed or exhausts its remaining
 *         invites.
 *
 */
contract SpacePort is ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///////////////
    //  Errors   //
    ///////////////

    error UnauthorizedOwnerOrProxy();
    error DeployerMustControlOwnershipPoint();
    error CallerNotOwnerOfUrbitId();
    error UrbitIdNotActive();
    error CallerNotAuthorized();
    error PointNotOwnedByCaller();
    error PointNotControlledByCaller();
    error UnauthorizedAccess();
    error NoInvitesRemaining();
    error BadRecipient();
    error InsufficientUrbit();
    error UrbitIdAlreadyBanned(uint32 urbitId);
    error RecipientNotOwner();
    error InvalidSigner();
    error NotAMember(uint32 urbitId);
    error AlreadyMember(uint32 urbitId);
    error InvalidCount();
    error InsufficientInvites();
    error InsufficientUrbitBalance();
    error SpaceAlreadyExists();
    error SpaceDoesNotExist();
    error SpaceDestroyed();
    error EthTransferFailed();
    error DirectEthNotAccepted();
    error FunctionDoesNotExist();
    error BasketNotYetActive();
    error BasketDoesNotExist();
    error InviterAlreadyInUse();
    error InviterRequired();
    error SubsidizedInvitesExceedsMax();
    error SponsorFundingInsufficient();
    error CreationNotWhitelisted();
    error NotBanned(uint32 urbitId);
    error MigrationDisabled();
    error InvalidMigrationLogic();

    ///////////////////////
    // Storage Variables //
    ///////////////////////

    IAzimuth private immutable i_azimuth;
    address  private immutable i_urbitToken;
    address  private immutable i_migrationLogic;

    uint256 private constant INVITE_PRICE = 1e18; // 1 $URBIT per invite

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

    //////////////////////////////
    // Per-space state & ledgers//
    //////////////////////////////

    struct MetadataEntry {
        string key;
        string value;
    }

    struct MemberInfo {
        uint32 basketIndex; // basket the member joined under
        uint32 joinIndex;   // order in which the member joined (zero-indexed across the space)
    }

    struct Basket {
        address inviter;          // EOA authorized to onboard for this basket
        uint256 activationDate;   // Unix timestamp this basket opens (0 = immediate)
        uint32  remainingInvites; // Unused invites in this basket
        uint32  totalInvitesIssued; // Lifetime count ever deposited into this basket
        uint256 escrowUrbit;      // $URBIT escrowed for this basket
        bool    exists;
    }

    struct Space {
        uint32  ownerId;
        bool    isDestroyed;
        string  spaceId;
        bool    exists;
        string  metadataUri;
        string  about;
        uint32  nextBasketIndex; // monotonic; equals the index addBasket will use next
        uint32  memberIndex;     // next joinIndex to assign; equals total members ever onboarded
    }

    // key: keccak256(abi.encode(leaderUrbitId, spaceId))
    mapping(bytes32 => Space) private _spaces;

    // (spaceKey, basketIndex) → Basket
    mapping(bytes32 => mapping(uint32 => Basket)) private _baskets;

    // per-space membership flags
    mapping(bytes32 => mapping(uint32 => bool)) private _isMember;
    mapping(bytes32 => mapping(uint32 => bool)) private _isBanned;
    mapping(bytes32 => mapping(uint32 => bool)) private _hasQuit;

    // per-member (basketIndex, joinIndex) stamp, assigned at onboard time
    mapping(bytes32 => mapping(uint32 => MemberInfo)) private _memberInfo;

    // anti-replay nonce, scoped per (spaceKey, urbitId)
    mapping(bytes32 => mapping(uint32 => uint256)) private _onboardNonce;

    // per-space on-chain key/value metadata
    mapping(bytes32 => MetadataEntry[]) private _spaceMetadata;

    //////////////////////
    // EIP-191 typehash //
    //////////////////////

    /// @dev keccak256("Onboard(bytes32 spaceKey,uint32 basketIndex,uint32 spaceOwnerId,uint32 urbitId,address recipient,uint256 nonce,address verifyingContract,uint256 chainId)")
    bytes32 private constant ONBOARD_TYPEHASH =
        keccak256("Onboard(bytes32 spaceKey,uint32 basketIndex,uint32 spaceOwnerId,uint32 urbitId,address recipient,uint256 nonce,address verifyingContract,uint256 chainId)");

    //////////////
    //  Events  //
    //////////////

    // Lifecycle of per-space records
    event SpaceOpened(uint32 indexed leaderUrbitId, bytes32 indexed spaceKey, string spaceId);
    event SpaceClosed(bytes32 indexed spaceKey, uint32 indexed leaderUrbitId);

    // Ownership transfer
    event OwnerProposed(uint32 indexed currentOwnerId, uint32 indexed proposedOwnerId);
    event OwnershipProposalRevoked(uint32 indexed currentOwnerId);
    event OwnershipAccepted(uint32 indexed newOwnerId);
    event OwnershipRejected(uint32 indexed proposedOwnerId);

    // External integrations
    event PlanetMarketUpdated(address indexed newMarket);
    event ManagementProxyUpdated(address indexed newProxy);
    event DuesContractUpdated(address indexed newContract);

    // Basket lifecycle
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
    event BasketActivationDateUpdated(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        uint256 activationDate
    );
    // Invite escrow / accounting (per basket)
    event InvitesAdded(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        address indexed depositor,
        uint32 count,
        uint256 amount
    );
    event InvitesRemoved(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        address indexed withdrawer,
        uint32 count,
        uint256 amount
    );
    event UrbitTokensRetrieved(
        bytes32 indexed spaceKey,
        uint32 indexed basketIndex,
        address indexed to,
        uint256 amount
    );

    // Membership lifecycle
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
    event UrbitIdUnbanned(bytes32 indexed spaceKey, uint32 indexed unbannedUrbitId);
    event UrbitIdQuit(bytes32 indexed spaceKey, uint32 indexed quittingUrbitId);

    // Admin toggles
    event SubsidizedInvitesUpdated(bool enabled, uint32 maxPerCall);
    event CreationWhitelistUpdated(bool enabled);
    event CreationWhitelistSet(uint32[] urbitIds, bool allowed);

    // Space metadata
    event MetadataUriUpdated(bytes32 indexed spaceKey, string metadataUri);
    event MetadataEntrySet(bytes32 indexed spaceKey, string key, string value);
    event MetadataEntryRemoved(bytes32 indexed spaceKey, string key);
    event AboutUpdated(bytes32 indexed spaceKey, string about);

    // Migration
    event MigrationLogicPinned(address indexed migrationLogic);
    event MigrationFinalized();

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyHubOwner() {
        if (!i_azimuth.isOwner(_ownerId, msg.sender) &&
            !i_azimuth.isManagementProxy(_ownerId, msg.sender)) {
            revert UnauthorizedOwnerOrProxy();
        }
        _;
    }

    modifier onlyExisting(bytes32 spaceKey) {
        if (!_spaces[spaceKey].exists) revert SpaceDoesNotExist();
        if (_spaces[spaceKey].isDestroyed) revert SpaceDestroyed();
        _;
    }

    modifier onlyOwnerID(bytes32 spaceKey) {
        uint32 sid = _spaces[spaceKey].ownerId;
        if (!i_azimuth.isOwner(sid, msg.sender)) revert PointNotOwnedByCaller();
        _;
    }

    modifier onlyController(bytes32 spaceKey) {
        uint32 sid = _spaces[spaceKey].ownerId;
        if (!i_azimuth.isOwner(sid, msg.sender) &&
            !i_azimuth.isManagementProxy(sid, msg.sender)) revert PointNotControlledByCaller();
        _;
    }

    /// @dev Authorizes msg.sender as the basket's inviter, the space owner, or its management proxy.
    modifier permissionedBasketAccess(bytes32 spaceKey, uint32 basketIndex) {
        Basket storage c = _baskets[spaceKey][basketIndex];
        if (!c.exists) revert BasketDoesNotExist();
        Space storage s = _spaces[spaceKey];
        if (msg.sender != c.inviter &&
            !i_azimuth.isOwner(s.ownerId, msg.sender) &&
            !i_azimuth.isManagementProxy(s.ownerId, msg.sender)) {
            revert UnauthorizedAccess();
        }
        _;
    }

    /////////////////
    // Constructor //
    /////////////////

    constructor(
        address azimuthAddress,
        uint32 ownerId,
        address urbitToken,
        address planetMarket,
        address migrationLogic
    ) {
        i_azimuth = IAzimuth(azimuthAddress);
        i_urbitToken = urbitToken;
        i_migrationLogic = migrationLogic;
        _ownerId = ownerId;
        _proposedOwnerId = ownerId;
        _planetMarket = planetMarket;
        if (planetMarket != address(0)) {
            IERC20(i_urbitToken).forceApprove(planetMarket, type(uint256).max);
        }
        if (!i_azimuth.isOwner(ownerId, msg.sender)) {
            revert DeployerMustControlOwnershipPoint();
        }
        if (migrationLogic != address(0)) {
            if (migrationLogic.code.length == 0) revert InvalidMigrationLogic();
            emit MigrationLogicPinned(migrationLogic);
        }
    }

    /////////////////////////////
    //// Space CRUD (public) ////
    /////////////////////////////

    /// @notice Create a new space owned by `leaderUrbitId`. Optionally seeds an initial basket 0
    ///         if `inviter` is non-zero.
    /// @dev Caller must currently own `leaderUrbitId` on Azimuth and the point must be active.
    ///      If the creation whitelist is enabled, `leaderUrbitId` must be on it. `spaceId`
    ///      uniqueness is enforced per-owner via `keccak256(leaderUrbitId, spaceId)`.
    ///      If `inviter != address(0)`, a basket 0 is seeded with `activationDate` and
    ///      `inviteCount` invites. If `inviter == address(0)`, no basket is opened — the space
    ///      starts non-inviteable and `addBasket` is required to begin onboarding.
    /// @param leaderUrbitId The urbit ID that will own the new space.
    /// @param inviter Address authorized to onboard for basket 0. Pass `address(0)` to skip
    ///                creating an initial basket.
    /// @param spaceId The slug. Must be in the valid slug format.
    /// @param activationDate Unix timestamp at which basket 0 opens. Ignored if `inviter` is zero.
    /// @param inviteCount Invites to seed into basket 0. Ignored if `inviter` is zero.
    /// @param about Free-form description.
    /// @return spaceKey Deterministic key: `keccak256(abi.encode(leaderUrbitId, spaceId))`.
    function createSpace(
        uint32 leaderUrbitId,
        address inviter,
        string memory spaceId,
        uint256 activationDate,
        uint32 inviteCount,
        string memory about
    ) external nonReentrant returns (bytes32 spaceKey) {
        if (!i_azimuth.isOwner(leaderUrbitId, msg.sender)) revert CallerNotOwnerOfUrbitId();
        if (!i_azimuth.isActive(leaderUrbitId)) revert UrbitIdNotActive();
        if (_creationWhitelistEnabled && !_creationWhitelist[leaderUrbitId]) revert CreationNotWhitelisted();

        SlugLib.assertValidSlug(spaceId);

        spaceKey = keccak256(abi.encode(leaderUrbitId, spaceId));
        if (_spaces[spaceKey].exists) revert SpaceAlreadyExists();

        Space storage s = _spaces[spaceKey];
        s.ownerId = leaderUrbitId;
        s.spaceId = spaceId;
        s.exists = true;
        s.about = about;

        emit SpaceOpened(leaderUrbitId, spaceKey, spaceId);
        if (bytes(about).length > 0) {
            emit AboutUpdated(spaceKey, about);
        }

        if (inviter != address(0)) {
            _openBasket(spaceKey, inviter, activationDate, inviteCount);
        }
    }

    /// @notice Destroy a space, closing all baskets and returning escrowed `$URBIT` to the hub owner.
    /// @dev Callable only by the current Azimuth owner of the space's urbit ID (not its management
    ///      proxy). Destruction is irreversible — `isDestroyed` is permanent and blocks all future
    ///      `onlyExisting` operations. Members already in the space keep their records but no new
    ///      members can be added.
    /// @param spaceKey The space to destroy.
    /// @return True on success.
    function destroySpace(bytes32 spaceKey)
        external
        nonReentrant
        onlyExisting(spaceKey)
        onlyOwnerID(spaceKey)
        returns (bool)
    {
        Space storage s = _spaces[spaceKey];
        address host = i_azimuth.getOwner(s.ownerId);

        uint32 endIdx = s.nextBasketIndex;
        for (uint32 i = 0; i < endIdx; i++) {
            Basket storage c = _baskets[spaceKey][i];
            if (!c.exists) continue;
            uint256 escrow = c.escrowUrbit;
            if (escrow > 0) {
                c.escrowUrbit = 0;
                c.remainingInvites = 0;
                IERC20(i_urbitToken).safeTransfer(host, escrow);
                emit UrbitTokensRetrieved(spaceKey, i, host, escrow);
            }
        }

        s.isDestroyed = true;
        emit SpaceClosed(spaceKey, s.ownerId);
        return true;
    }

    ///////////////////////////
    //// Basket lifecycle  ////
    ///////////////////////////

    /// @notice Open a new basket on an existing space. The new basket gets its own inviter,
    ///         activation date, and invite count, independent of any prior baskets.
    /// @dev Callable by the space owner or its management proxy. Old baskets continue
    ///      functioning until their invites are exhausted (e.g., drained via removeInvites).
    /// @param spaceKey The space.
    /// @param inviter Address authorized to onboard for this basket. Must be non-zero and not
    ///                already an inviter for another live basket of this space.
    /// @param activationDate Unix timestamp this basket opens. `0` = immediate.
    /// @param inviteCount Invites to seed into this basket.
    /// @return basketIndex The index assigned to the new basket.
    function addBasket(
        bytes32 spaceKey,
        address inviter,
        uint256 activationDate,
        uint32 inviteCount
    )
        external
        nonReentrant
        onlyExisting(spaceKey)
        onlyController(spaceKey)
        returns (uint32 basketIndex)
    {
        if (inviter == address(0)) revert InviterRequired();
        basketIndex = _openBasket(spaceKey, inviter, activationDate, inviteCount);
    }

    /// @notice Rotate the inviter address on a specific basket without opening a new basket.
    ///         Useful when a basket's inviter wallet is compromised — swap in a fresh inviter
    ///         while leaving activation date and remaining invites intact. Passing `address(0)`
    ///         pauses external onboarding on this basket (owner/proxy can still onboard via
    ///         their Azimuth authority); the basket can be unpaused later by setting a non-zero
    ///         inviter again.
    /// @dev Callable by the space owner or its management proxy. A non-zero new inviter must not
    ///      already be in use by another live basket of this space (but may be in use elsewhere).
    /// @param spaceKey The space.
    /// @param basketIndex The basket to mutate.
    /// @param newInviter New inviter address, or `address(0)` to pause external onboarding.
    function setSpaceInviter(
        bytes32 spaceKey,
        uint32 basketIndex,
        address newInviter
    )
        external
        onlyExisting(spaceKey)
        onlyController(spaceKey)
    {
        Basket storage c = _baskets[spaceKey][basketIndex];
        if (!c.exists) revert BasketDoesNotExist();
        if (newInviter != address(0)) {
            _assertInviterUnusedInSpace(spaceKey, newInviter);
        }

        address oldInviter = c.inviter;
        c.inviter = newInviter;
        emit BasketInviterChanged(spaceKey, basketIndex, oldInviter, newInviter);
    }

    /// @notice Set the activation date on a specific basket.
    /// @dev Callable by the space owner or its management proxy. Only affects onboarding for this
    ///      basket; existing members are unaffected. `0` = active immediately.
    function setBasketActivationDate(
        bytes32 spaceKey,
        uint32 basketIndex,
        uint256 activationDate
    )
        external
        onlyExisting(spaceKey)
        onlyController(spaceKey)
    {
        Basket storage c = _baskets[spaceKey][basketIndex];
        if (!c.exists) revert BasketDoesNotExist();
        c.activationDate = activationDate;
        emit BasketActivationDateUpdated(spaceKey, basketIndex, activationDate);
    }

    ///////////////////////////////
    //// Invite Escrow & Flows ////
    ///////////////////////////////

    /// @notice Top up invites on a specific basket, escrowing `count * INVITE_PRICE` of `$URBIT`.
    /// @dev Callable by the basket's inviter, the space owner, or the owner's management proxy.
    ///      Subject to the subsidy toggle: when `_subsidizedInvites` is on, the hub owner funds
    ///      the top-up (capped by `_maxSubsidizedInvites` per call); otherwise the caller funds.
    ///      The funder must have pre-approved the hub to spend the required `$URBIT`.
    /// @param spaceKey The space.
    /// @param basketIndex The basket to add invites to.
    /// @param count Number of invites to add. Must be > 0.
    /// @return True on success.
    function addInvites(bytes32 spaceKey, uint32 basketIndex, uint32 count)
        external
        nonReentrant
        onlyExisting(spaceKey)
        permissionedBasketAccess(spaceKey, basketIndex)
        returns (bool)
    {
        if (count == 0) revert InvalidCount();
        Basket storage c = _baskets[spaceKey][basketIndex];

        (address funder, uint256 amount) = _resolveInviteFunding(count);
        IERC20(i_urbitToken).safeTransferFrom(funder, address(this), amount);

        c.remainingInvites += count;
        c.totalInvitesIssued += count;
        c.escrowUrbit += amount;

        emit InvitesAdded(spaceKey, basketIndex, funder, count, amount);
        return true;
    }

    /// @notice Remove unused invites from a basket and return the escrowed `$URBIT` to the host
    ///         (current Azimuth owner of the space's urbit ID).
    /// @dev Callable by the basket's inviter, the space owner, or the owner's management proxy.
    ///      Tokens are returned to the host, not the caller — so a temporary management proxy
    ///      can't siphon escrow during a window where they control the urbit ID.
    /// @param spaceKey The space.
    /// @param basketIndex The basket to remove invites from.
    /// @param count Number of invites to remove.
    /// @return True on success.
    function removeInvites(bytes32 spaceKey, uint32 basketIndex, uint32 count)
        external
        nonReentrant
        onlyExisting(spaceKey)
        permissionedBasketAccess(spaceKey, basketIndex)
        returns (bool)
    {
        if (count == 0) revert InvalidCount();

        Basket storage c = _baskets[spaceKey][basketIndex];
        if (c.remainingInvites < count) revert InsufficientInvites();

        uint256 amount = INVITE_PRICE * uint256(count);
        if (c.escrowUrbit < amount) revert InsufficientUrbitBalance();

        c.remainingInvites -= count;
        c.escrowUrbit -= amount;

        address host = i_azimuth.getOwner(_spaces[spaceKey].ownerId);
        IERC20(i_urbitToken).safeTransfer(host, amount);

        emit InvitesRemoved(spaceKey, basketIndex, host, count, amount);
        return true;
    }

    /////////////////////////////////////
    //// Membership: onboarding/quit ////
    /////////////////////////////////////

    /// @notice Onboard a brand-new Urbit ID via the planet dispenser. Spends one invite from the
    ///         given basket and stamps the new member with that basket's index.
    /// @dev Callable by the basket inviter, the space owner, or the owner's management proxy.
    ///      Caller proposes `newUrbitId`; the dispenser validates it. Any `msg.value` is forwarded
    ///      to `recipient` as an ETH stipend.
    /// @param spaceKey The space to join.
    /// @param basketIndex The basket whose invites to spend.
    /// @param recipient Address that will own the newly minted Urbit ID.
    /// @param newUrbitId The urbit ID to mint and onboard.
    /// @return True on success.
    function onboardNewUrbitID(
        bytes32 spaceKey,
        uint32 basketIndex,
        address recipient,
        uint32 newUrbitId
    )
        external
        payable
        nonReentrant
        onlyExisting(spaceKey)
        permissionedBasketAccess(spaceKey, basketIndex)
        returns (bool)
    {
        Basket storage c = _baskets[spaceKey][basketIndex];
        if (c.activationDate > 0 && block.timestamp < c.activationDate) revert BasketNotYetActive();
        if (c.remainingInvites == 0) revert NoInvitesRemaining();
        if (_isMember[spaceKey][newUrbitId]) revert AlreadyMember(newUrbitId);
        if (_isBanned[spaceKey][newUrbitId]) revert UrbitIdAlreadyBanned(newUrbitId);
        if (recipient == address(0)) revert BadRecipient();
        if (c.escrowUrbit < INVITE_PRICE) revert InsufficientUrbit();

        IPlanetDispenser(_planetMarket).redeemPlanet(newUrbitId, recipient, _managementProxy);

        Space storage s = _spaces[spaceKey];

        unchecked { c.remainingInvites -= 1; }
        c.escrowUrbit -= INVITE_PRICE;
        _isMember[spaceKey][newUrbitId] = true;

        uint32 joinIndex = s.memberIndex;
        s.memberIndex = joinIndex + 1;
        _memberInfo[spaceKey][newUrbitId] = MemberInfo({basketIndex: basketIndex, joinIndex: joinIndex});

        if (msg.value > 0) {
            (bool ok, ) = payable(recipient).call{value: msg.value}("");
            if (!ok) revert EthTransferFailed();
        }

        emit InviteClaimed(spaceKey, s.ownerId, newUrbitId, recipient, msg.value, basketIndex, joinIndex);
        return true;
    }

    /// @notice Onboard an existing Urbit ID. Spends one invite from the given basket, transfers
    ///         `INVITE_PRICE` of `$URBIT` to `recipient`, and stamps the new member.
    /// @dev Callable by the basket inviter, the space owner, or the owner's management proxy.
    ///      The existing urbit ID's owner (or management proxy) must co-sign a personal_sign
    ///      message binding the call payload. Any `msg.value` is forwarded as an ETH stipend.
    function onboardExistingUrbitID(
        bytes32 spaceKey,
        uint32 basketIndex,
        address recipient,
        uint32 existingUrbitId,
        bytes memory signature
    )
        external
        payable
        nonReentrant
        onlyExisting(spaceKey)
        permissionedBasketAccess(spaceKey, basketIndex)
        returns (bool)
    {
        Basket storage c = _baskets[spaceKey][basketIndex];
        Space storage s = _spaces[spaceKey];

        if (c.activationDate > 0 && block.timestamp < c.activationDate) revert BasketNotYetActive();
        if (c.remainingInvites == 0) revert NoInvitesRemaining();
        if (c.escrowUrbit < INVITE_PRICE) revert InsufficientUrbit();
        if (_isMember[spaceKey][existingUrbitId]) revert AlreadyMember(existingUrbitId);
        if (_isBanned[spaceKey][existingUrbitId]) revert UrbitIdAlreadyBanned(existingUrbitId);
        if (recipient != i_azimuth.getOwner(existingUrbitId)) revert RecipientNotOwner();

        bytes32 structHash = keccak256(
            abi.encode(
                ONBOARD_TYPEHASH,
                spaceKey,
                basketIndex,
                s.ownerId,
                existingUrbitId,
                recipient,
                _onboardNonce[spaceKey][existingUrbitId],
                address(this),
                block.chainid
            )
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(structHash);

        address signer = ECDSA.recover(digest, signature);
        bool ok = (signer == i_azimuth.getOwner(existingUrbitId)) ||
                  (i_azimuth.isManagementProxy(existingUrbitId, signer));
        if (!ok) revert InvalidSigner();

        unchecked { _onboardNonce[spaceKey][existingUrbitId]++; }
        unchecked { c.remainingInvites -= 1; }
        c.escrowUrbit -= INVITE_PRICE;

        _isMember[spaceKey][existingUrbitId] = true;
        uint32 joinIndex = s.memberIndex;
        s.memberIndex = joinIndex + 1;
        _memberInfo[spaceKey][existingUrbitId] = MemberInfo({basketIndex: basketIndex, joinIndex: joinIndex});

        IERC20(i_urbitToken).safeTransfer(recipient, INVITE_PRICE);

        if (msg.value > 0) {
            (bool ok2, ) = payable(recipient).call{value: msg.value}("");
            if (!ok2) revert EthTransferFailed();
        }

        emit InviteClaimed(spaceKey, s.ownerId, existingUrbitId, recipient, msg.value, basketIndex, joinIndex);
        return true;
    }

    /// @notice Leave a space as a member, signed and submitted by the member themselves.
    function rageQuitSpace(bytes32 spaceKey, uint32 rageQuitUrbitId)
        external
        nonReentrant
        onlyExisting(spaceKey)
        returns (bool)
    {
        if (!_isMember[spaceKey][rageQuitUrbitId]) revert NotAMember(rageQuitUrbitId);

        bool controls =
            i_azimuth.isOwner(rageQuitUrbitId, msg.sender) ||
            i_azimuth.isManagementProxy(rageQuitUrbitId, msg.sender);
        if (!controls) revert CallerNotAuthorized();

        _hasQuit[spaceKey][rageQuitUrbitId] = true;
        _isMember[spaceKey][rageQuitUrbitId] = false;

        emit UrbitIdQuit(spaceKey, rageQuitUrbitId);
        return true;
    }

    /////////////////////////
    //// Per-space Admin ////
    /////////////////////////

    /// @notice Ban or unban an urbit ID from a space. Banning a current member removes them;
    ///         unbanning a previously-banned ID does NOT re-add membership — they'd have to
    ///         be onboarded again.
    /// @dev Callable by the space owner or its management proxy.
    /// @param spaceKey The space.
    /// @param urbitId The urbit ID.
    /// @param banned True to ban (must currently be a member), false to unban (must currently be banned).
    function setBan(bytes32 spaceKey, uint32 urbitId, bool banned)
        external
        onlyExisting(spaceKey)
        onlyController(spaceKey)
    {
        if (banned) {
            if (!_isMember[spaceKey][urbitId]) revert NotAMember(urbitId);
            if (_isBanned[spaceKey][urbitId]) revert UrbitIdAlreadyBanned(urbitId);
            _isBanned[spaceKey][urbitId] = true;
            _isMember[spaceKey][urbitId] = false;
            emit UrbitIdBanned(spaceKey, urbitId);
        } else {
            if (!_isBanned[spaceKey][urbitId]) revert NotBanned(urbitId);
            _isBanned[spaceKey][urbitId] = false;
            emit UrbitIdUnbanned(spaceKey, urbitId);
        }
    }

    function setMetadataUri(bytes32 spaceKey, string calldata metadataUri)
        external
        onlyExisting(spaceKey)
        onlyController(spaceKey)
        returns (bool)
    {
        _spaces[spaceKey].metadataUri = metadataUri;
        emit MetadataUriUpdated(spaceKey, metadataUri);
        return true;
    }

    function setAbout(bytes32 spaceKey, string calldata about)
        external
        onlyExisting(spaceKey)
        onlyController(spaceKey)
    {
        _spaces[spaceKey].about = about;
        emit AboutUpdated(spaceKey, about);
    }

    ///////////////////////////////
    //// On-chain Metadata CRUD ///
    ///////////////////////////////

    function setMetadataEntries(
        bytes32 spaceKey,
        MetadataEntry[] calldata entries
    ) external onlyExisting(spaceKey) onlyController(spaceKey) {
        for (uint256 i = 0; i < entries.length; i++) {
            _setMetadataEntryInternal(spaceKey, entries[i].key, entries[i].value);
        }
    }

    function removeMetadataEntry(bytes32 spaceKey, string calldata key)
        external
        onlyExisting(spaceKey)
        onlyController(spaceKey)
    {
        MetadataEntry[] storage entries = _spaceMetadata[spaceKey];

        for (uint256 i = 0; i < entries.length; i++) {
            if (keccak256(bytes(entries[i].key)) == keccak256(bytes(key))) {
                entries[i] = entries[entries.length - 1];
                entries.pop();
                emit MetadataEntryRemoved(spaceKey, key);
                return;
            }
        }
    }

    function _setMetadataEntryInternal(
        bytes32 spaceKey,
        string calldata key,
        string calldata value
    ) internal {
        MetadataEntry[] storage entries = _spaceMetadata[spaceKey];

        for (uint256 i = 0; i < entries.length; i++) {
            if (keccak256(bytes(entries[i].key)) == keccak256(bytes(key))) {
                entries[i].value = value;
                emit MetadataEntrySet(spaceKey, key, value);
                return;
            }
        }

        entries.push(MetadataEntry({key: key, value: value}));
        emit MetadataEntrySet(spaceKey, key, value);
    }

    /////////////////////////
    //// Hub Admin (owner) //
    /////////////////////////

    function proposeOwner(uint32 proposedOwnerId) external onlyHubOwner returns (uint32) {
        _proposedOwnerId = proposedOwnerId;
        emit OwnerProposed({ currentOwnerId: _ownerId, proposedOwnerId: proposedOwnerId });
        return _proposedOwnerId;
    }

    function revokeOwnershipProposal() external onlyHubOwner returns (uint32) {
        _proposedOwnerId = _ownerId;
        emit OwnershipProposalRevoked({ currentOwnerId: _ownerId });
        return _proposedOwnerId;
    }

    function acceptOwnership() external returns (uint32) {
        if (!i_azimuth.isOwner(_proposedOwnerId, msg.sender)) revert CallerNotAuthorized();
        _ownerId = _proposedOwnerId;
        emit OwnershipAccepted({ newOwnerId: _ownerId });
        return _ownerId;
    }

    function rejectOwnership() external returns (uint32) {
        if (!i_azimuth.isOwner(_proposedOwnerId, msg.sender)) revert CallerNotAuthorized();
        emit OwnershipRejected({ proposedOwnerId: _proposedOwnerId });
        _proposedOwnerId = _ownerId;
        return _ownerId;
    }

    function changePlanetMarket(address newMarket) external onlyHubOwner returns (bool) {
        if (_planetMarket != address(0)) {
            IERC20(i_urbitToken).forceApprove(_planetMarket, 0);
        }
        _planetMarket = newMarket;
        if (newMarket != address(0)) {
            IERC20(i_urbitToken).forceApprove(newMarket, type(uint256).max);
        }
        emit PlanetMarketUpdated(newMarket);
        return true;
    }

    function changeManagementProxy(address newProxy) external onlyHubOwner returns (bool) {
        _managementProxy = newProxy;
        emit ManagementProxyUpdated(newProxy);
        return true;
    }

    function changeDuesContract(address newContract) external onlyHubOwner returns (bool) {
        _duesContract = newContract;
        emit DuesContractUpdated(newContract);
        return true;
    }

    /// @notice Toggle subsidized invites. When on, the hub owner funds every basket seed and
    ///         every `addInvites` call (each individual call is capped at `maxPerCall` invites).
    ///         When off, the caller funds their own invites. The cap is intentionally per-call,
    ///         not cumulative: it's a fat-finger guard against accidental zeros, not a hard
    ///         per-space budget. A misbehaving space inviter can be banned/closed if abused.
    function setSubsidizedInvites(bool enabled, uint32 maxPerCall) external onlyHubOwner {
        _subsidizedInvites = enabled;
        _maxSubsidizedInvites = maxPerCall;
        emit SubsidizedInvitesUpdated(enabled, maxPerCall);
    }

    function setCreationWhitelistEnabled(bool enabled) external onlyHubOwner {
        _creationWhitelistEnabled = enabled;
        emit CreationWhitelistUpdated(enabled);
    }

    function setCreationWhitelist(uint32[] calldata urbitIds, bool allowed) external onlyHubOwner {
        for (uint256 i = 0; i < urbitIds.length; i++) {
            _creationWhitelist[urbitIds[i]] = allowed;
        }
        emit CreationWhitelistSet(urbitIds, allowed);
    }

    ///////////////////
    //// Migration ////
    ///////////////////

    function migrate(bytes calldata data) external {
        if (!i_azimuth.isOwner(_ownerId, msg.sender)) revert PointNotOwnedByCaller();
        if (_migrationFinalized || i_migrationLogic == address(0)) revert MigrationDisabled();
        (bool ok, bytes memory ret) = i_migrationLogic.delegatecall(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    function finalizeMigration() external {
        if (!i_azimuth.isOwner(_ownerId, msg.sender)) revert PointNotOwnedByCaller();
        _migrationFinalized = true;
        emit MigrationFinalized();
    }

    //////////////////////////
    //// View / Getters   ////
    //////////////////////////

    function spaceKeyOf(uint32 leaderUrbitId, string memory spaceId) public pure returns (bytes32) {
        return keccak256(abi.encode(leaderUrbitId, spaceId));
    }

    /// @notice Read the core fields of a space in a single call. Basket details are fetched
    ///         separately via `getBasket(spaceKey, basketIndex)`.
    function getSpace(bytes32 spaceKey)
        external
        view
        returns (
            uint32 ownerId,
            bool destroyed,
            string memory spaceId,
            string memory metadataUri,
            string memory about,
            uint32 nextBasketIndex,
            uint32 memberIndex
        )
    {
        Space storage s = _spaces[spaceKey];
        return (
            s.ownerId,
            s.isDestroyed,
            s.spaceId,
            s.metadataUri,
            s.about,
            s.nextBasketIndex,
            s.memberIndex
        );
    }

    /// @notice Read a single basket's state.
    function getBasket(bytes32 spaceKey, uint32 basketIndex)
        external
        view
        returns (
            address inviter,
            uint256 activationDate,
            uint32 remainingInvites,
            uint32 totalInvitesIssued,
            uint256 escrowUrbit,
            bool basketExists
        )
    {
        Basket storage c = _baskets[spaceKey][basketIndex];
        return (
            c.inviter,
            c.activationDate,
            c.remainingInvites,
            c.totalInvitesIssued,
            c.escrowUrbit,
            c.exists
        );
    }

    function getMemberInfo(bytes32 spaceKey, uint32 urbitId)
        external
        view
        returns (uint32 basketIndex, uint32 joinIndex)
    {
        MemberInfo storage info = _memberInfo[spaceKey][urbitId];
        return (info.basketIndex, info.joinIndex);
    }

    function exists(bytes32 spaceKey) external view returns (bool) { return _spaces[spaceKey].exists; }
    function isDestroyed(bytes32 spaceKey) external view returns (bool) { return _spaces[spaceKey].isDestroyed; }
    function isMember(bytes32 spaceKey, uint32 urbitId) external view returns (bool) { return _isMember[spaceKey][urbitId]; }
    function isBanned(bytes32 spaceKey, uint32 urbitId) external view returns (bool) { return _isBanned[spaceKey][urbitId]; }
    function hasQuit(bytes32 spaceKey, uint32 urbitId) external view returns (bool) { return _hasQuit[spaceKey][urbitId]; }

    function onboardNonce(bytes32 spaceKey, uint32 urbitId) external view returns (uint256) {
        return _onboardNonce[spaceKey][urbitId];
    }

    /// @notice True if the space exists, is not destroyed, and `basketIndex` is currently open
    ///         (exists, not closed, and its activationDate has passed).
    function isBasketActive(bytes32 spaceKey, uint32 basketIndex) external view returns (bool) {
        Space storage s = _spaces[spaceKey];
        if (!s.exists || s.isDestroyed) return false;
        Basket storage c = _baskets[spaceKey][basketIndex];
        if (!c.exists) return false;
        if (c.activationDate == 0) return true;
        return block.timestamp >= c.activationDate;
    }

    function getOwnerId() external view returns (uint32) { return _ownerId; }
    function getProposedOwnerId() external view returns (uint32) { return _proposedOwnerId; }
    function getPlanetMarketContract() external view returns (address) { return _planetMarket; }
    function getManagementProxy() external view returns (address) { return _managementProxy; }
    function getDuesContract() external view returns (address) { return _duesContract; }
    function getUrbitToken() external view returns (address) { return i_urbitToken; }
    function getAzimuth() external view returns (address) { return address(i_azimuth); }

    function getSubsidizedInvites() external view returns (bool enabled, uint32 maxPerCall) {
        return (_subsidizedInvites, _maxSubsidizedInvites);
    }

    function isCreationWhitelistEnabled() external view returns (bool) {
        return _creationWhitelistEnabled;
    }

    function isCreationWhitelisted(uint32 urbitId) external view returns (bool) {
        return _creationWhitelist[urbitId];
    }

    function isMigrationFinalized() external view returns (bool) {
        return _migrationFinalized;
    }

function getMetadataEntries(bytes32 spaceKey) external view returns (MetadataEntry[] memory) {
        return _spaceMetadata[spaceKey];
    }

    /// @notice Fetch the value for a single metadata entry by key. Returns empty string if
    ///         the key is unset. Convenience over `getMetadataEntries` when callers only
    ///         need one value (e.g., reading `dues`).
    function getMetadataEntry(bytes32 spaceKey, string calldata key)
        external
        view
        returns (string memory)
    {
        MetadataEntry[] storage entries = _spaceMetadata[spaceKey];
        bytes32 keyHash = keccak256(bytes(key));
        for (uint256 i = 0; i < entries.length; i++) {
            if (keccak256(bytes(entries[i].key)) == keyHash) {
                return entries[i].value;
            }
        }
        return "";
    }

    /////////////////////
    //// Internals   ////
    /////////////////////

    /// @dev Open a basket (used by both createSpace and addBasket). Validates inviter uniqueness
    ///      within the space, pulls $URBIT for the seed amount via subsidy or caller, and writes
    ///      the new basket + bumps nextBasketIndex.
    function _openBasket(
        bytes32 spaceKey,
        address inviter,
        uint256 activationDate,
        uint32 inviteCount
    ) internal returns (uint32 basketIndex) {
        _assertInviterUnusedInSpace(spaceKey, inviter);

        Space storage s = _spaces[spaceKey];
        basketIndex = s.nextBasketIndex;
        s.nextBasketIndex = basketIndex + 1;

        Basket storage c = _baskets[spaceKey][basketIndex];
        c.inviter = inviter;
        c.activationDate = activationDate;
        c.exists = true;

        emit BasketOpened(spaceKey, basketIndex, inviter, activationDate, inviteCount);
        emit BasketInviterChanged(spaceKey, basketIndex, address(0), inviter);

        if (inviteCount > 0) {
            (address funder, uint256 amount) = _resolveInviteFunding(inviteCount);
            IERC20(i_urbitToken).safeTransferFrom(funder, address(this), amount);

            c.remainingInvites = inviteCount;
            c.totalInvitesIssued = inviteCount;
            c.escrowUrbit = amount;

            emit InvitesAdded(spaceKey, basketIndex, funder, inviteCount, amount);
        }
    }

    /// @dev Resolves who pays for a batch of `count` invites and the corresponding `$URBIT`
    ///      amount. When the subsidy toggle is on, the hub owner funds — but each individual
    ///      call is capped at `_maxSubsidizedInvites`. The cap is per-call (fat-finger guard),
    ///      not a cumulative budget. Caller funds otherwise.
    function _resolveInviteFunding(uint32 count) internal view returns (address funder, uint256 amount) {
        amount = INVITE_PRICE * uint256(count);
        if (_subsidizedInvites) {
            if (count > _maxSubsidizedInvites) revert SubsidizedInvitesExceedsMax();
            funder = i_azimuth.getOwner(_ownerId);
        } else {
            funder = msg.sender;
        }
        if (IERC20(i_urbitToken).balanceOf(funder) < amount ||
            IERC20(i_urbitToken).allowance(funder, address(this)) < amount) {
            revert SponsorFundingInsufficient();
        }
    }

    /// @dev Reverts if `inviter` is already registered for some basket in this space.
    function _assertInviterUnusedInSpace(bytes32 spaceKey, address inviter) internal view {
        Space storage s = _spaces[spaceKey];
        uint32 endIdx = s.nextBasketIndex;
        for (uint32 i = 0; i < endIdx; i++) {
            Basket storage c = _baskets[spaceKey][i];
            if (c.exists && c.inviter == inviter) {
                revert InviterAlreadyInUse();
            }
        }
    }

    /////////////////
    //// Receive ////
    /////////////////

    receive() external payable {
        revert DirectEthNotAccepted();
    }

    fallback() external payable {
        revert FunctionDoesNotExist();
    }
}
