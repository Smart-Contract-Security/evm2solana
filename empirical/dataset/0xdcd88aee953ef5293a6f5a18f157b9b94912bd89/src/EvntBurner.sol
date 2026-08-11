// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EvntBurner — Sprint X v3 Phase A V5 (gas-only optimisations on V4)
/// @notice V5 is a gas-only redeploy of V4. NO protocol semantic change other
///         than a minor shift in the `Accrued.bluechipCount` event field
///         meaning (see delta #2 below). ABI surface (function signatures,
///         event signatures, error selectors, constants) byte-for-byte
///         identical to V4.
///
/// @dev    Three gas optimisations Eugene-locked 2026-05-28 (after V4 mainnet
///         shakedown on `0x4ED2a780542B40121182eDeBef991577D60a10ec`):
///
///         #1 — `burnBatch` redundant `try ownerOf{gas:30k}` precheck dropped
///              (V4 lines 352-361). The subsequent `transferFrom` call in OZ
///              5.x's ERC-721 implementation ALREADY enforces ownership
///              internally: `transferFrom` invokes `_update(to, tokenId,
///              auth=msg.sender)` which calls `_checkAuthorized` (revert
///              `ERC721NonexistentToken` for missing tokens / revert
///              `ERC721InsufficientApproval` when the burner is not approved
///              for the caller's NFT) and then compares the returned
///              `previousOwner` against `from` (revert `ERC721IncorrectOwner`
///              when caller does not own the token). Funds are safe in all
///              paths — every revert is observed BEFORE any state mutation in
///              EvntBurner (`totalBurns` is incremented post-loop).
///
///              Trade-off: the bespoke `NotTokenOwner(col, id)` revert no
///              longer surfaces on the non-owned / nonexistent-token path —
///              the underlying OZ error bubbles up instead. The frontend
///              filters to user-owned NFTs so this path is rarely hit;
///              backend / indexer never relied on the bespoke selector.
///              Saving: ~5k gas per NFT (no STATICCALL with 30k gas cap, no
///              try/catch dispatch), ≈250k per 50-NFT batch.
///
///         #2 — `_countBluechips` → `_userHoldsAnyBluechip`. The V4 helper
///              looped the full `bluechipCollections[]` array (cap 50)
///              calling `balanceOf` per collection and returning an integer
///              `count`. The only consumer in `burnBatch` was the boolean
///              verdict `count > 0` — the actual count was never used for
///              reward math. V5 early-returns on the first
///              `balanceOf(user) > 0` hit.
///
///              Trade-off: `Accrued.bluechipCount` shifts semantic from
///              "count of bluechip collections user holds at least 1 NFT in"
///              (uint256 ∈ [0, 50]) to a uint256 boolean ∈ {0, 1}. The event
///              field's byte-layout is unchanged (still uint256 at the same
///              tuple position), so backend listener `burnListener.ts`
///              continues to decode the 7-field event without modification.
///              Backend uses the field only for log lines, not for math —
///              backwards-compatible at the ABI / wire level. NatSpec
///              updated on the event field below.
///
///              Saving: up to ~245k per batch when the user holds ≥1
///              bluechip (50-collection registry, hit on iteration 1). When
///              the user holds NO bluechip, gas is identical to V4 (full
///              scan unchanged).
///
///         #3 — Cache `collectionStatus` SLOAD across same-collection runs
///              within `burnBatch`. When `collections[i] == collections[i-1]`
///              the cached `Status` from the previous iteration is reused
///              instead of re-reading storage. Saving: ~100 gas per
///              repeat (warm SLOAD cost), ≈5k for a 50-NFT batch from one
///              collection.
///
/// @dev    What stays IDENTICAL to V4 (Eugene-locked, do not drift):
///           - Constants: INITIAL_REWARD_BASE = 50 ether,
///             HALVING_INTERVAL = 100_000, BLUECHIP_BPS = 5000,
///             MAX_BATCH = 50, MAX_BLUECHIP_COLLECTIONS = 50,
///             MAX_WHITELIST_OPS_BATCH = 100.
///           - DEAD_ADDRESS, ERC721_INTERFACE_ID.
///           - `Accrued` event 7-field signature byte-for-byte (semantic of
///             field #3 shifted per delta #2 above — event topic / ABI
///             unchanged).
///           - `NFTBurned` per-NFT event signature byte-for-byte.
///           - `CollectionStatusSet` event signature byte-for-byte.
///           - `burnBatch(address[],uint256[])` external signature.
///           - `previewBatchReward(address[])` external signature.
///           - `currentRewardBase()` / `currentEra()` / `burnsUntilNextHalving()`.
///           - `addCollections(address[],Status)` / `removeCollections(address[])`.
///           - `getBluechipCollections()` / `bluechipCount()` /
///             `isBurnCollection(address)` / `isBluechipCollection(address)`.
///           - `transferFrom` to DEAD_ADDRESS (NOT safeTransferFrom).
///           - EIP-1153 transient-storage dedup `_dedup` pattern.
///           - `Pausable`, `ReentrancyGuard`, `Ownable` inheritance.
///           - Pragma `0.8.28` exact pin.
///
/// @dev    Bluechip semantic unchanged from V4 V3-semantic restore:
///         `Status.Bluechip` collections are NEVER burnable
///         (`burnBatch` rejects with `NotBurnable`); the ×1.5 multiplier
///         applies FLAT to the entire batch iff the burner holds ≥1 NFT
///         in ANY bluechip-whitelisted collection. The per-user-holding
///         scan is bounded by `MAX_BLUECHIP_COLLECTIONS = 50`.
///
/// @dev    V5 deploy targets:
///           - Ethereum mainnet (after Eugene approval via safebroker).
///           - V4 stays at `0x4ED2a780542B40121182eDeBef991577D60a10ec`
///             paused/abandoned post-V5; V4 pending EVNT (50 EVNT for
///             `0x09Aebf855B7415E6bBf78411B670A3426B90B494`, DEX #1089
///             accrual) stays in backend DB.
contract EvntBurner is Ownable, Pausable, ReentrancyGuard {
    // ─── Identity ────────────────────────────────────────────────────────
    string public constant NAME = "EvntBurner";
    string public constant VERSION = "5.0.0";

    // ─── Constants ───────────────────────────────────────────────────────
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Burns per halving era (Bitcoin-style). Same as V3/V4 (X3-9).
    uint256 public constant HALVING_INTERVAL = 100_000;

    /// @notice Initial per-NFT base reward at era 0. Same as V3/V4 (X3-8).
    uint256 public constant INITIAL_REWARD_BASE = 50 ether;

    /// @notice Bluechip multiplier in basis points (+50%, never halves).
    ///         Same as V3/V4 (X3-10).
    uint256 public constant BLUECHIP_BPS = 5000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public constant MAX_BATCH = 50;
    uint256 public constant MAX_BLUECHIP_COLLECTIONS = 50;

    /// @notice Bound on `addCollections` / `removeCollections` batch size.
    ///         Same as V4. Caps the gas spike of a single admin tx and
    ///         keeps the worst-case revert path manageable.
    uint256 public constant MAX_WHITELIST_OPS_BATCH = 100;

    /// @dev ERC-165 interface id for IERC721. Kept as exported constant in
    ///      case off-chain consumers reference it — V4/V5 contract itself
    ///      does NOT read this (validation moved off-chain in V4).
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;

    // ─── Status enum ─────────────────────────────────────────────────────

    /// @notice Whitelist classification for a collection.
    ///         - `None`     (0) — default; collection NOT in any list.
    ///         - `Burn`     (1) — burn-eligible; emits `NFTBurned` + counts
    ///                            toward `Accrued.burnedCount`, base reward.
    ///         - `Bluechip` (2) — multiplier ×1.5 PROOF-OF-WEALTH marker.
    ///                            Bluechip NFTs are NEVER burned (`burnBatch`
    ///                            reverts `NotBurnable` for `Status.Bluechip`
    ///                            collections). The multiplier applies
    ///                            FLAT to every NFT in a `burnBatch` call
    ///                            iff the burner holds ≥1 NFT from ANY
    ///                            bluechip-whitelisted collection. Per V3
    ///                            spec §4 + cosmos memo §4.2 wash-trading
    ///                            vector closure.
    enum Status {
        None,
        Burn,
        Bluechip
    }

    // ─── Storage ─────────────────────────────────────────────────────────

    /// @notice Cumulative count of NFTs burned across all users since deploy.
    ///         Used as the era input: `era = totalBurns / HALVING_INTERVAL`.
    uint256 public totalBurns;

    /// @notice Single mapping unifying burn + bluechip whitelist membership.
    ///         A collection is exactly one of `None` / `Burn` / `Bluechip`
    ///         at any moment — structurally guaranteed by the enum type.
    mapping(address => Status) public collectionStatus;

    /// @notice Bounded list of `Status.Bluechip` collections — enumerated
    ///         by `_userHoldsAnyBluechip(user)` on every `burnBatch` to
    ///         apply the V3 per-user-holding multiplier semantic. Cap at
    ///         `MAX_BLUECHIP_COLLECTIONS = 50` bounds the worst-case scan
    ///         to ~50 × 5k gas = 250k. V5 early-returns on the first
    ///         positive-balance hit. Burn-list deliberately NOT mirrored
    ///         here — burn collections are read off-chain via the
    ///         `CollectionStatusSet` event stream, preserving the V4 gas
    ///         win on the volume admin path.
    address[] public bluechipCollections;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted once per NFT burned. Indexed for backend listener
    ///         compatibility (`burnListener.ts`). Unchanged from V3/V4.
    event NFTBurned(address indexed user, address indexed collection, uint256 indexed tokenId);

    /// @notice Backend listener subscribes to this event to trigger the
    ///         `EvntClaimVault.credit()` relay on Polygon. 7-field shape +
    ///         field names byte-for-byte identical to V4 (Sprint X v3
    ///         LOW-07 / X3-19 closure).
    ///
    /// @dev    V5 SEMANTIC SHIFT on `bluechipCount` field (delta #2):
    ///         this field now reports a uint256 boolean ∈ {0, 1} (1 iff
    ///         the burner holds ≥1 NFT in ANY bluechip-whitelisted
    ///         collection at burn time) instead of V4's actual integer
    ///         count of holding collections. The event byte-layout is
    ///         UNCHANGED (still uint256 at position #3) — backend listener
    ///         `burnListener.ts` continues to decode without modification.
    ///         If you need the actual count off-chain, call the
    ///         `getBluechipCollections()` view + per-collection
    ///         `balanceOf(user)` from the indexer.
    event Accrued(
        address indexed user,
        uint256 burnedCount,
        uint256 bluechipCount,
        uint256 totalEvnt,
        uint256 eraAtStart,
        uint256 eraAtEnd,
        uint256 totalBurnsAfter
    );

    /// @notice V4 unified status-change event. Replaces V3's four
    ///         single-purpose events (`BurnCollectionAdded` /
    ///         `BurnCollectionRemoved` / `BluechipCollectionAdded` /
    ///         `BluechipCollectionRemoved`). Carries both prev and new
    ///         status so off-chain indexers can reconstruct full transition
    ///         history from one event topic.
    event CollectionStatusSet(address indexed collection, Status indexed prevStatus, Status indexed newStatus);

    /// @dev Custom indexed pause events on top of OZ Pausable.
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);

    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ─── Custom Errors ───────────────────────────────────────────────────

    error ZeroAddress();
    error InvalidCollection(address collection);

    error EmptyBatch();
    error BatchTooLarge(uint256 provided, uint256 max);
    error ArrayLengthMismatch();
    error NotWhitelisted(address collection);
    /// @notice V3-semantic restore: the collection is whitelisted but its
    ///         `Status` is not `Burn` (i.e. `Status.Bluechip` —
    ///         multiplier-only, never burned).
    error NotBurnable(address collection);
    /// @notice Kept as exported error selector for ABI compatibility.
    ///         V5 NO LONGER emits this error on the burnBatch ownership
    ///         path — the underlying OZ ERC-721 revert
    ///         (`ERC721IncorrectOwner` / `ERC721NonexistentToken` /
    ///         `ERC721InsufficientApproval`) surfaces instead per
    ///         delta #1 above. Selector preserved so external consumers
    ///         that built type-safe revert decoders against V4 still
    ///         compile (they will now never see this revert from
    ///         `burnBatch`).
    error NotTokenOwner(address collection, uint256 tokenId);
    error DuplicateInBatch(address collection, uint256 tokenId);

    /// @notice Collection is already at the requested target status.
    error AlreadyInList(address collection, Status status);
    /// @notice Collection is not on any list.
    error NotInList(address collection);
    /// @notice `addCollections` called with `target == Status.None`.
    ///         Use `removeCollections` for the None-target path.
    error InvalidTargetStatus(Status target);
    /// @notice `addCollections` / `removeCollections` batch exceeded
    ///         `MAX_WHITELIST_OPS_BATCH`.
    error WhitelistBatchTooLarge(uint256 size, uint256 maxSize);
    /// @notice Bluechip cap (`MAX_BLUECHIP_COLLECTIONS`) reached.
    error BluechipListFull(uint256 max);

    // ─── Constructor ─────────────────────────────────────────────────────

    /// @param initialOwner Address of the contract owner (admin role).
    ///                     Phase A: EOA. Phase B: Gnosis Safe (per
    ///                     Sprint X v3 architecture α, see
    ///                     `workspace/SPRINT-X-v3-DESIGN.md`).
    /// @dev BHN-L-10 closure (defense-in-depth): defensive zero-address
    ///      invariant. OZ Ownable's `OwnableInvalidOwner(address(0))`
    ///      fires first, this require is redundant-by-design in case OZ
    ///      changes semantics on a future major.
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "EvntBurner: zero owner");
    }

    // ─── Public / External: User write ───────────────────────────────────

    /// @notice Burn a batch of NFTs and earn EVNT via auto-halving.
    /// @dev    Per-NFT reward = `(INITIAL_REWARD_BASE >> era) × multiplier`,
    ///         where `era = (totalBurnsBefore + i) / HALVING_INTERVAL` (so
    ///         a batch crossing an era boundary mid-batch correctly applies
    ///         the lower reward to the post-boundary NFTs), and
    ///         `multiplier = 1.5` (BPS 15000/10000) if the burner holds
    ///         ≥1 NFT in ANY `Status.Bluechip` collection, `1.0` otherwise.
    ///         Multiplier is computed ONCE at the start of the batch from
    ///         `_userHoldsAnyBluechip(msg.sender)` and applied FLAT to
    ///         every NFT. Reverts on duplicate (collection, tokenId)
    ///         within the same batch via EIP-1153 transient storage.
    ///
    ///         All burned NFTs MUST be from `Status.Burn` collections.
    ///         `Status.Bluechip` collections are proof-of-wealth markers
    ///         only — they are NEVER sinks. Attempting to burn a
    ///         `Status.Bluechip` NFT reverts `NotBurnable` (per V3 spec §4
    ///         + cosmos memo §4.2 wash-trading vector closure).
    ///
    ///         V5 delta #1 — non-owned tokens revert with the underlying
    ///         OZ ERC-721 error (`ERC721IncorrectOwner` /
    ///         `ERC721NonexistentToken` / `ERC721InsufficientApproval`)
    ///         rather than the V4 bespoke `NotTokenOwner(col, id)`.
    ///         Funds are safe — every revert is observed BEFORE state
    ///         mutation (`totalBurns` increments post-loop), so atomic
    ///         rollback is guaranteed.
    ///
    ///         No EVNT is moved or minted on this chain — the `Accrued`
    ///         event is observed by the backend listener which broadcasts
    ///         `EvntClaimVault.credit()` on Polygon (Sprint X v3 §5.1).
    /// @param  collections Array of NFT collection addresses. Each MUST be
    ///                     `Status.Burn`. `Status.None` reverts
    ///                     `NotWhitelisted`; `Status.Bluechip` reverts
    ///                     `NotBurnable`.
    /// @param  tokenIds    Array of token IDs to burn (1:1 with collections).
    function burnBatch(address[] calldata collections, uint256[] calldata tokenIds)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 len = collections.length;
        if (len == 0) revert EmptyBatch();
        if (len != tokenIds.length) revert ArrayLengthMismatch();
        if (len > MAX_BATCH) revert BatchTooLarge(len, MAX_BATCH);

        // V5 delta #2 — boolean verdict only. `_userHoldsAnyBluechip`
        // early-returns on the first positive hit, saving up to ~245k gas
        // vs V4's full-array `_countBluechips` when ≥1 bluechip is held.
        bool userIsBluechip = _userHoldsAnyBluechip(msg.sender);

        uint256 burnsBefore = totalBurns;
        uint256 totalEvnt;

        // V5 delta #3 — cache `collectionStatus` SLOAD across same-collection
        // runs. When `col == lastCol`, reuse cached `Status` from the prior
        // iteration. Saves ~100 gas/repeat (warm SLOAD), ~5k for a 50-NFT
        // batch from a single collection.
        address lastCol;
        Status lastStatus;

        for (uint256 i; i < len;) {
            address col = collections[i];
            uint256 tokenId = tokenIds[i];

            Status s;
            if (col == lastCol) {
                // Cache hit — skip the SLOAD.
                s = lastStatus;
            } else {
                s = collectionStatus[col];
                lastCol = col;
                lastStatus = s;
            }

            // V3-semantic restore: ONLY `Status.Burn` is burnable.
            // `Status.None` → NotWhitelisted; `Status.Bluechip` → NotBurnable.
            // (Bluechip is proof-of-wealth multiplier marker, never sink.)
            if (s == Status.None) revert NotWhitelisted(col);
            if (s != Status.Burn) revert NotBurnable(col);

            // EIP-1153 transient duplicate guard. Each (col, tokenId) pair
            // gets a unique transient slot keyed by keccak256. Cleared
            // automatically at tx end.
            bytes32 key = keccak256(abi.encodePacked(col, tokenId));
            uint256 seen;
            assembly ("memory-safe") {
                seen := tload(key)
            }
            if (seen != 0) revert DuplicateInBatch(col, tokenId);
            assembly ("memory-safe") {
                tstore(key, 1)
            }

            // V5 delta #1 — drop redundant `try ownerOf{gas:30k}` precheck.
            // `transferFrom` already enforces ownership via OZ 5.x's
            // `_update` + post-call `previousOwner != from` revert.
            // Non-owner / nonexistent / unapproved paths surface the
            // underlying OZ error instead of `NotTokenOwner`. Funds safe
            // (revert atomicity preserved).
            IERC721(col).transferFrom(msg.sender, DEAD_ADDRESS, tokenId);

            emit NFTBurned(msg.sender, col, tokenId);

            // Per-NFT auto-halving (era boundaries respected mid-batch).
            // V3-semantic: flat per-user-holding multiplier.
            uint256 era = (burnsBefore + i) / HALVING_INTERVAL;
            uint256 baseReward = INITIAL_REWARD_BASE >> era;
            uint256 reward =
                userIsBluechip ? (baseReward * (BPS_DENOMINATOR + BLUECHIP_BPS)) / BPS_DENOMINATOR : baseReward;

            totalEvnt += reward;

            unchecked {
                ++i;
            }
        }

        uint256 burnsAfter = burnsBefore + len;
        totalBurns = burnsAfter;

        // `Accrued.bluechipCount` reports the V5 boolean verdict as uint256
        // ∈ {0, 1} (delta #2). Backend decodes the 7-field event unchanged.
        emit Accrued(
            msg.sender,
            len,
            userIsBluechip ? 1 : 0,
            totalEvnt,
            burnsBefore / HALVING_INTERVAL,
            (burnsAfter - 1) / HALVING_INTERVAL,
            burnsAfter
        );
    }

    // ─── Public / External: Views ────────────────────────────────────────

    /// @notice Precise reward preview that respects in-batch era
    ///         progression. Frontend reads this for "you'll receive X EVNT"
    ///         display before burning. Soft-mode: a non-burnable entry
    ///         (`Status.None` OR `Status.Bluechip`) contributes 0 silently
    ///         — for top-level shape errors (oversize / empty), reverts.
    /// @dev    Owner check intentionally NOT performed (so the UI can quote
    ///         pre-approval). V3-semantic: this preview is the BASE-reward
    ///         preview only — the per-user ×1.5 multiplier is NOT applied
    ///         here because the preview is called from a contextless view
    ///         path (no msg.sender to scan). Frontend scales by the
    ///         multiplier client-side based on `getBluechipCollections()`
    ///         + per-collection `balanceOf`.
    /// @param  collections   Array of NFT collection addresses to preview.
    /// @return totalEvnt     Sum of per-NFT BASE rewards across the batch
    ///                       (multiplier NOT applied — frontend scales).
    /// @return perNftReward  Per-NFT BASE reward (length == collections.length).
    function previewBatchReward(address[] calldata collections)
        external
        view
        returns (uint256 totalEvnt, uint256[] memory perNftReward)
    {
        uint256 len = collections.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_BATCH) revert BatchTooLarge(len, MAX_BATCH);

        perNftReward = new uint256[](len);
        uint256 burnsBefore = totalBurns;

        for (uint256 i; i < len;) {
            address col = collections[i];
            Status s = collectionStatus[col];
            if (s == Status.Burn) {
                uint256 era = (burnsBefore + i) / HALVING_INTERVAL;
                uint256 baseReward = INITIAL_REWARD_BASE >> era;
                perNftReward[i] = baseReward;
                totalEvnt += baseReward;
            }
            // Status.None or Status.Bluechip → perNftReward[i] stays 0.
            // (Bluechip not burnable — see burnBatch NatSpec).
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Current per-NFT base reward (no bluechip multiplier).
    /// @return Per-NFT base reward in wei EVNT.
    function currentRewardBase() external view returns (uint256) {
        return INITIAL_REWARD_BASE >> (totalBurns / HALVING_INTERVAL);
    }

    /// @notice Era display for the HalvingProgress widget. Equal to
    ///         `floor(totalBurns / HALVING_INTERVAL)`.
    function currentEra() external view returns (uint256) {
        return totalBurns / HALVING_INTERVAL;
    }

    /// @notice Burns until the next halving (era boundary).
    function burnsUntilNextHalving() external view returns (uint256) {
        return HALVING_INTERVAL - (totalBurns % HALVING_INTERVAL);
    }

    /// @notice V3-compatible wrapper: returns true iff `col`'s status is
    ///         exactly `Status.Burn`. Off-chain consumers (backend,
    ///         frontend) can keep V3 ABI semantics without migrating.
    function isBurnCollection(address col) external view returns (bool) {
        return collectionStatus[col] == Status.Burn;
    }

    /// @notice V3-compatible wrapper: returns true iff `col`'s status is
    ///         exactly `Status.Bluechip`.
    function isBluechipCollection(address col) external view returns (bool) {
        return collectionStatus[col] == Status.Bluechip;
    }

    /// @notice V3-compatible view: current count of `Status.Bluechip`
    ///         collections. Equal to `bluechipCollections.length`.
    function bluechipCount() external view returns (uint256) {
        return bluechipCollections.length;
    }

    /// @notice V3-compatible view: full list of `Status.Bluechip`
    ///         collections. Used by the frontend admin UI + the
    ///         `useUserNfts` hook to identify bluechip-multiplier NFTs in
    ///         a user's wallet. Length bounded by
    ///         `MAX_BLUECHIP_COLLECTIONS = 50`.
    function getBluechipCollections() external view returns (address[] memory) {
        return bluechipCollections;
    }

    // ─── Internal helpers ────────────────────────────────────────────────

    /// @notice V5 delta #2 — return true iff `user` holds ≥1 NFT in ANY
    ///         `Status.Bluechip` collection. Used by `burnBatch` to
    ///         determine the flat ×1.5 multiplier ONCE per batch.
    /// @dev    Each `balanceOf` call gas-capped at 30k (same as V4) so a
    ///         malicious or buggy bluechip collection cannot grief the
    ///         burn. `try/catch` gracefully skips non-responsive
    ///         collections (returns the running boolean without them
    ///         rather than reverting the entire burn).
    ///
    ///         Early-returns on the first positive hit — worst-case scan
    ///         is bounded by `MAX_BLUECHIP_COLLECTIONS = 50` when the
    ///         user holds no bluechip (identical to V4). Best-case is
    ///         1 STATICCALL when the first registered bluechip matches.
    /// @param  user Address whose holdings to check.
    /// @return Boolean: true iff at least one bluechip collection reports
    ///         `balanceOf(user) > 0`.
    function _userHoldsAnyBluechip(address user) internal view returns (bool) {
        uint256 len = bluechipCollections.length;
        for (uint256 i; i < len;) {
            address bc = bluechipCollections[i];
            try IERC721(bc).balanceOf{gas: 30_000}(user) returns (uint256 bal) {
                if (bal > 0) {
                    return true;
                }
            } catch {
                // Non-responsive bluechip → skip (don't grief the user's burn).
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    // ─── Public / External: Admin write ──────────────────────────────────

    /// @notice Set a batch of collections to `target` status. Single-add
    ///         goes through this same code path (`addCollections([col],
    ///         Status.Burn)`).
    /// @dev    Atomic: if any per-collection check fails (e.g. transition
    ///         into `Bluechip` hits `MAX_BLUECHIP_COLLECTIONS`), the entire
    ///         batch reverts. Use this property to keep mutual-exclusion
    ///         transitions deterministic (Burn → Bluechip cannot leave a
    ///         partial state).
    /// @param  cols    Array of collection addresses to set.
    /// @param  target  Target status. MUST be `Status.Burn` or
    ///                 `Status.Bluechip` — passing `Status.None` reverts
    ///                 with `InvalidTargetStatus`. Use `removeCollections`
    ///                 for the None-target path.
    function addCollections(address[] calldata cols, Status target) external onlyOwner {
        uint256 len = cols.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_WHITELIST_OPS_BATCH) revert WhitelistBatchTooLarge(len, MAX_WHITELIST_OPS_BATCH);
        if (target == Status.None) revert InvalidTargetStatus(target);

        for (uint256 i; i < len;) {
            address col = cols[i];
            if (col == address(0)) revert ZeroAddress();
            if (col == DEAD_ADDRESS || col == address(this)) {
                revert InvalidCollection(col);
            }

            Status prev = collectionStatus[col];
            if (prev == target) revert AlreadyInList(col, prev);

            // Maintain `bluechipCollections[]` in lockstep with status
            // transitions touching `Status.Bluechip`. Cap checked BEFORE
            // push (atomic — partial state impossible because EVM reverts
            // the whole tx on cap-hit).
            if (target == Status.Bluechip) {
                if (bluechipCollections.length >= MAX_BLUECHIP_COLLECTIONS) {
                    revert BluechipListFull(MAX_BLUECHIP_COLLECTIONS);
                }
                bluechipCollections.push(col);
            }
            if (prev == Status.Bluechip) {
                _removeBluechipFromArray(col);
            }

            collectionStatus[col] = target;
            emit CollectionStatusSet(col, prev, target);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Remove a batch of collections from the whitelist (set their
    ///         status to `None`).
    /// @param  cols  Array of collection addresses to remove.
    function removeCollections(address[] calldata cols) external onlyOwner {
        uint256 len = cols.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_WHITELIST_OPS_BATCH) revert WhitelistBatchTooLarge(len, MAX_WHITELIST_OPS_BATCH);

        for (uint256 i; i < len;) {
            address col = cols[i];
            Status prev = collectionStatus[col];
            if (prev == Status.None) revert NotInList(col);

            if (prev == Status.Bluechip) {
                _removeBluechipFromArray(col);
            }

            collectionStatus[col] = Status.None;
            emit CollectionStatusSet(col, prev, Status.None);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Swap-and-pop a bluechip from `bluechipCollections[]`. Worst-case
    ///      O(MAX_BLUECHIP_COLLECTIONS=50) scan. Eugene expects ≤50 bluechip
    ///      adds over product lifetime so a linear scan is acceptable vs
    ///      maintaining an O(1) index mapping (additional 22k per add).
    function _removeBluechipFromArray(address col) internal {
        uint256 len = bluechipCollections.length;
        for (uint256 i; i < len;) {
            if (bluechipCollections[i] == col) {
                if (i != len - 1) {
                    bluechipCollections[i] = bluechipCollections[len - 1];
                }
                bluechipCollections.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Pause the contract (disables `burnBatch`).
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /// @notice Unpause the contract.
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /// @notice Emergency-rescue ERC-20 tokens accidentally sent to the
    ///         contract. Cannot affect burned NFTs (they live on
    ///         DEAD_ADDRESS — an address with no private key, so no
    ///         recovery is possible by any actor including admin) or
    ///         burn flow.
    /// @param  token  ERC-20 token contract.
    /// @param  to     Destination wallet.
    /// @param  amount Amount to rescue (in token base units).
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        // Use raw call so a missing return-value (non-standard ERC-20) does
        // not brick rescue. SafeERC20 not imported to keep parity with V3
        // ABI surface.
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "EvntBurner: rescue failed");
        emit TokensRescued(token, to, amount);
    }
}
