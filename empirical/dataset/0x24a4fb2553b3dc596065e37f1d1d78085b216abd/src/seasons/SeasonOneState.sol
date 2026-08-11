// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pausable} from "@openzeppelin-v5/contracts/utils/Pausable.sol";
import {IERC721} from "@openzeppelin-v5/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin-v5/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeCast} from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

import {SlopPacks} from "../SlopPacks.sol";
import {Sloplings} from "../Sloplings.sol";
import {ISeason} from "../interfaces/ISeason.sol";
import {ISeasonController} from "../interfaces/ISeasonController.sol";
import {FisherYatesDeck} from "../libraries/FisherYatesDeck.sol";

/// @title SeasonOneState
/// @notice The durable half of a season and the engine's registered "season"
///         (the stable address that mints/burns/locks packs). It holds everything
///         that must survive a controller (logic) swap:
///           * the asset pool — a `Sloplings` main collection it mints + escrowed
///             vault NFTs,
///           * the Fisher-Yates deck and mint accounting,
///           * the per-pack open lifecycle (request/settle/deliver state) and the
///             ordered settle queue.
///         All mutation is `onlyController`; the active controller (logic) drives
///         it. Keeping the lifecycle STORAGE here (not in the controller) means a
///         logic swap never loses in-flight opens, deck position, or quotas. The
///         one piece of trust-critical mechanism kept in this contract rather than
///         the controller is the draw-once guard (`settleOne`), bound atomically to
///         the deck it consumes.
contract SeasonOneState is ISeason, Ownable, Pausable, IERC721Receiver {
    using FisherYatesDeck for FisherYatesDeck.Deck;
    using SafeCast for uint256;

    /// @notice Lifecycle for a pack's open. Keyed by packTokenId.
    enum RequestStatus {
        None, // 0 — never opened
        Pending, // 1 — opened; deck not yet consumed for its position
        Settled, // 2 — deck consumed, outcome recorded, not yet delivered
        Delivered // 3 — outcome delivered, pack burned
    }

    struct OpenRequest {
        uint64 entropyBlock; // slot 0 (8)
        uint64 position; // slot 0 (8)  settle-queue position
        uint64 chosen; // slot 0 (8)   deck outcome (meaningful once Settled)
        RequestStatus status; // slot 0 (1)
    }

    struct VaultItem {
        address nft;
        uint96 tokenId;
    }

    error NotController();
    error SoldOut();
    error PoolLocked();
    error ControllerStateMismatch();
    error VaultNotEscrowed();
    error VaultAlreadyRegistered();
    error NotDeliverable();
    error ZeroOwner();

    /// @notice The shared pack NFT. This contract is registered on it as a season
    ///         (`packs.isSeason`), so it alone mints/burns/locks its packs.
    SlopPacks public immutable packs;

    /// @notice This season's main collection. Its minter must be THIS contract.
    Sloplings public immutable mainCollection;

    /// @notice The active controller (logic). Owner-settable so logic swaps don't
    ///         move assets, the deck, accounting, or in-flight opens.
    address public controller;

    /// @notice Escrowed vault NFTs, delivered for draws at index >= mainCount.
    VaultItem[] internal _vault;

    /// @dev Prevents registering the same escrowed NFT more than once. Since
    ///      NFTs are pushed here before registration, ownership alone is not
    ///      enough to prove an item has not already entered the deck.
    mapping(address nft => mapping(uint256 tokenId => bool registered)) internal _vaultRegistered;

    /// @notice Fisher-Yates deck over [0, packCount). Drawn once per pack at settle.
    FisherYatesDeck.Deck internal _deck;

    /// @notice Packs minted so far; gates the supply cap.
    uint256 public mintedPacks;

    /// @notice Cumulative packs minted per address (quota accounting).
    mapping(address => uint256) public mintedBy;

    // ----- open lifecycle (durable; survives a controller swap) -----

    mapping(uint256 packTokenId => OpenRequest) public openRequests;

    /// @notice Settle queue: nextOpenPosition increments on every open;
    ///         nextSettlePosition advances strictly in order as positions settle.
    uint256 public nextOpenPosition;
    uint256 public nextSettlePosition;
    mapping(uint256 position => uint256 packTokenId) public packIdForPosition;

    event ControllerSet(address indexed previous, address indexed next);
    event NFTWithdrawn(address indexed nft, uint256 tokenId, address indexed to);

    /// @param startPaused If true, the season deploys paused — mint/open/settle/deliver are
    ///        all halted until the owner calls `unpause`. Mainnet deploys start paused (the
    ///        owner finishes the out-of-band setup — Sloplings.setMinter, vault
    ///        transfers, addVault — then unpauses to go live); Sepolia/local start
    ///        unpaused. Pausing in the constructor is atomic with deploy, closing the
    ///        deploy-then-pause window.
    constructor(address owner_, SlopPacks packs_, Sloplings mainCollection_, bool startPaused) {
        require(owner_ != address(0), ZeroOwner());
        _initializeOwner(owner_);
        packs = packs_;
        mainCollection = mainCollection_;
        if (startPaused) {
            _pause();
        }
    }

    modifier onlyController() {
        require(msg.sender == controller, NotController());
        _;
    }

    // ----- ISeason -----

    /// @inheritdoc ISeason
    /// @dev The engine's `tokenURI` lands here; forward to the (swappable) logic.
    function packTokenURI(uint256 packTokenId) external view returns (string memory) {
        return ISeasonController(controller).packTokenURI(packTokenId);
    }

    // ----- views -----

    function mainCount() public view returns (uint256) {
        return mainCollection.MAX_SUPPLY();
    }

    /// @notice Total deck size = main pool + escrowed vault.
    function packCount() public view returns (uint256) {
        return mainCount() + _vault.length;
    }

    function remaining() external view returns (uint256) {
        return _deck.remaining(packCount());
    }

    function vaultCount() external view returns (uint256) {
        return _vault.length;
    }

    function vaultItem(uint256 idx) external view returns (address nft, uint256 tokenId) {
        VaultItem storage v = _vault[idx];
        return (v.nft, v.tokenId);
    }

    function getOpenRequest(uint256 packTokenId) external view returns (OpenRequest memory) {
        return openRequests[packTokenId];
    }

    /// @notice Outstanding pending opens in the settle queue.
    function pendingCount() external view returns (uint256) {
        return nextOpenPosition - nextSettlePosition;
    }

    // ----- controller-gated mutators -----

    /// @notice Record `amount` pack mints by `minter` and mint that many packs to
    ///         `to`. Enforces the asset-backed supply cap; the quota check is the
    ///         controller's job. Returns the first id of the sequential batch
    ///         `[firstPackTokenId, firstPackTokenId + amount)`.
    function mintPack(address minter, address to, uint256 amount)
        external
        onlyController
        whenNotPaused
        returns (uint256 firstPackTokenId)
    {
        require(mintedPacks + amount <= packCount(), SoldOut());
        mintedPacks += amount;
        mintedBy[minter] += amount;
        firstPackTokenId = packs.mint(to, amount);
    }

    /// @notice Record an open: enqueue the pack at the next position, mark it
    ///         Pending, and lock it against transfer until delivery.
    function recordOpen(uint256 packTokenId, uint64 entropyBlock) external onlyController whenNotPaused {
        uint256 pos = nextOpenPosition;
        openRequests[packTokenId] = OpenRequest({
            entropyBlock: entropyBlock, position: pos.toUint64(), chosen: 0, status: RequestStatus.Pending
        });
        packIdForPosition[pos] = packTokenId;
        nextOpenPosition = pos + 1;
        packs.setTransferLocked(packTokenId, true);
    }

    /// @notice Settle one position: draw its deck outcome exactly once. The status
    ///         flip and the destructive deck draw are atomic here (no external call
    ///         between), so a re-entrant or double settle for the same pack can't
    ///         consume the deck twice — it sees `status != Pending` and returns
    ///         `didDraw == false`. The controller owns the ordered walk; this owns
    ///         "draw at most once per pack".
    function settleOne(uint256 packTokenId, bytes32 seed)
        external
        onlyController
        whenNotPaused
        returns (uint256 chosen, bool didDraw)
    {
        OpenRequest storage req = openRequests[packTokenId];
        if (req.status == RequestStatus.Settled || req.status == RequestStatus.Delivered) {
            return (req.chosen, false);
        }
        require(req.status == RequestStatus.Pending, NotDeliverable());
        req.status = RequestStatus.Settled;
        chosen = _deck.draw(packCount(), seed);
        req.chosen = chosen.toUint64();
        didDraw = true;
    }

    /// @notice Advance the settle pointer. The controller computes the target and
    ///         only ever moves it forward across a settled run.
    function setNextSettle(uint256 pos) external onlyController {
        nextSettlePosition = pos;
    }

    /// @notice Forward an ERC-4906 pack-range refresh to the engine. Called by
    ///         the controller when something it owns changes `packTokenURI` for
    ///         many packs at once (e.g. the base URI is reset). The state is
    ///         the engine-registered season, so it's the address authorized to
    ///         emit on `packs`.
    function emitPackBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external onlyController {
        packs.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    /// @notice Deliver a settled pack: flip to Delivered + burn (before the asset
    ///         move, so a re-entrant deliver sees it handled), then move the drawn
    ///         asset to the current pack owner. Returns the actual asset routed
    ///         (`nftContract`, `tokenId`) so the controller can emit a
    ///         self-describing PackOpened event without re-reading state.
    function deliver(uint256 packTokenId, address to)
        external
        onlyController
        whenNotPaused
        returns (address nftContract, uint256 tokenId)
    {
        OpenRequest storage req = openRequests[packTokenId];
        require(req.status == RequestStatus.Settled, NotDeliverable());

        req.status = RequestStatus.Delivered;
        packs.unlockAndBurn(packTokenId);

        uint256 chosen = req.chosen; // deck index in [0, packCount)
        uint256 mc = mainCount();
        if (chosen < mc) {
            // Map the 0-based deck index into the collection's own id space.
            nftContract = address(mainCollection);
            tokenId = mainCollection.MIN_TOKEN_ID() + chosen;
            mainCollection.mint(tokenId, to);
        } else {
            VaultItem storage v = _vault[chosen - mc];
            nftContract = v.nft;
            tokenId = v.tokenId;
            IERC721(v.nft).transferFrom(address(this), to, tokenId);
        }
    }

    // ----- owner -----

    /// @notice Point at the active controller (the logic swap). Requires the
    ///         controller already bound to THIS state. Best done while paused.
    function setController(address controller_) external onlyOwner {
        require(ISeasonController(controller_).state() == address(this), ControllerStateMismatch());
        emit ControllerSet(controller, controller_);
        controller = controller_;
    }

    /// @notice Register vault NFTs already escrowed in this state contract,
    ///         growing the pool. The owner must push each NFT here first, then
    ///         call this to freeze it into the deck. Only before the first mint —
    ///         `packCount` sizes the deck, so the pool must be frozen before any
    ///         draw.
    function addVault(VaultItem[] calldata items) external onlyOwner {
        require(mintedPacks == 0, PoolLocked());
        for (uint256 i = 0; i < items.length; i++) {
            require(IERC721(items[i].nft).ownerOf(items[i].tokenId) == address(this), VaultNotEscrowed());
            require(!_vaultRegistered[items[i].nft][items[i].tokenId], VaultAlreadyRegistered());
            _vaultRegistered[items[i].nft][items[i].tokenId] = true;
            _vault.push(items[i]);
        }
    }

    /// @notice Emergency escape hatch: pull escrowed NFTs out to `to`. Only while
    ///         paused, so the deck can't draw an item that's no longer here.
    function withdrawNFTs(VaultItem[] calldata items, address to) external onlyOwner whenPaused {
        for (uint256 i = 0; i < items.length; i++) {
            IERC721(items[i].nft).transferFrom(address(this), to, items[i].tokenId);
            emit NFTWithdrawn(items[i].nft, items[i].tokenId, to);
        }
    }

    /// @notice Per-season kill switch. Halts mint, open, settle, and deliver, and
    ///         enables `withdrawNFTs`.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
