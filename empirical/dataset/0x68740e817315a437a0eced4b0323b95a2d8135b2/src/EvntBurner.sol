// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EvntBurner — Sprint X v3 Ethereum mainnet burner (EVNT-unified)
/// @notice Sprint X v3 — see `workspace/SPRINT-X-v3-DESIGN.md` §4.1. EvntBurner
///         is the Ethereum-mainnet sibling of `EvntClaimVault` (Polygon). Users
///         burn whitelisted ERC-721s here; the on-chain `Accrued` event is
///         picked up by a backend listener which auto-relays a `credit()`
///         call to `EvntClaimVault` on Polygon (RELAYER_ROLE EOA, 12-conf
///         reorg wait per EVAP-RISK-01). No EVNT is moved or minted on this
///         chain — Ethereum stays accounting-only.
///
///         Ported verbatim from `NFTBurnerV2.sol` (Sprint X v2.2, kept
///         on-chain as legacy per Sprint X v3 decision X3-19). Three deltas:
///
///         1. Event rename `NRGAwarded(..., uint256 totalNRG, ...)` →
///            `Accrued(..., uint256 totalEvnt, ...)`. Same 7-field shape
///            (LOW-07: explicit eraAtStart/eraAtEnd/totalBurnsAfter). Field
///            renamed from `totalNRG` to `totalEvnt`. Backend ABI counterpart
///            in `nft-energy-backend/src/lib/contracts.ts:evntBurnerAbi`
///            (Sprint X v3 §5.2).
///
///         2. Whitelist policy reverts to V1 mutual-exclusion (Sprint X v3
///            X3-11). A collection cannot be in BOTH the burn list and the
///            bluechip list simultaneously. Two NEW custom errors
///            `CollectionAlreadyBluechip(address)` /
///            `CollectionAlreadyBurn(address)` guard `addBurnCollection` /
///            `addBluechipCollection` against cross-membership. V2's
///            "orthogonal flags" semantics rescinded.
///
///         3. Symbol rename: `NFTBurnerV2` → `EvntBurner`. All `NRG`
///            references in comments / NatSpec → `EVNT`. Constants
///            `INITIAL_REWARD_BASE = 50 ether` / `HALVING_INTERVAL = 100_000`
///            / `BLUECHIP_BPS = 5000` UNCHANGED (Eugene-locked 2026-05-26
///            Sprint X v3 X3-7/X3-8/X3-9/X3-10). NAME / VERSION constants
///            reflect new identity.
///
/// @dev    Pragma `0.8.28` exact (matches Sprint X v2 + EvntClaimVault).
///         All Sprint X v2 hardening kept: Pausable + ReentrancyGuard +
///         MAX_BATCH=50 + EIP-1153 transient-storage dedup + ERC-165 sanity
///         check + {gas: 30_000} cap on external balanceOf/ownerOf calls +
///         try-ownerOf pre-check + transferFrom (NOT safeTransferFrom) +
///         halving era logic. Sentinel pre-impl review 2026-05-26 verdict
///         GREEN: no Critical/High blockers for this contract (EVAP3-M-01
///         / M-02 / L-01 / L-02 / L-03 are vault-side only).
contract EvntBurner is Ownable, Pausable, ReentrancyGuard {
    // ─── Identity ────────────────────────────────────────────────────────
    string public constant NAME = "EvntBurner";
    string public constant VERSION = "3.0.0";

    // ─── Constants ───────────────────────────────────────────────────────
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Burns per halving era (Bitcoin-style). Compile-time fixed
    ///         (Sprint X v3 X3-9, same as V2 X1=A).
    uint256 public constant HALVING_INTERVAL = 100_000;

    /// @notice Initial per-NFT base reward at era 0. Eugene-locked
    ///         2026-05-26 Sprint X v3 X3-8: 50 EVNT — identical to V2's 50
    ///         NRG. Cosmos pre-mainnet refresher 2026-05-22 verdict GREEN.
    uint256 public constant INITIAL_REWARD_BASE = 50 ether;

    /// @notice Bluechip multiplier in basis points (Sprint X v3 X3-10: 50%
    ///         bonus, never halves — applied AFTER per-NFT halving). Same
    ///         as V2 X3=A.
    uint256 public constant BLUECHIP_BPS = 5000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public constant MAX_BATCH = 50;
    uint256 public constant MAX_BLUECHIP_COLLECTIONS = 50;

    /// @dev ERC-165 interface id for IERC721
    bytes4 private constant _ERC721_INTERFACE_ID = 0x80ac58cd;

    // ─── Storage ─────────────────────────────────────────────────────────
    /// @notice Cumulative count of NFTs burned across all users since deploy.
    ///         Used as the era input: `era = totalBurns / HALVING_INTERVAL`.
    uint256 public totalBurns;

    mapping(address => bool) public isBurnCollection;
    address[] public burnCollections;
    mapping(address => uint256) private _burnIndex;

    mapping(address => bool) public isBluechipCollection;
    address[] public bluechipCollections;
    mapping(address => uint256) private _bluechipIndex;

    // ─── Events ──────────────────────────────────────────────────────────
    event NFTBurned(address indexed user, address indexed collection, uint256 indexed tokenId);

    /// @notice Sprint X v3 delta 1: renamed from `NRGAwarded` → `Accrued`.
    ///         Field `totalNRG` renamed `totalEvnt`. LOW-07 explicit
    ///         `eraAtStart` / `eraAtEnd` for cross-era batches; `totalBurnsAfter`
    ///         lets backend index without re-reading storage.
    ///         Backend ABI counterpart in
    ///         `nft-energy-backend/src/lib/contracts.ts:evntBurnerAbi`.
    event Accrued(
        address indexed user,
        uint256 burnedCount,
        uint256 bluechipCount,
        uint256 totalEvnt,
        uint256 eraAtStart,
        uint256 eraAtEnd,
        uint256 totalBurnsAfter
    );

    event BurnCollectionAdded(address indexed collection);
    event BurnCollectionRemoved(address indexed collection);
    event BluechipCollectionAdded(address indexed collection);
    event BluechipCollectionRemoved(address indexed collection);
    /// @dev Custom indexed pause events on top of OZ Pausable.
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ─── Custom Errors ───────────────────────────────────────────────────
    error NotWhitelisted(address collection);
    error BatchTooLarge(uint256 provided, uint256 max);
    error EmptyBatch();
    error ArrayLengthMismatch();
    error NotTokenOwner(address collection, uint256 tokenId);
    error AlreadyInBurnList(address collection);
    error AlreadyInBluechipList(address collection);
    error NotInBurnList(address collection);
    error NotInBluechipList(address collection);
    error BluechipListFull(uint256 max);
    error ZeroAddress();
    error InvalidCollection(address collection);
    /// @dev Same (collection, tokenId) appears more than once in the batch.
    error DuplicateInBatch(address collection, uint256 tokenId);
    /// @dev Collection does not look like ERC-721.
    error NotERC721(address collection);

    /// @dev Sprint X v3 delta 2 — V1-style mutual exclusion between burn
    ///      and bluechip whitelists (X3-11). A collection added to the
    ///      bluechip list cannot also be on the burn list, and vice versa.
    ///      The burn loop will still grant the 1.5× multiplier IF the
    ///      burned collection is also in the bluechip list — but per the
    ///      mutual-exclusion invariant that case is unreachable from
    ///      admin add-paths. Bluechip-flagged collections function as
    ///      ownership-signal collections (`getBluechipCount` view) rather
    ///      than burn-and-bonus collections in v3.
    error CollectionAlreadyBluechip(address collection);
    error CollectionAlreadyBurn(address collection);

    // ─── Constructor ─────────────────────────────────────────────────────
    /// @param initialOwner Address of the contract owner (admin role).
    ///                     Mainnet: Gnosis Safe (2-of-3 per architecture α).
    ///                     Testnet/local: EOA.
    /// @dev BHN-L-10 closure: defensive zero-address invariant on ctor input.
    ///      (OZ Ownable also reverts on address(0) with
    ///      OwnableInvalidOwner — this require is defense-in-depth.)
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "EvntBurner: zero owner");
    }

    // ─── Public / External ───────────────────────────────────────────────

    /// @notice Burn a batch of NFTs and earn EVNT via auto-halving.
    /// @dev    Per-NFT reward = `(INITIAL_REWARD_BASE >> era) × multiplier`,
    ///         where `era = (totalBurnsBefore + i) / HALVING_INTERVAL` (so a
    ///         batch crossing an era boundary mid-batch correctly applies the
    ///         lower reward to the post-boundary NFTs), and `multiplier =
    ///         (BPS_DENOMINATOR + BLUECHIP_BPS) / BPS_DENOMINATOR = 1.5` for
    ///         bluechip collections, `1.0` otherwise. Bluechip is determined
    ///         per-NFT by the collection's `isBluechipCollection` flag at
    ///         burn time. (Reverts on duplicate (collection, tokenId) within
    ///         the same batch via EIP-1153 transient storage.)
    ///
    ///         Note: this contract performs NO EVNT transfer. The Accrued
    ///         event is observed by the backend listener which signs +
    ///         broadcasts `EvntClaimVault.credit()` on Polygon (Sprint X
    ///         v3 §5.1). User EVNT lands in `pendingEvnt[user]` on Polygon
    ///         after 12-conf Eth reorg wait.
    /// @param  collections Array of NFT collection addresses (whitelisted).
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

        uint256 burnsBefore = totalBurns;
        uint256 totalEvnt;
        uint256 bluechipCount;

        for (uint256 i; i < len;) {
            address col = collections[i];
            uint256 tokenId = tokenIds[i];

            if (!isBurnCollection[col]) revert NotWhitelisted(col);

            // EIP-1153 transient duplicate guard. Each (col, tokenId) pair
            // gets a unique transient slot keyed by keccak256. Cleared
            // automatically at tx end (no manual cleanup, matches V1/V2).
            bytes32 key = keccak256(abi.encodePacked(col, tokenId));
            uint256 seen;
            assembly ("memory-safe") {
                seen := tload(key)
            }
            if (seen != 0) revert DuplicateInBatch(col, tokenId);
            assembly ("memory-safe") {
                tstore(key, 1)
            }

            // V1/V2 hardening: try ownerOf pre-check (uniform NotTokenOwner
            // revert for nonexistent tokenIds; OZ ERC721 reverts
            // ERC721NonexistentToken instead of returning address(0)).
            // {gas: 30_000} cap (BURN-L-02 closure) bounds griefing surface
            // from a misbehaving collection that consumes excess gas.
            IERC721 nft = IERC721(col);
            try nft.ownerOf{gas: 30_000}(tokenId) returns (address actual) {
                if (actual != msg.sender) revert NotTokenOwner(col, tokenId);
            } catch {
                revert NotTokenOwner(col, tokenId);
            }

            // V1/V2 hardening: transferFrom (NOT safeTransferFrom) — avoids
            // ERC721Received reentrancy hook on quirky-721 (MED-11). DEAD
            // address cannot have onERC721Received installed, so safe variant
            // would only add gas + reentrancy surface.
            nft.transferFrom(msg.sender, DEAD_ADDRESS, tokenId);

            emit NFTBurned(msg.sender, col, tokenId);

            // Per-NFT auto-halving (era boundaries respected mid-batch).
            // Bluechip multiplier applied AFTER halving (X3-10: never halves,
            // fixed +50%). Note: under v3 mutual-exclusion (X3-11) the
            // `bluechip` branch is effectively unreachable from on-chain
            // admin paths — burn loop preserves the math for forward-compat.
            uint256 era = (burnsBefore + i) / HALVING_INTERVAL;
            uint256 baseReward = INITIAL_REWARD_BASE >> era;

            bool bluechip = isBluechipCollection[col];
            uint256 reward = bluechip ? (baseReward * (BPS_DENOMINATOR + BLUECHIP_BPS)) / BPS_DENOMINATOR : baseReward;

            totalEvnt += reward;
            if (bluechip) {
                unchecked {
                    ++bluechipCount;
                }
            }

            unchecked {
                ++i;
            }
        }

        uint256 burnsAfter = burnsBefore + len;
        totalBurns = burnsAfter;

        // LOW-07: eraAtStart from `burnsBefore`; eraAtEnd from
        // `burnsAfter - 1` (era of the LAST burned NFT — same era as
        // eraAtStart unless batch crossed a boundary). For len >= 1 this is
        // safe because `burnsAfter >= 1`.
        emit Accrued(
            msg.sender,
            len,
            bluechipCount,
            totalEvnt,
            burnsBefore / HALVING_INTERVAL,
            (burnsAfter - 1) / HALVING_INTERVAL,
            burnsAfter
        );
    }

    /// @notice MED-08 fix: precise reward preview that respects in-batch era
    ///         progression. Frontend uses this for "you'll receive X EVNT"
    ///         display before burning. Soft-mode: a non-whitelisted entry
    ///         contributes 0 (silently) — for top-level shape errors
    ///         (oversize / empty), reverts.
    /// @dev    BHN-M-13 simplification: dropped redundant `batchSize`
    ///         (== collections.length) and unused `tokenIds` (preview does
    ///         not read tokenId state — owner check is intentionally NOT
    ///         performed here so the UI can quote pre-approval).
    /// @param  collections   Array of NFT collection addresses to preview.
    /// @return totalEvnt     Sum of per-NFT rewards across the batch.
    /// @return perNftReward  Per-NFT reward (length == collections.length).
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
            if (isBurnCollection[col]) {
                uint256 era = (burnsBefore + i) / HALVING_INTERVAL;
                uint256 baseReward = INITIAL_REWARD_BASE >> era;
                uint256 reward = isBluechipCollection[col]
                    ? (baseReward * (BPS_DENOMINATOR + BLUECHIP_BPS)) / BPS_DENOMINATOR
                    : baseReward;
                perNftReward[i] = reward;
                totalEvnt += reward;
            }
            // de-whitelisted collection → perNftReward[i] left as 0
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Current per-NFT base reward (no bluechip multiplier).
    /// @dev    Frontend HalvingProgress widget reads this for display.
    ///         Equivalent to `INITIAL_REWARD_BASE >> currentEra()`.
    /// @return Per-NFT base reward in wei EVNT.
    function currentRewardBase() external view returns (uint256) {
        return INITIAL_REWARD_BASE >> (totalBurns / HALVING_INTERVAL);
    }

    /// @notice Era display for HalvingProgress widget. Latest completed-batch
    ///         era. Equal to `floor(totalBurns / HALVING_INTERVAL)`.
    function currentEra() external view returns (uint256) {
        return totalBurns / HALVING_INTERVAL;
    }

    /// @notice Burns until next halving (era boundary). Returns
    ///         HALVING_INTERVAL when totalBurns == 0 (full era ahead).
    function burnsUntilNextHalving() external view returns (uint256) {
        return HALVING_INTERVAL - (totalBurns % HALVING_INTERVAL);
    }

    /// @notice Get all bluechip collection addresses
    function getBluechipCollections() external view returns (address[] memory) {
        return bluechipCollections;
    }

    /// @notice Get all burn-whitelisted collection addresses
    function getBurnCollections() external view returns (address[] memory) {
        return burnCollections;
    }

    /// @notice Count how many bluechip collections the user holds tokens
    ///         from (informational view, not used in reward math). Fail-soft
    ///         with {gas: 30_000} cap (BURN-L-02 closure) — a single broken
    ///         collection does NOT brick the call.
    function getBluechipCount(address user) external view returns (uint256) {
        return _countBluechips(user);
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Add a collection to the burn whitelist.
    /// @dev Sprint X v3 X3-11 mutual-exclusion: reverts
    ///      `CollectionAlreadyBluechip` if the collection is already in
    ///      the bluechip list. Remove from bluechip first, then re-add to
    ///      burn (or vice versa) if classification changes.
    function addBurnCollection(address collection) external onlyOwner {
        if (collection == address(0)) revert ZeroAddress();
        if (collection == DEAD_ADDRESS || collection == address(this)) {
            revert InvalidCollection(collection);
        }
        if (isBurnCollection[collection]) revert AlreadyInBurnList(collection);
        // Sprint X v3 delta 2 — V1-style mutual exclusion.
        if (isBluechipCollection[collection]) revert CollectionAlreadyBluechip(collection);
        _validateIsERC721(collection);

        isBurnCollection[collection] = true;
        _burnIndex[collection] = burnCollections.length;
        burnCollections.push(collection);

        emit BurnCollectionAdded(collection);
    }

    /// @notice Remove a collection from the burn whitelist.
    function removeBurnCollection(address collection) external onlyOwner {
        if (!isBurnCollection[collection]) revert NotInBurnList(collection);

        isBurnCollection[collection] = false;

        // Swap-and-pop
        uint256 idx = _burnIndex[collection];
        uint256 lastIdx = burnCollections.length - 1;
        if (idx != lastIdx) {
            address last = burnCollections[lastIdx];
            burnCollections[idx] = last;
            _burnIndex[last] = idx;
        }
        burnCollections.pop();
        delete _burnIndex[collection];

        emit BurnCollectionRemoved(collection);
    }

    /// @notice Add a collection to the bluechip list (gives 1.5× reward).
    /// @dev Sprint X v3 X3-11 mutual-exclusion: reverts
    ///      `CollectionAlreadyBurn` if the collection is already in the
    ///      burn list.
    function addBluechipCollection(address collection) external onlyOwner {
        if (collection == address(0)) revert ZeroAddress();
        if (collection == DEAD_ADDRESS || collection == address(this)) {
            revert InvalidCollection(collection);
        }
        if (isBluechipCollection[collection]) revert AlreadyInBluechipList(collection);
        // Sprint X v3 delta 2 — V1-style mutual exclusion.
        if (isBurnCollection[collection]) revert CollectionAlreadyBurn(collection);
        if (bluechipCollections.length >= MAX_BLUECHIP_COLLECTIONS) {
            revert BluechipListFull(MAX_BLUECHIP_COLLECTIONS);
        }
        _validateIsERC721(collection);

        isBluechipCollection[collection] = true;
        _bluechipIndex[collection] = bluechipCollections.length;
        bluechipCollections.push(collection);

        emit BluechipCollectionAdded(collection);
    }

    /// @notice Remove a collection from the bluechip list.
    function removeBluechipCollection(address collection) external onlyOwner {
        if (!isBluechipCollection[collection]) revert NotInBluechipList(collection);

        isBluechipCollection[collection] = false;

        // Swap-and-pop
        uint256 idx = _bluechipIndex[collection];
        uint256 lastIdx = bluechipCollections.length - 1;
        if (idx != lastIdx) {
            address last = bluechipCollections[lastIdx];
            bluechipCollections[idx] = last;
            _bluechipIndex[last] = idx;
        }
        bluechipCollections.pop();
        delete _bluechipIndex[collection];

        emit BluechipCollectionRemoved(collection);
    }

    /// @notice Pause the contract (disables burnBatch).
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
    ///         DEAD_ADDRESS) or burn flow.
    /// @param  token  ERC-20 token contract.
    /// @param  to     Destination wallet.
    /// @param  amount Amount to rescue (in token base units).
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        // Use raw call so a missing return-value (non-standard ERC-20) does
        // not brick rescue. SafeERC20 not imported to keep parity with V2 ABI
        // surface.
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "EvntBurner: rescue failed");
        emit TokensRescued(token, to, amount);
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Count how many bluechip collections `user` holds at least 1
    ///      token from. Fail-soft: a single broken collection (revert on
    ///      balanceOf) is skipped instead of bricking the call. Owner can
    ///      drop it via `removeBluechipCollection`. {gas: 30_000} cap caps
    ///      griefing surface from a misbehaving bluechip (BURN-L-02
    ///      closure). 30k gas covers an honest ERC-721 (typical 2.5–5k
    ///      SLOAD) with wide margin.
    function _countBluechips(address user) internal view returns (uint256 count) {
        address[] memory bcs = bluechipCollections;
        uint256 len = bcs.length;
        for (uint256 i; i < len;) {
            try IERC721(bcs[i]).balanceOf{gas: 30_000}(user) returns (uint256 bal) {
                if (bal > 0) {
                    unchecked {
                        ++count;
                    }
                }
            } catch {
                // skip broken collection — fail-soft semantic
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Validate that `collection` looks like an ERC-721. Three-tier
    ///      check (verbatim from V1/V2):
    ///      1. The address must have code (rules out EOAs).
    ///      2. ERC-165 supportsInterface(0x80ac58cd) — preferred path.
    ///      3. Legacy fallback via `balanceOf(0xdEaD)` for ERC-721s
    ///         predating ERC-165.
    ///      Reverts with NotERC721 if none of these pass.
    function _validateIsERC721(address collection) internal view {
        if (collection.code.length == 0) revert NotERC721(collection);

        try IERC165(collection).supportsInterface(_ERC721_INTERFACE_ID) returns (bool ok) {
            if (ok) return;
            // ERC-165 explicitly says "no" → reject
            revert NotERC721(collection);
        } catch {
            // Legacy ERC-721 without ERC-165 — try balanceOf as a sanity check
            try IERC721(collection).balanceOf(DEAD_ADDRESS) returns (
                uint256
            ) {
            // accept
            }
            catch {
                revert NotERC721(collection);
            }
        }
    }
}
