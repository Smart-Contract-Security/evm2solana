// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {OwnableBasic} from "@limitbreak/creator-token-standards/access/OwnableBasic.sol";
import {OwnablePermissions} from "@limitbreak/creator-token-standards/access/OwnablePermissions.sol";
import {ERC721C} from "@limitbreak/creator-token-standards/erc721c/ERC721C.sol";
import {ERC721OpenZeppelin} from "@limitbreak/creator-token-standards/token/erc721/ERC721OpenZeppelin.sol";
import {BasicRoyalties} from "@limitbreak/creator-token-standards/programmable-royalties/BasicRoyalties.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {AbnormiesRenderer} from "./AbnormiesRenderer.sol";
import {INormies} from "./interfaces/INormies.sol";
import {INormiesCanvasStorage} from "./interfaces/INormiesCanvasStorage.sol";
import {IAdapter8004, TokenStandard} from "./interfaces/IAdapter8004.sol";
import {IDelegateRegistry} from "./interfaces/IDelegateRegistry.sol";

contract Abnormies is OwnableBasic, ERC721C, BasicRoyalties {
    uint96 public constant ROYALTY_FEE_NUMERATOR = 250;
    uint64 public constant PHASE_1_DURATION = 2 days;
    uint64 public constant FALLBACK_REVEAL_DELAY = 14 days;
    uint256 public constant MAX_SUPPLY = 10_000;

    uint256 public constant MINT_PRICE = 0.005 ether;
    uint256 public constant PHASE2_MAX_PER_CALL = 50;

    // Seal-then-commit-then-reveal. Receipts are frozen first (sealed); only afterwards is a fixed
    // window of future block hashes — unknown and unchosen at seal time — mixed into the reveal
    // seed. Because the seal happens before the entropy blocks exist, no one can simulate future
    // receipts' outcomes while Phase 2 is still open. REVEAL_DELAY_BLOCKS gaps the seal from the
    // first entropy block so the seal-tx proposer cannot also be the first entropy proposer.
    // Mixing REVEAL_BLOCK_COUNT consecutive blockhashes removes any single intermediate
    // proposer's influence, but does NOT fully eliminate proposer bias: the proposer of the last
    // entropy block can compute the resulting seed before publishing and withhold that block for
    // one conditional reroll, at the cost of forfeiting its MEV. The manipulation surface is
    // therefore ~(proposer share) x (block MEV) per reveal — a single reroll attempt — not
    // (proposer share)^N. That residual bias is acceptable for this project at 0.005 ETH/mint and
    // a ~30 ETH pot. REVEAL_EXPIRY_BLOCKS keeps the whole window inside the 256-block blockhash
    // horizon; past it, reveal() can no longer read the hashes and reseal() restarts from the
    // current block.
    uint256 public constant REVEAL_DELAY_BLOCKS = 8;
    uint256 public constant REVEAL_BLOCK_COUNT = 4;
    uint256 public constant REVEAL_EXPIRY_BLOCKS = 240;

    address public constant NORMIES = 0x9Eb6E2025B64f340691e424b7fe7022fFDE12438;
    address public constant NORMIES_CANVAS_STORAGE = 0xC255BE0983776BAB027a156681b6925cde47B2D1;
    address public constant ADAPTER8004 = 0xde152AfB7db5373F34876E1499fbD893A82dD336;

    // delegate.xyz v2 registry. Same address across mainnet, Sepolia, and all major L2s.
    address public constant DELEGATE_REGISTRY = 0x00000000000000447e69651d841bD8D104Bed493;

    bytes32 public immutable SNAPSHOT_ROOT;
    AbnormiesRenderer public immutable renderer;
    uint64 public immutable deployedAt;
    address public immutable treasury;

    struct Receipt {
        address claimant;
        uint16 normieId;
        bool fromPhase1;
        bool snapshotCustomized;
        bool resolved;
        uint16 abnormieId;
    }

    struct AbnormieState {
        uint16 seedNormieId;
        uint64 staticAt;
        address frozenBy;
        uint8 freezeAction;
        bool seedDeadAtFreeze;
        uint32 pairedAtCascadeIndex;
        uint32 staticAtCascadeIndex;
        uint16 cirrusCountAtFreeze;
        bool seedCustomizedAtFreeze;
        uint64 seedDeadAtBlockAtFreeze;
        bool paired;
    }

    struct Cascade {
        uint64 blockNumber;
        uint16 burnedTokenId;
        uint16 freezeTargetTokenId;
        uint8 action;
        uint8 thunderSize;
    }

    Receipt[] public receipts;
    mapping(uint256 => bool) public claimed;
    mapping(uint256 => AbnormieState) public abnormieState;

    mapping(uint256 => address) public lastObservedSeedOwner;
    mapping(uint256 => uint16) public cirrusCount;
    mapping(uint256 => bool) public seedCustomized;
    mapping(uint256 => bool) public seedBurned;
    mapping(uint256 => uint64) public seedDeadAtBlock;
    mapping(uint256 => bool) public seedAwakened;
    mapping(uint256 => uint256) public boundAgentId;

    Cascade[] public cascadeLog;
    uint16 public firstStaticTokenId;
    bool public firstStaticSet;

    uint256[MAX_SUPPLY] private _unclaimedIds;
    uint256 public unclaimedCount = MAX_SUPPLY;

    uint8 public phase;
    uint64 public phase1ClosedAt;
    uint64 public sealedAtBlock;
    bool public isSealed;
    uint256 public revealSeed;
    bool public revealed;
    uint256 public nextResolveIndex;
    uint256 public phase1ReceiptCount;
    uint256 public phase2ReceiptCount;

    uint256 public phase2RemainingSlots;

    mapping(uint256 => uint256) private _phase2NormiePool;
    uint256 public phase2NormiePoolSize;

    event Phase1Claimed(address indexed claimant, uint256 indexed normieId, bool customized);
    event Phase1Closed(uint256 receiptCount);
    event Sealed(uint64 sealedAtBlock, uint256 receiptCount);
    event Resealed(uint64 sealedAtBlock);
    event Revealed(uint256 seed, uint256 blockNumber);
    event AbnormiePaired(uint256 indexed abnormieId, uint256 indexed normieId, address indexed claimant);

    event CirrusObserved(uint256 indexed normieId, address indexed newOwner, uint16 cirrusCount);
    event SeedCustomized(uint256 indexed normieId);
    event SeedBurned(uint256 indexed normieId);
    event SeedAwakened(uint256 indexed normieId, uint256 indexed agentId);

    event Thundered(
        uint256 indexed burnedTokenId, uint256 indexed freezeTargetTokenId, address indexed burner, uint256 cascadeIndex
    );
    event Lightninged(
        uint256 indexed burnedTokenId, uint256 indexed freezeTargetTokenId, address indexed burner, uint256 cascadeIndex
    );
    event AbnormieFrozen(uint256 indexed tokenId, address indexed by, uint8 action, uint64 atBlock, bool firstStatic);

    event Phase2Minted(address indexed claimant, uint256 firstReceiptIndex, uint256 count);
    event AirdropMinted(address indexed recipient, uint256 count, uint256 startReceiptIndex, uint256 endReceiptIndex);

    event TreasuryWithdrawal(address indexed treasury, uint256 amount);

    error NotOwner();
    error InvalidTreasury();
    error WithdrawalFailed();
    error PhaseNotOpen();
    error Phase1Ended();
    error Phase1NotEnded();
    error LengthMismatch();
    error InvalidProof();
    error InvalidDelegation();
    error AlreadyClaimed(uint256 normieId);
    error OutOfRangeNormieId(uint256 normieId);
    error ResolveBeforeReveal();
    error FallbackRevealTooEarly();
    error PhaseSealed();
    error NotSealed();
    error AlreadyRevealed();
    error RevealBlocksNotReady(uint256 needBlock);
    error BlockhashUnavailable(uint256 blockNumber);
    error RevealExpired();
    error CannotReseal();
    error EmptyRange();
    error AlreadyAwakened();
    error WrongBindingStandard();
    error WrongBindingContract();
    error WrongBindingTokenId();
    error NotActive(uint256 tokenId);
    error SelfFreezeForbidden();
    error SeedStillLiving();
    error SeedNotCustomized();
    error SeedDead();
    error WrongMintPrice();
    error MaxPerCallExceeded();
    error SoldOut();
    error InvalidRecipient();

    constructor(bytes32 snapshotRoot, address royaltyReceiver, address treasury_, address renderer_)
        ERC721OpenZeppelin("Abnormies", "ABNORMIES")
        BasicRoyalties(royaltyReceiver, ROYALTY_FEE_NUMERATOR)
    {
        if (treasury_ == address(0)) revert InvalidTreasury();

        SNAPSHOT_ROOT = snapshotRoot;
        treasury = treasury_;
        renderer = AbnormiesRenderer(renderer_);
        deployedAt = uint64(block.timestamp);
    }

    function withdraw() external {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        (bool ok,) = treasury.call{value: balance}("");
        if (!ok) revert WithdrawalFailed();
        emit TreasuryWithdrawal(treasury, balance);
    }

    // -----------------------------------------------------------------------
    // Phase 1: claim + close
    // -----------------------------------------------------------------------

    /// @notice Create Phase 1 receipts for claimed Normies, each proven against the snapshot root.
    /// @dev Two paths, selected by `vault`:
    ///      - Direct (`vault == address(0)`): `claimant = msg.sender`. Each leaf is verified against
    ///        `msg.sender` and receipts are credited to `msg.sender`.
    ///      - Delegated (`vault != address(0)`): the caller must be an authorized delegate for
    ///        `vault` per delegate.xyz v2 — `checkDelegateForContract(msg.sender, vault, this, 0)`,
    ///        where `rights == bytes32(0)` matches both an "all" delegation and one scoped to this
    ///        contract. On success `claimant = vault`: leaves are verified against `vault` and
    ///        receipts are credited to `vault`, letting a hot wallet claim for the cold vault that
    ///        actually held the Normies at snapshot. Reverts `InvalidDelegation` if not authorized.
    function claim(
        uint256[] calldata normieIds,
        bool[] calldata customizedFlags,
        bytes32[][] calldata proofs,
        address vault
    ) external {
        if (phase != 0) revert PhaseNotOpen();
        if (block.timestamp >= deployedAt + PHASE_1_DURATION) revert Phase1Ended();

        uint256 n = normieIds.length;
        if (customizedFlags.length != n || proofs.length != n) revert LengthMismatch();

        // Resolve the address the receipts are credited to and proven against.
        address claimant = msg.sender;
        if (vault != address(0)) {
            if (!IDelegateRegistry(DELEGATE_REGISTRY)
                    .checkDelegateForContract(msg.sender, vault, address(this), bytes32(0))) {
                revert InvalidDelegation();
            }
            claimant = vault;
        }

        for (uint256 i = 0; i < n;) {
            uint256 normieId = normieIds[i];
            bool customized = customizedFlags[i];

            // Guard against a malformed snapshot root carrying an out-of-range id. The valid
            // Normie range is 0..MAX_SUPPLY-1; anything at MAX_SUPPLY or above can never pair and
            // would overflow the uint16 receipt field.
            require(normieId < MAX_SUPPLY, OutOfRangeNormieId(normieId));
            if (claimed[normieId]) revert AlreadyClaimed(normieId);

            // Double-hashed leaf encoding matches OpenZeppelin's StandardMerkleTree (used by
            // `snapshot/build.ts`). The outer keccak protects against second-preimage attacks on
            // intermediate tree nodes; the inner keccak is the leaf-value commitment that the
            // proof verifies against.
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(normieId, claimant, customized))));
            if (!MerkleProof.verify(proofs[i], SNAPSHOT_ROOT, leaf)) revert InvalidProof();

            claimed[normieId] = true;
            receipts.push(
                Receipt({
                    claimant: claimant,
                    normieId: uint16(normieId),
                    fromPhase1: true,
                    snapshotCustomized: customized,
                    resolved: false,
                    abnormieId: 0
                })
            );
            phase1ReceiptCount += 1;

            emit Phase1Claimed(claimant, normieId, customized);

            unchecked {
                ++i;
            }
        }
    }

    function closePhase1() external {
        if (phase != 0) revert PhaseNotOpen();
        if (block.timestamp < deployedAt + PHASE_1_DURATION) revert Phase1NotEnded();

        phase = 1;
        phase1ClosedAt = uint64(block.timestamp);
        phase2RemainingSlots = MAX_SUPPLY - phase1ReceiptCount;
        phase2NormiePoolSize = MAX_SUPPLY;

        // No entropy is committed here. Phase 2 stays open and receipts accumulate; the commitment
        // to randomness happens only at seal time, so no one can simulate outcomes for receipts
        // that don't exist yet.
        emit Phase1Closed(phase1ReceiptCount);
    }

    // -----------------------------------------------------------------------
    // Phase 2: paid mints, owner airdrops, reveal, resolve
    // -----------------------------------------------------------------------

    function mintPhase2(uint256 count) external payable {
        if (phase != 1 || revealed) revert PhaseNotOpen();
        if (isSealed) revert PhaseSealed();
        if (count == 0 || count > PHASE2_MAX_PER_CALL) revert MaxPerCallExceeded();
        if (msg.value != count * MINT_PRICE) revert WrongMintPrice();
        if (phase2RemainingSlots < count) revert SoldOut();

        uint256 start = receipts.length;
        phase2RemainingSlots -= count;

        for (uint256 i = 0; i < count;) {
            receipts.push(
                Receipt({
                    claimant: msg.sender,
                    normieId: 0,
                    fromPhase1: false,
                    snapshotCustomized: false,
                    resolved: false,
                    abnormieId: 0
                })
            );
            unchecked {
                ++i;
            }
        }
        phase2ReceiptCount += count;

        emit Phase2Minted(msg.sender, start, count);
        _maybeAutoSeal();
    }

    function airdrop(address recipient, uint256 count) external {
        _requireCallerIsContractOwner();
        if (phase != 1 || revealed) revert PhaseNotOpen();
        if (isSealed) revert PhaseSealed();
        if (recipient == address(0)) revert InvalidRecipient();
        if (count == 0 || count > PHASE2_MAX_PER_CALL) revert MaxPerCallExceeded();
        if (phase2RemainingSlots < count) revert SoldOut();

        uint256 start = receipts.length;
        phase2RemainingSlots -= count;

        for (uint256 i = 0; i < count;) {
            receipts.push(
                Receipt({
                    claimant: recipient,
                    normieId: 0,
                    fromPhase1: false,
                    snapshotCustomized: false,
                    resolved: false,
                    abnormieId: 0
                })
            );
            unchecked {
                ++i;
            }
        }
        phase2ReceiptCount += count;

        emit AirdropMinted(recipient, count, start, receipts.length);
        _maybeAutoSeal();
    }

    /// @notice Permissionless seal trigger for the fallback path. Freezes the receipt list so the
    ///         reveal window can begin. Auto-seal already fires inline when supply is exhausted via
    ///         mint/airdrop; this is the safety net if Phase 2 stalls below capacity — callable
    ///         once `phase1ClosedAt + FALLBACK_REVEAL_DELAY` has elapsed. Any remaining Phase 2
    ///         slots are stranded: after seal, no further mints or airdrops are accepted.
    function sealForReveal() external {
        if (isSealed) revert PhaseSealed();
        if (phase != 1 || revealed) revert PhaseNotOpen();
        bool soldOut = phase2RemainingSlots == 0;
        bool late = block.timestamp >= uint256(phase1ClosedAt) + FALLBACK_REVEAL_DELAY;
        if (!soldOut && !late) revert FallbackRevealTooEarly();
        _seal();
    }

    /// @notice Permissionless reveal. Mixes the hashes of REVEAL_BLOCK_COUNT consecutive blocks
    ///         starting at `sealedAtBlock + REVEAL_DELAY_BLOCKS` into the seed. Callable once all
    ///         those blocks are mined (and far enough back that they're stable) but before the
    ///         blockhash window expires. Past expiry, reseal() must restart the window first.
    function reveal() external {
        if (!isSealed) revert NotSealed();
        if (revealed) revert AlreadyRevealed();

        uint256 firstBlock = uint256(sealedAtBlock) + REVEAL_DELAY_BLOCKS;
        uint256 readyBlock = firstBlock + REVEAL_BLOCK_COUNT;
        if (block.number <= readyBlock) revert RevealBlocksNotReady(readyBlock);
        if (block.number > uint256(sealedAtBlock) + REVEAL_EXPIRY_BLOCKS) revert RevealExpired();

        bytes32 seed;
        for (uint256 i = 0; i < REVEAL_BLOCK_COUNT;) {
            uint256 target = firstBlock + i;
            bytes32 h = blockhash(target);
            if (h == bytes32(0)) revert BlockhashUnavailable(target);
            seed = keccak256(abi.encode(seed, h));
            unchecked {
                ++i;
            }
        }

        revealSeed = uint256(seed);
        revealed = true;
        phase = 2;
        emit Revealed(revealSeed, block.number);
    }

    /// @notice Restart the reveal window when the prior seal aged out of the 256-block blockhash
    ///         horizon (the practical case being the 14-day fallback, where the entropy blocks are
    ///         long unreadable by the time anyone calls reveal). Only moves `sealedAtBlock`; the
    ///         frozen receipt list is untouched.
    function reseal() external {
        if (!isSealed) revert NotSealed();
        if (revealed) revert AlreadyRevealed();
        if (block.number <= uint256(sealedAtBlock) + REVEAL_EXPIRY_BLOCKS) revert CannotReseal();
        sealedAtBlock = uint64(block.number);
        emit Resealed(sealedAtBlock);
    }

    function _maybeAutoSeal() internal {
        if (isSealed || revealed) return;
        if (phase != 1) return;
        if (phase2RemainingSlots != 0) return;
        _seal();
    }

    function _seal() internal {
        isSealed = true;
        sealedAtBlock = uint64(block.number);
        emit Sealed(sealedAtBlock, receipts.length);
    }

    function resolveReceipts(uint256 count) external {
        if (!revealed) revert ResolveBeforeReveal();
        if (count == 0) return;

        uint256 receiptCount = receipts.length;
        uint256 start = nextResolveIndex;
        if (start >= receiptCount) return;

        uint256 remaining = receiptCount - start;
        if (count > remaining) count = remaining;
        uint256 end = start + count;

        for (uint256 i = start; i < end;) {
            Receipt storage r = receipts[i];
            if (!r.resolved) {
                uint256 abnormieId = _pickAndPop(uint256(keccak256(abi.encode(revealSeed, i))) % unclaimedCount);
                uint256 normieId = r.fromPhase1
                    ? uint256(r.normieId)
                    : _pickNormieIdForPhase2(uint256(keccak256(abi.encode(revealSeed, i, "norm"))));

                r.abnormieId = uint16(abnormieId);
                r.normieId = uint16(normieId);
                r.resolved = true;

                _mint(r.claimant, abnormieId);
                AbnormieState storage st = abnormieState[abnormieId];
                st.seedNormieId = uint16(normieId);
                st.pairedAtCascadeIndex = uint32(cascadeLog.length);
                st.paired = true;

                if (r.fromPhase1) {
                    lastObservedSeedOwner[normieId] = r.claimant;
                    if (r.snapshotCustomized) {
                        seedCustomized[normieId] = true;
                    }
                } else {
                    _snapshotSeedAtPairing(normieId);
                }

                emit AbnormiePaired(abnormieId, normieId, r.claimant);
            }

            unchecked {
                ++i;
            }
        }

        nextResolveIndex = end;
    }

    function _pickAndPop(uint256 index) internal returns (uint256 abnormieId) {
        uint256 lastIndex = unclaimedCount - 1;

        uint256 picked = _unclaimedIds[index];
        abnormieId = picked == 0 ? index + 1 : picked;

        if (index != lastIndex) {
            uint256 lastStored = _unclaimedIds[lastIndex];
            _unclaimedIds[index] = lastStored == 0 ? lastIndex + 1 : lastStored;
        }

        unclaimedCount = lastIndex;
    }

    function _pickNormieIdForPhase2(uint256 seedBase) internal returns (uint256 normieId) {
        // Pool spans Normie ids 0..MAX_SUPPLY-1 inclusive (matches the live Normies token range:
        // 0 exists, 9999 exists, 10000 does not). Slot encoding stores (candidate + 1) so a
        // raw 0 in the mapping unambiguously means "uninitialised; natural value = r" rather
        // than the literal candidate 0.
        uint256 attempt = 0;
        while (true) {
            uint256 size = phase2NormiePoolSize;
            uint256 r = uint256(keccak256(abi.encode(seedBase, attempt))) % size;

            uint256 stored = _phase2NormiePool[r];
            uint256 candidate = stored == 0 ? r : stored - 1;

            uint256 lastIdx = size - 1;
            if (r != lastIdx) {
                uint256 lastStored = _phase2NormiePool[lastIdx];
                uint256 lastCandidate = lastStored == 0 ? lastIdx : lastStored - 1;
                _phase2NormiePool[r] = lastCandidate + 1;
            }
            phase2NormiePoolSize = lastIdx;

            if (claimed[candidate]) {
                unchecked {
                    ++attempt;
                }
                continue;
            }
            claimed[candidate] = true;
            return candidate;
        }
    }

    function _snapshotSeedAtPairing(uint256 normieId) internal {
        try INormiesCanvasStorage(NORMIES_CANVAS_STORAGE).isTransformed(normieId) returns (bool transformed) {
            if (transformed) {
                seedCustomized[normieId] = true;
            }
        } catch {}
        try INormies(NORMIES).ownerOf(normieId) returns (address o) {
            if (o == address(0)) {
                _markSeedBurned(normieId);
            } else {
                lastObservedSeedOwner[normieId] = o;
            }
        } catch {
            _markSeedBurned(normieId);
        }
    }

    function _markSeedBurned(uint256 normieId) internal {
        if (seedBurned[normieId]) return;
        seedBurned[normieId] = true;
        seedDeadAtBlock[normieId] = uint64(block.number);
        emit SeedBurned(normieId);
    }

    // -----------------------------------------------------------------------
    // Pokes
    // -----------------------------------------------------------------------

    function pokeSeed(uint256 normieId) external {
        _pokeSeed(normieId);
    }

    function pokeMany(uint256[] calldata normieIds) external {
        uint256 n = normieIds.length;
        for (uint256 i = 0; i < n;) {
            _pokeSeed(normieIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function pokeAwakening(uint256 normieId, uint256 agentId) external {
        if (seedAwakened[normieId]) revert AlreadyAwakened();

        IAdapter8004.Binding memory binding = IAdapter8004(ADAPTER8004).bindingOf(agentId);
        if (binding.standard != TokenStandard.ERC721) revert WrongBindingStandard();
        if (binding.tokenContract != NORMIES) revert WrongBindingContract();
        if (binding.tokenId != normieId) revert WrongBindingTokenId();

        seedAwakened[normieId] = true;
        boundAgentId[normieId] = agentId;

        emit SeedAwakened(normieId, agentId);
    }

    function _pokeSeed(uint256 normieId) internal {
        if (seedBurned[normieId]) {
            return;
        }

        address currentOwner;
        try INormies(NORMIES).ownerOf(normieId) returns (address o) {
            currentOwner = o;
        } catch {
            _markSeedBurned(normieId);
            return;
        }
        if (currentOwner == address(0)) {
            _markSeedBurned(normieId);
            return;
        }

        address last = lastObservedSeedOwner[normieId];
        if (last == address(0)) {
            lastObservedSeedOwner[normieId] = currentOwner;
        } else if (currentOwner != last) {
            uint16 current = cirrusCount[normieId];
            uint16 next = current;
            if (current < type(uint16).max) {
                next = current + 1;
                cirrusCount[normieId] = next;
            }
            lastObservedSeedOwner[normieId] = currentOwner;
            emit CirrusObserved(normieId, currentOwner, next);
        }

        if (!seedCustomized[normieId]) {
            try INormiesCanvasStorage(NORMIES_CANVAS_STORAGE).isTransformed(normieId) returns (bool transformed) {
                if (transformed) {
                    seedCustomized[normieId] = true;
                    emit SeedCustomized(normieId);
                }
            } catch {}
        }
    }

    // -----------------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------------

    function thunder(uint256 burnTokenId, uint256 freezeTargetTokenId) external {
        if (phase < 2) revert PhaseNotOpen();
        if (ownerOf(burnTokenId) != msg.sender) revert NotOwner();

        AbnormieState storage burnState = abnormieState[burnTokenId];
        if (burnState.staticAt != 0) revert NotActive(burnTokenId);

        uint256 seedId = burnState.seedNormieId;
        if (!seedBurned[seedId]) {
            _pokeSeed(seedId);
        }
        if (!seedBurned[seedId]) revert SeedStillLiving();

        _requireFreezeTargetEligible(freezeTargetTokenId);

        uint256 cascadeIndex = _freezeAndCascade(burnTokenId, freezeTargetTokenId, 1);

        emit Thundered(burnTokenId, freezeTargetTokenId, msg.sender, cascadeIndex);
    }

    function lightning(uint256 burnTokenId, uint256 freezeTargetTokenId) external {
        if (phase < 2) revert PhaseNotOpen();
        if (ownerOf(burnTokenId) != msg.sender) revert NotOwner();

        AbnormieState storage burnState = abnormieState[burnTokenId];
        if (burnState.staticAt != 0) revert NotActive(burnTokenId);

        uint256 seedId = burnState.seedNormieId;
        _pokeSeed(seedId);
        if (seedBurned[seedId]) revert SeedDead();
        if (!seedCustomized[seedId]) revert SeedNotCustomized();

        _requireFreezeTargetEligible(freezeTargetTokenId);

        uint256 cascadeIndex = _freezeAndCascade(burnTokenId, freezeTargetTokenId, 2);

        emit Lightninged(burnTokenId, freezeTargetTokenId, msg.sender, cascadeIndex);
    }

    function _requireFreezeTargetEligible(uint256 freezeTargetTokenId) internal view {
        address freezeOwner = ownerOf(freezeTargetTokenId);
        if (freezeOwner == msg.sender) revert SelfFreezeForbidden();
        if (abnormieState[freezeTargetTokenId].staticAt != 0) revert NotActive(freezeTargetTokenId);
    }

    function _freezeAndCascade(uint256 burnTokenId, uint256 freezeTargetTokenId, uint8 action)
        internal
        returns (uint256 cascadeIndex)
    {
        AbnormieState storage targetState = abnormieState[freezeTargetTokenId];
        uint256 targetSeedId = targetState.seedNormieId;
        uint64 atBlock = uint64(block.number);

        _pokeSeed(targetSeedId);

        targetState.staticAt = atBlock;
        targetState.frozenBy = msg.sender;
        targetState.freezeAction = action;
        targetState.seedDeadAtFreeze = seedBurned[targetSeedId];
        targetState.cirrusCountAtFreeze = cirrusCount[targetSeedId];
        targetState.seedCustomizedAtFreeze = seedCustomized[targetSeedId];
        targetState.seedDeadAtBlockAtFreeze = seedDeadAtBlock[targetSeedId];
        targetState.staticAtCascadeIndex = uint32(cascadeLog.length);

        bool firstStatic = !firstStaticSet;
        if (firstStatic) {
            firstStaticTokenId = uint16(freezeTargetTokenId);
            firstStaticSet = true;
        }

        emit AbnormieFrozen(freezeTargetTokenId, msg.sender, action, atBlock, firstStatic);

        cascadeLog.push(
            Cascade({
                blockNumber: atBlock,
                burnedTokenId: uint16(burnTokenId),
                freezeTargetTokenId: uint16(freezeTargetTokenId),
                action: action,
                thunderSize: 0
            })
        );
        cascadeIndex = cascadeLog.length - 1;

        _burn(burnTokenId);
    }

    function cascadeLogLength() external view returns (uint256) {
        return cascadeLog.length;
    }

    function getAllCascades() external view returns (Cascade[] memory) {
        return cascadeLog;
    }

    function getCascade(uint256 index) external view returns (Cascade memory) {
        return cascadeLog[index];
    }

    function getAbnormieState(uint256 abnormieId) external view returns (AbnormieState memory) {
        return abnormieState[abnormieId];
    }

    function getSeedState(uint256 normieId)
        external
        view
        returns (address lastOwner, uint16 cirrus, bool customized, bool burned, bool awakened, uint256 boundAgent)
    {
        return (
            lastObservedSeedOwner[normieId],
            cirrusCount[normieId],
            seedCustomized[normieId],
            seedBurned[normieId],
            seedAwakened[normieId],
            boundAgentId[normieId]
        );
    }

    // -----------------------------------------------------------------------
    // Hooks + utility
    // -----------------------------------------------------------------------

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override
    {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        if (from == address(0)) return;
        for (uint256 i = 0; i < batchSize;) {
            uint256 tokenId = firstTokenId + i;
            // Gate on `paired`, not `seedNormieId != 0`: an Abnormie legitimately paired with
            // Normie 0 has seedNormieId == 0 and must still auto-poke its seed on transfer.
            AbnormieState storage state = abnormieState[tokenId];
            if (state.paired) {
                _pokeSeed(state.seedNormieId);
            }
            unchecked {
                ++i;
            }
        }
    }

    function receiptsLength() external view returns (uint256) {
        return receipts.length;
    }

    function receiptAt(uint256 index)
        external
        view
        returns (
            address claimant,
            uint16 normieId,
            bool fromPhase1,
            bool snapshotCustomized,
            bool resolved,
            uint16 abnormieId
        )
    {
        Receipt storage r = receipts[index];
        return (r.claimant, r.normieId, r.fromPhase1, r.snapshotCustomized, r.resolved, r.abnormieId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        return renderer.tokenURI(tokenId);
    }

    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function _requireCallerIsContractOwner() internal view virtual override(OwnableBasic, OwnablePermissions) {
        if (msg.sender != owner()) revert NotOwner();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, ERC2981) returns (bool) {
        return ERC721C.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}
