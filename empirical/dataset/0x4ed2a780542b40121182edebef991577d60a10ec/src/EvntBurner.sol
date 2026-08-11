// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EvntBurner — Sprint X v3 Phase A V4 (gas-optimized whitelist redesign, V3-semantic restore)
/// @notice V4 redesign of the EVNT-unified Ethereum mainnet burner. Three
///         storage / ABI deltas vs V3 deliver a ~70 % per-add gas saving and
///         an atomic batch whitelist entrypoint (Eugene-locked 2026-05-27
///         after V3's ~196k gas-per-add complaint):
///
///         1. Unified `Status` enum — replaces the V3 quad of
///            `mapping(...) bool isBurnCollection` + `address[]
///            burnCollections` + `mapping(...) uint256 _burnIndex` (and
///            symmetric trio for bluechip) with a single
///            `mapping(address => Status) collectionStatus`. Mutual exclusion
///            (V3 X3-11) becomes *structural* — a collection is exactly one
///            of `None`, `Burn`, `Bluechip` by type. V3-compatible wrapper
///            views `isBurnCollection(address)` / `isBluechipCollection(address)`
///            kept (so off-chain consumers don't have to migrate).
///
///         2. Single batched entrypoint — `addCollections(address[] cols,
///            Status target)` / `removeCollections(address[] cols)` replace
///            the V3 quad (`addBurnCollection` / `removeBurnCollection` /
///            `addBluechipCollection` / `removeBluechipCollection`). N×21k
///            base-fee saving per batch + one event per delta. Single-add
///            still possible via `addCollections([col], Status.Burn)`.
///
///         3. On-chain ERC-721 validation dropped — `_validateIsERC721`
///            (V3 `code.length` + ERC-165 + legacy-balanceOf fallback)
///            removed. Sanity moved off-chain to backend
///            `/admin/burn/calldata/*` preflight + frontend admin warning.
///            Funds are SAFE under all misconfiguration paths because
///            `burnBatch`'s `try ownerOf` pre-check (retained verbatim
///            from V3) catches non-ERC-721 *contracts* (rerouting to
///            uniform `NotTokenOwner` revert) and Solidity's pre-call
///            extcodesize check rejects *EOAs* with "call to non-contract
///            address" — in BOTH cases the entire batch reverts atomically
///            (no NFT moved, no `Accrued` emitted, no reward accrued, no
///            cross-chain credit relay). UX suffers on EOA misconfig
///            (cryptic revert message vs uniform `NotTokenOwner`), but
///            off-chain admin preflight prevents that case from reaching
///            production. Constant `ERC721_INTERFACE_ID = 0x80ac58cd`
///            kept as exported constant in case frontend / backend
///            imports it.
///
/// @dev    V3-semantic restore (Eugene-locked 2026-05-27 after V4 first cut):
///         The V4 first iteration drifted the bluechip semantic in two
///         ways that Eugene rejected — both reverted here so the V4 gas
///         win is delivered WITHOUT changing economics or opening the
///         wash-trading vector cosmos closed:
///
///         (a) `Status.Bluechip` collections are NOT burnable. They are
///             proof-of-wealth multiplier markers only. `burnBatch` rejects
///             any (col, tokenId) whose `collectionStatus != Status.Burn`
///             with `NotBurnable`. Per V3 spec §4 + cosmos memo §4.2:
///             allowing bluechip-as-burn-target would let an attacker buy
///             cheap NFTs from a collection that fell in price after being
///             whitelisted as bluechip → burn them → claim the ×1.5
///             multiplier. Locked.
///
///         (b) Bluechip multiplier is PER-USER-HOLDING, not per-NFT-burned.
///             `burnBatch` computes `bluechipHeld = _countBluechips(msg.sender)`
///             ONCE at start (scanning `bluechipCollections[]`). If
///             `bluechipHeld > 0`, the FLAT ×1.5 multiplier applies to
///             every NFT in the batch (which by (a) are all `Status.Burn`).
///             If user holds no bluechip NFT, no multiplier. The
///             `Accrued.bluechipCount` field reports `bluechipHeld` —
///             same V3 meaning, byte-compatible 7-field event signature.
///
///         To support (b) we re-introduce the bounded `bluechipCollections[]`
///         array (capped at `MAX_BLUECHIP_COLLECTIONS = 50`) for on-chain
///         scan. Burn-list reads remain event-driven (no `burnCollections[]`
///         array), preserving the V4 gas win for the volume case.
///
/// @dev    What stays IDENTICAL to V3 (Eugene-locked, do not drift):
///           - Constants: INITIAL_REWARD_BASE = 50 ether,
///             HALVING_INTERVAL = 100_000, BLUECHIP_BPS = 5000,
///             MAX_BATCH = 50, MAX_BLUECHIP_COLLECTIONS = 50.
///           - DEAD_ADDRESS, _ERC721_INTERFACE_ID.
///           - `Accrued` event 7-field signature byte-for-byte (backend
///             listener `burnListener.ts` subscribes to this — DO NOT
///             reorder / rename / re-index).
///           - `burnBatch(address[],uint256[])` external signature
///             (frontend wagmi wiring depends on this).
///           - `currentRewardBase()` / `previewBatchReward(address[])` view
///             signatures, halving formula, reward math.
///           - `transferFrom` to DEAD_ADDRESS (NOT safeTransferFrom).
///           - EIP-1153 transient-storage dedup `_dedup` pattern.
///           - `try ownerOf{gas: 30_000}` per-NFT pre-check.
///           - `Pausable`, `ReentrancyGuard`, `Ownable` inheritance.
///           - Pragma `0.8.28` exact pin.
///
/// @dev    Mutual exclusion guarantee — V4 structurally prevents a
///         collection from being both Burn and Bluechip simultaneously
///         (the `Status` enum can hold only one value). Transition from
///         `Burn → Bluechip` (or vice versa) is one atomic admin call:
///         `addCollections([col], Status.Bluechip)` — equivalent to V3's
///         "remove then add" but single-tx. The unified `CollectionStatusSet`
///         event encodes both prev and new status, so off-chain indexers can
///         reconstruct full transition history from a single event stream.
///
/// @dev    Bluechip storage — `bluechipCollections[]` array (V3-style)
///         tracks the bluechip set for on-chain scan in `_countBluechips`.
///         Capped at `MAX_BLUECHIP_COLLECTIONS = 50`. The `bluechipCount()`
///         view returns `bluechipCollections.length`. The burn-list is
///         deliberately NOT mirrored in storage — `Status.Burn` reads come
///         from the `CollectionStatusSet` event stream off-chain. This
///         preserves the V4 gas win on the volume admin path (~33k for a
///         single Burn add).
///
/// @dev    Sprint X v3 Phase A history pointers:
///           - V3 deployed Ethereum mainnet `0x68740e817315A437A0EceD4B0323b95A2d8135B2`
///             (block 25184804) with NO state — empty redeploy is safe.
///           - Sentinel pre-impl review pending — PR flagged
///             `[SENTINEL-REQUIRED]` for full pre-deploy audit.
///           - Backend ABI counterpart in
///             `nft-energy-backend/src/lib/contracts.ts:evntBurnerAbi`
///             will be regenerated post-merge (separate PR).
contract EvntBurner is Ownable, Pausable, ReentrancyGuard {
    // ─── Identity ────────────────────────────────────────────────────────
    string public constant NAME = "EvntBurner";
    string public constant VERSION = "4.0.0";

    // ─── Constants ───────────────────────────────────────────────────────
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Burns per halving era (Bitcoin-style). Same as V3 (X3-9).
    uint256 public constant HALVING_INTERVAL = 100_000;

    /// @notice Initial per-NFT base reward at era 0. Same as V3 (X3-8).
    uint256 public constant INITIAL_REWARD_BASE = 50 ether;

    /// @notice Bluechip multiplier in basis points (+50%, never halves).
    ///         Same as V3 (X3-10).
    uint256 public constant BLUECHIP_BPS = 5000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public constant MAX_BATCH = 50;
    uint256 public constant MAX_BLUECHIP_COLLECTIONS = 50;

    /// @notice V4 NEW: bound on `addCollections` / `removeCollections`
    ///         batch size. Caps the gas spike of a single admin tx and
    ///         keeps the worst-case revert path manageable.
    uint256 public constant MAX_WHITELIST_OPS_BATCH = 100;

    /// @dev ERC-165 interface id for IERC721. Kept as exported constant in
    ///      case off-chain consumers reference it — V4 contract itself no
    ///      longer reads this (validation moved off-chain).
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;

    // ─── Status enum (V4 core) ───────────────────────────────────────────

    /// @notice Whitelist classification for a collection.
    ///         - `None`     (0) — default; collection NOT in any list.
    ///         - `Burn`     (1) — burn-eligible; emits `NFTBurned` + counts
    ///                            toward `Accrued.burnedCount`, base reward.
    ///         - `Bluechip` (2) — multiplier ×1.5 PROOF-OF-WEALTH marker.
    ///                            Bluechip NFTs are NEVER burned (`burnBatch`
    ///                            reverts `NotBurnable` for `Status.Bluechip`
    ///                            collections). The multiplier applies
    ///                            FLAT to every NFT in a `burnBatch` call
    ///                            iff `_countBluechips(msg.sender) > 0`
    ///                            (i.e. the burner holds ≥1 NFT from ANY
    ///                            bluechip-whitelisted collection). Per V3
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
    ///         by `_countBluechips(user)` on every `burnBatch` to apply
    ///         the V3 per-user-holding multiplier semantic. Cap at
    ///         `MAX_BLUECHIP_COLLECTIONS = 50` bounds the worst-case scan
    ///         to ~50 × 5k gas = 250k. Burn-list deliberately NOT mirrored
    ///         here — burn collections are read off-chain via the
    ///         `CollectionStatusSet` event stream, preserving the V4 gas
    ///         win on the volume admin path.
    address[] public bluechipCollections;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted once per NFT burned. Indexed for backend listener
    ///         compatibility (`burnListener.ts`). Unchanged from V3.
    event NFTBurned(address indexed user, address indexed collection, uint256 indexed tokenId);

    /// @notice Backend listener subscribes to this event to trigger the
    ///         `EvntClaimVault.credit()` relay on Polygon. 7-field shape +
    ///         field names byte-for-byte identical to V3 (Sprint X v3
    ///         LOW-07 / X3-19 closure). DO NOT alter — backend ABI in
    ///         `nft-energy-backend/src/lib/contracts.ts:evntBurnerAbi`
    ///         matches this signature exactly.
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
    /// @notice V3-semantic restore (2026-05-27): the collection is whitelisted
    ///         but its `Status` is not `Burn` (i.e. `Status.Bluechip` —
    ///         multiplier-only, never burned).
    error NotBurnable(address collection);
    error NotTokenOwner(address collection, uint256 tokenId);
    error DuplicateInBatch(address collection, uint256 tokenId);

    /// @notice V4 NEW: collection is already at the requested target status
    ///         (replaces V3's separate `AlreadyInBurnList` / `AlreadyInBluechipList`).
    error AlreadyInList(address collection, Status status);
    /// @notice V4 NEW: collection is not on any list (replaces V3's
    ///         `NotInBurnList` / `NotInBluechipList`).
    error NotInList(address collection);
    /// @notice V4 NEW: `addCollections` called with `target == Status.None`.
    ///         Use `removeCollections` for the None-target path.
    error InvalidTargetStatus(Status target);
    /// @notice V4 NEW: `addCollections` / `removeCollections` batch
    ///         exceeded `MAX_WHITELIST_OPS_BATCH`.
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
    ///         `_countBluechips(msg.sender)` and applied FLAT to every NFT.
    ///         Reverts on duplicate (collection, tokenId) within the same
    ///         batch via EIP-1153 transient storage.
    ///
    ///         All burned NFTs MUST be from `Status.Burn` collections.
    ///         `Status.Bluechip` collections are proof-of-wealth markers
    ///         only — they are NEVER sinks. Attempting to burn a
    ///         `Status.Bluechip` NFT reverts `NotBurnable` (per V3 spec §4
    ///         + cosmos memo §4.2 wash-trading vector closure).
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

        // V3-semantic restore (2026-05-27): per-user-holding multiplier.
        // Scan `bluechipCollections[]` ONCE and stash the flat-multiplier
        // verdict before the loop. Cost: bounded by MAX_BLUECHIP_COLLECTIONS
        // (50) × 5k (warm STATICCALL with 30k cap) ≈ 250k worst-case, far
        // more typically 50-100k.
        uint256 bluechipHeld = _countBluechips(msg.sender);
        bool userIsBluechip = bluechipHeld > 0;

        uint256 burnsBefore = totalBurns;
        uint256 totalEvnt;

        for (uint256 i; i < len;) {
            address col = collections[i];
            uint256 tokenId = tokenIds[i];

            Status s = collectionStatus[col];
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

            // V1/V2/V3 hardening retained: try ownerOf pre-check (uniform
            // NotTokenOwner revert; OZ ERC721 reverts ERC721NonexistentToken
            // instead of returning address(0)). {gas: 30_000} cap caps
            // griefing surface from a misbehaving collection.
            IERC721 nft = IERC721(col);
            try nft.ownerOf{gas: 30_000}(tokenId) returns (address actual) {
                if (actual != msg.sender) revert NotTokenOwner(col, tokenId);
            } catch {
                revert NotTokenOwner(col, tokenId);
            }

            // V1/V2/V3 hardening retained: transferFrom (NOT safeTransferFrom).
            nft.transferFrom(msg.sender, DEAD_ADDRESS, tokenId);

            emit NFTBurned(msg.sender, col, tokenId);

            // Per-NFT auto-halving (era boundaries respected mid-batch).
            // V3-semantic restore: flat per-user-holding multiplier.
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

        // `Accrued.bluechipCount` reports the COUNT OF BLUECHIP COLLECTIONS
        // user holds (V3-semantic, byte-compatible 7-field event signature).
        emit Accrued(
            msg.sender,
            len,
            bluechipHeld,
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
    ///         pre-approval). V3-semantic restore: this preview is the
    ///         BASE-reward preview only — the per-user ×1.5 multiplier is
    ///         NOT applied here because the preview is called from a
    ///         contextless view path (no msg.sender to scan). Frontend
    ///         scales by the multiplier client-side based on
    ///         `_countBluechips(user)` (exposed via the live array view
    ///         `getBluechipCollections()` + per-collection `balanceOf`).
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

    /// @notice Count how many `Status.Bluechip` collections `user` holds
    ///         at least 1 NFT in. Used by `burnBatch` to determine the
    ///         flat ×1.5 multiplier ONCE per batch (V3-semantic).
    /// @dev    Each `balanceOf` call gas-capped at 30k (same as `ownerOf`)
    ///         so a malicious or buggy bluechip collection cannot grief
    ///         the burn. `try/catch` gracefully skips non-responsive
    ///         collections (returns count without them rather than
    ///         reverting the entire burn).
    /// @param  user  Address whose holdings to count.
    /// @return count Number of bluechip collections with `balanceOf(user) > 0`.
    function _countBluechips(address user) internal view returns (uint256 count) {
        uint256 len = bluechipCollections.length;
        for (uint256 i; i < len;) {
            address bc = bluechipCollections[i];
            try IERC721(bc).balanceOf{gas: 30_000}(user) returns (uint256 bal) {
                if (bal > 0) {
                    unchecked {
                        ++count;
                    }
                }
            } catch {
                // Non-responsive bluechip → skip (don't grief the user's burn).
            }
            unchecked {
                ++i;
            }
        }
    }

    // ─── Public / External: Admin write ──────────────────────────────────

    /// @notice Set a batch of collections to `target` status. Single-add
    ///         goes through this same code path (`addCollections([col],
    ///         Status.Burn)`) — V4 has no separate single-add entrypoint.
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
