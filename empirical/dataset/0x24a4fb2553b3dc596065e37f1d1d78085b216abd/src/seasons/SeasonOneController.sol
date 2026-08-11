// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin-v5/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {ISeasonController} from "../interfaces/ISeasonController.sol";
import {SlopPacks} from "../SlopPacks.sol";
import {Sloplings} from "../Sloplings.sol";
import {RandaoOracle} from "../RandaoOracle.sol";
import {SeasonOneState} from "./SeasonOneState.sol";
import {Rescuable} from "../utils/Rescuable.sol";

/// @title SeasonOneController
/// @notice The swappable logic of a Sloplings season and its user-facing surface.
///         Users mint, open, settle and deliver packs here; this contract gates
///         and prices them, derives entropy, and drives the durable
///         `SeasonOneState` (deck, accounting, the open lifecycle storage).
///         It owns no assets and no durable per-pack state — only owner-mutable
///         config (allowlist, fee, timing, entropy source, lookahead, art) and
///         the V4 burn wiring — so a buggy season is fixed by deploying a new
///         controller and re-pointing `state.setController`, leaving assets, deck
///         position, quotas, and in-flight opens intact.
///
///         The engine (`SlopPacks`) is just the pack NFT; this contract drives it
///         only indirectly, through the state (the engine's registered minter).
contract SeasonOneController is ISeasonController, IUnlockCallback, Ownable, ReentrancyGuard, Rescuable {
    using SafeCast for uint256;
    using LibString for uint256;
    using BalanceDeltaLibrary for BalanceDelta;

    error NotOnAllowlist();
    error ExceedsQuota();
    error SeasonNotStarted();
    error RevealsNotYetOpen();
    error WrongMintFee();
    error EntropyNotReady();
    error NotOwnerOfPack();
    error NotThisSeason();
    error PackLocked();
    error PositionOutOfRange();
    error BadHeaderCount();
    error InvalidLookahead();
    error WrongOpenFee();
    error NotPoolManager();
    error UnexpectedDeltaSign();
    error ZeroOwner();
    error EmptyBatch();

    /// @notice The shared pack NFT.
    SlopPacks public immutable packs;
    /// @notice The durable state + asset vault this controller drives.
    SeasonOneState private immutable _state;

    uint256 public constant seasonNumber = 1;

    // ----- owner-mutable config -----

    uint256 public openingFee;
    uint256 public startTimestamp; // early-quota mint gate
    uint256 public revealDelay; // reveals open at start + revealDelay
    uint256 public waveDelay; // offset past start when totalQuota unlocks

    /// @notice Blocks ahead of `requestOpen` the entropy block is committed; settle
    ///         can't happen until that block is mined. Min 1 (always commits to a
    ///         not-yet-mined block).
    uint256 public lookahead;

    /// @notice Entropy source. Owner may replace it; cannot rewrite settled draws.
    RandaoOracle public oracle;

    // ----- burn wiring (the open fee is swapped to SLOP and sent to DEAD) -----

    /// @dev Canonical burn address; sending SLOP here removes it from supply.
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    IPoolManager public immutable poolManager;
    /// @notice The V4 pool the open fee is swapped through. `currency0` is native
    ///         ETH (the fee), `currency1` is SLOP. Set once at construction; a
    ///         struct can't be immutable, so it lives in storage.
    PoolKey public poolKey;

    /// @notice Single allowlist root binding each address to (earlyQuota, totalQuota).
    bytes32 public allowlistRoot;

    /// @notice Base URI prepended to the pack token id to form `packTokenURI`.
    ///         Owner-mutable; freely re-settable. Empty until set.
    string public packBaseURI;

    event OpenRequested(uint256 indexed packTokenId, address indexed beneficiary, uint64 entropyBlock);

    /// @notice A pack's draw was settled (the deck slot consumed). `chosen` is the
    ///         0-based deck index in `[0, packCount)` — NOT a token id. The asset
    ///         it represents is: for `chosen < mainCount` the main-collection token
    ///         `mainCollection.MIN_TOKEN_ID() + chosen` (minted later, at deliver); for
    ///         `chosen >= mainCount` the escrowed vault item at index
    ///         `chosen - mainCount`.
    event OpenSettled(uint256 indexed packTokenId, address indexed beneficiary, uint256 chosen, uint256 position);

    /// @notice A pack was delivered: the drawn asset (`nftContract` token `tokenId`)
    ///         was transferred/minted to `beneficiary` and the pack burned.
    ///         Self-describing — consumers don't need to re-read state or branch on
    ///         main-vs-vault. For the deck index that produced this asset, see
    ///         `OpenSettled`.
    event PackOpened(
        uint256 indexed packTokenId, address indexed beneficiary, address indexed nftContract, uint256 tokenId
    );
    /// @notice One combined V4 swap per `requestOpen` batch sent `ethIn` of ETH and
    ///         burned `slopBurned` of SLOP (DEAD-address forward). `packCount` is the
    ///         number of packs that contributed to the fee — divide for pro-rata
    ///         per-pack accounting off-chain if needed.
    event SlopBurned(uint256 ethIn, uint256 slopBurned, uint256 packCount);
    event OpeningFeeSet(uint256 openingFee);
    event TimingSet(uint256 startTimestamp, uint256 revealDelay, uint256 waveDelay);
    event AllowlistRootSet(bytes32 root);
    event OracleSet(RandaoOracle indexed previous, RandaoOracle indexed next);
    event LookaheadSet(uint256 lookahead);
    event BaseURIUpdated(string baseURI);

    constructor(
        address owner_,
        SlopPacks packs_,
        SeasonOneState state_,
        RandaoOracle oracle_,
        IPoolManager poolManager_,
        PoolKey memory poolKey_,
        uint256 openingFee_,
        uint256 startTimestamp_,
        uint256 revealDelay_,
        uint256 waveDelay_,
        uint256 lookahead_
    ) {
        require(owner_ != address(0), ZeroOwner());
        require(lookahead_ >= 1, InvalidLookahead());
        _initializeOwner(owner_);
        packs = packs_;
        _state = state_;
        oracle = oracle_;
        poolManager = poolManager_;
        poolKey = poolKey_;
        openingFee = openingFee_;
        startTimestamp = startTimestamp_;
        revealDelay = revealDelay_;
        waveDelay = waveDelay_;
        lookahead = lookahead_;
    }

    /// @inheritdoc ISeasonController
    function state() external view returns (address) {
        return address(_state);
    }

    // ----- mint -----

    /// @notice Mint `amount` packs to `recipient` in one transaction. Allowlist +
    ///         quota key on `msg.sender` (the payer); `recipient` may differ.
    ///         `authData` = abi.encode(uint256 earlyQuota, uint256 totalQuota,
    ///         bytes32[] proof). Minting is free; attached value is rejected.
    ///         Returns the first id of the sequential batch
    ///         `[firstPackTokenId, firstPackTokenId + amount)`.
    function mintPack(address recipient, uint256 amount, bytes calldata authData)
        external
        payable
        returns (uint256 firstPackTokenId)
    {
        require(msg.value == 0, WrongMintFee());
        require(block.timestamp >= startTimestamp, SeasonNotStarted());

        (uint256 earlyQuota, uint256 totalQuota, bytes32[] memory proof) =
            abi.decode(authData, (uint256, uint256, bytes32[]));

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, earlyQuota, totalQuota))));
        require(MerkleProofLib.verify(proof, allowlistRoot, leaf), NotOnAllowlist());

        uint256 cap = block.timestamp >= startTimestamp + waveDelay ? totalQuota : earlyQuota;
        require(_state.mintedBy(msg.sender) + amount <= cap, ExceedsQuota());

        // state enforces the supply cap + accounting and mints the pack NFTs.
        firstPackTokenId = _state.mintPack(msg.sender, recipient, amount);
    }

    // ----- open: request -----

    /// @notice Open a batch of packs you own in one transaction. Commits every pack
    ///         to the same future-block prevRandao (`entropyBlock = block.number +
    ///         lookahead`), and swaps the combined opening fee
    ///         (`openingFee * n`) to SLOP in ONE V4 swap, forwarding it to DEAD.
    ///         Each pack is locked until delivery (the state does this in
    ///         `recordOpen`). Pass `[pack]` for a single-pack open.
    function requestOpen(uint256[] calldata packTokenIds) external payable nonReentrant {
        uint256 n = packTokenIds.length;
        require(n > 0, EmptyBatch());
        require(revealsOpen(), RevealsNotYetOpen());
        require(msg.value == openingFee * n, WrongOpenFee());

        uint64 entropyBlock = (block.number + lookahead).toUint64();
        for (uint256 i = 0; i < n; i++) {
            uint256 pack = packTokenIds[i];
            require(packs.seasonOf(pack) == address(_state), NotThisSeason());
            require(packs.ownerOf(pack) == msg.sender, NotOwnerOfPack());
            require(_state.getOpenRequest(pack).status == SeasonOneState.RequestStatus.None, PackLocked());
            // Enqueue + lock BEFORE the swap (no double-open re-entry).
            // recordOpen is whenNotPaused, so a paused season rejects the open here.
            _state.recordOpen(pack, entropyBlock);
            emit OpenRequested(pack, msg.sender, entropyBlock);
        }

        // ONE swap for the whole batch; per-pack attribution is the FE's job
        // (divide `slopBurned` by `packCount` for pro-rata).
        uint256 slopBurned = _swapAndBurn(msg.value);
        if (slopBurned != 0) emit SlopBurned(msg.value, slopBurned, n);
    }

    // ----- open: settle (anyone) + deliver (beneficiary) -----

    /// @notice Advance the settle pointer through `targetPosition`, drawing each
    ///         pending position's outcome in strict order. `proofs` is interpreted
    ///         leniently: only the trailing N entries are consumed (N = positions
    ///         still pending), so a caller who raced a concurrent settle has their
    ///         already-settled prefix discarded rather than reverting. Anyone may call.
    ///         Public so `settleAndDeliver` can call it internally.
    function settle(uint256 targetPosition, bytes[] calldata proofs) public {
        uint256 start = _state.nextSettlePosition();
        if (targetPosition < start) return; // already past
        require(targetPosition < _state.nextOpenPosition(), PositionOutOfRange());

        uint256 needed = (targetPosition - start) + 1;
        require(proofs.length >= needed, BadHeaderCount());
        uint256 offset = proofs.length - needed;

        for (uint256 i = 0; i < needed; i++) {
            uint256 position = start + i;
            uint256 packTokenId = packIdForPosition(position);
            uint256 entropyBlock = _state.getOpenRequest(packTokenId).entropyBlock;
            bytes32 randomness = entropy(entropyBlock, proofs[offset + i]);
            bytes32 seed = keccak256(abi.encode(packTokenId, randomness));
            (uint256 chosen, bool didDraw) = _state.settleOne(packTokenId, seed);
            if (didDraw) emit OpenSettled(packTokenId, packs.ownerOf(packTokenId), chosen, position);
        }
        _state.setNextSettle(targetPosition + 1);
    }

    /// @notice Take delivery of a batch of settled packs. The drawn asset for each
    ///         pack goes to that pack's current owner (anyone may call — beneficiary
    ///         is read live); each delivered pack is burned. Pass `[pack]` for a
    ///         single delivery.
    function deliver(uint256[] calldata packTokenIds) public {
        uint256 n = packTokenIds.length;
        require(n > 0, EmptyBatch());
        for (uint256 i = 0; i < n; i++) {
            _deliverOne(packTokenIds[i]);
        }
    }

    /// @notice Settle through the highest position among `packTokenIds` (if not
    ///         already), then deliver each. Pass empty `proofs` if a third party has
    ///         already settled the relevant positions. Pass `[pack]` for a single
    ///         settle-and-deliver.
    function settleAndDeliver(uint256[] calldata packTokenIds, bytes[] calldata proofs) external {
        uint256 n = packTokenIds.length;
        require(n > 0, EmptyBatch());
        // Settle through the deepest position the batch needs. Each pack's
        // _deliverOne will revert NotDeliverable if its position wasn't settled
        // (e.g. someone passed an unopened pack).
        uint256 target = _state.getOpenRequest(packTokenIds[0]).position;
        for (uint256 i = 1; i < n; i++) {
            uint256 pos = _state.getOpenRequest(packTokenIds[i]).position;
            if (pos > target) target = pos;
        }
        settle(target, proofs);
        for (uint256 i = 0; i < n; i++) {
            _deliverOne(packTokenIds[i]);
        }
    }

    /// @dev Deliver one pack: drawn asset to its current owner, pack burned, event.
    function _deliverOne(uint256 packTokenId) internal {
        address beneficiary = packs.ownerOf(packTokenId);
        // Returns the actual asset routed; reverts if not Settled / paused.
        (address nftContract, uint256 tokenId) = _state.deliver(packTokenId, beneficiary);
        emit PackOpened(packTokenId, beneficiary, nftContract, tokenId);
    }

    // ----- entropy -----

    /// @dev `proof` encoding depends on whether `entropyBlock` is within the
    ///      oracle's recent window: raw RLP header within window; otherwise
    ///      abi.encode(bytes headerRlp, bytes beaconProof) for the long-range path.
    function entropy(uint256 entropyBlock, bytes calldata proof) public view returns (bytes32) {
        require(block.number > entropyBlock, EntropyNotReady());
        if (oracle.isWithinRecentWindow(entropyBlock)) {
            return oracle.getRecentPrevRandao(entropyBlock, proof);
        }
        (bytes memory headerRlp, bytes memory beaconProof) = abi.decode(proof, (bytes, bytes));
        return oracle.getHistoricalBlockhashPrevRandao(entropyBlock, headerRlp, beaconProof);
    }

    // ----- burn (open fee -> SLOP -> DEAD via the V4 pool) -----

    /// @dev Swap `ethIn` of native ETH for SLOP through the V4 pool and forward the
    ///      SLOP to DEAD; returns the SLOP burned. `virtual` so tests can override
    ///      with a mock that needs no live pool. `ethIn == 0` is a no-op.
    function _swapAndBurn(uint256 ethIn) internal virtual returns (uint256 slopBurned) {
        if (ethIn == 0) return 0;
        bytes memory ret = poolManager.unlock(abi.encode(ethIn));
        slopBurned = abi.decode(ret, (uint256));
    }

    /// @inheritdoc IUnlockCallback
    /// @dev Runs inside `poolManager.unlock`: swap exact-input ETH->SLOP, settle the
    ///      ETH owed, take the SLOP to DEAD. Only the pool manager may call.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), NotPoolManager());
        uint256 ethIn = abi.decode(data, (uint256));

        PoolKey memory key = poolKey;
        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );

        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();
        require(a0 < 0 && a1 > 0, UnexpectedDeltaSign());

        uint256 ethOwed = uint256(int256(-a0));
        uint256 slopOut = uint256(int256(a1));

        // Sync currency0 (native ETH) before settling; see PoolManager `_settle`.
        poolManager.sync(key.currency0);
        poolManager.settle{value: ethOwed}();
        poolManager.take(key.currency1, DEAD, slopOut);

        return abi.encode(slopOut);
    }

    // ----- timing -----

    function revealsOpen() public view returns (bool) {
        return block.timestamp >= startTimestamp + revealDelay;
    }

    function packTokenURI(uint256) external view returns (string memory) {
        string memory base = packBaseURI;
        return bytes(base).length != 0 ? string.concat(base, seasonNumber.toString()) : "";
    }

    // ----- owner: config -----

    function setOpeningFee(uint256 openingFee_) external onlyOwner {
        openingFee = openingFee_;
        emit OpeningFeeSet(openingFee_);
    }

    /// @notice Set the season's timing. Grouped because the three reason about
    ///         each other.
    function setTiming(uint256 startTimestamp_, uint256 revealDelay_, uint256 waveDelay_) external onlyOwner {
        startTimestamp = startTimestamp_;
        revealDelay = revealDelay_;
        waveDelay = waveDelay_;
        emit TimingSet(startTimestamp_, revealDelay_, waveDelay_);
    }

    function setAllowlistRoot(bytes32 root) external onlyOwner {
        allowlistRoot = root;
        emit AllowlistRootSet(root);
    }

    function setOracle(RandaoOracle oracle_) external onlyOwner {
        emit OracleSet(oracle, oracle_);
        oracle = oracle_;
    }

    function setLookahead(uint256 lookahead_) external onlyOwner {
        require(lookahead_ >= 1, InvalidLookahead());
        lookahead = lookahead_;
        emit LookaheadSet(lookahead_);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _setBaseUri(newBaseURI);
    }

    function _setBaseUri(string memory newBaseURI) internal {
        packBaseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
        // The base URI is the entire prefix of every pack's tokenURI; changing
        // it changes every minted pack's metadata. Tell the engine to refresh
        // the whole collection. (`(0, type(uint256).max)` is the canonical
        // ERC-4906 "refresh everything" range.)
        _state.emitPackBatchMetadataUpdate(0, type(uint256).max);
    }

    /// @dev Owner-only. The controller custodies no game assets (those live in the
    ///      state), so a blanket rescue here is not a backdoor.
    function _authorizeRescue() internal view override {
        _checkOwner();
    }

    // ----- views (passthroughs to the state) -----

    function mainCollection() external view returns (Sloplings) {
        return _state.mainCollection();
    }

    function mainCount() external view returns (uint256) {
        return _state.mainCount();
    }

    function packCount() external view returns (uint256) {
        return _state.packCount();
    }

    function remaining() external view returns (uint256) {
        return _state.remaining();
    }

    function vaultCount() external view returns (uint256) {
        return _state.vaultCount();
    }

    function vaultItem(uint256 idx) external view returns (address nft, uint256 tokenId) {
        return _state.vaultItem(idx);
    }

    function mintedPacks() external view returns (uint256) {
        return _state.mintedPacks();
    }

    function mintedBy(address user) external view returns (uint256) {
        return _state.mintedBy(user);
    }

    function nextOpenPosition() external view returns (uint256) {
        return _state.nextOpenPosition();
    }

    function nextSettlePosition() external view returns (uint256) {
        return _state.nextSettlePosition();
    }

    function packIdForPosition(uint256 position) public view returns (uint256) {
        return _state.packIdForPosition(position);
    }

    function pendingCount() external view returns (uint256) {
        return _state.pendingCount();
    }

    function requestStatus(uint256 packTokenId) external view returns (SeasonOneState.RequestStatus) {
        return _state.getOpenRequest(packTokenId).status;
    }

    function getOpenRequest(uint256 packTokenId) external view returns (SeasonOneState.OpenRequest memory) {
        return _state.getOpenRequest(packTokenId);
    }
}
