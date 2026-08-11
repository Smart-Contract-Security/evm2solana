// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableBasic} from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import {ERC721C, ERC721OpenZeppelin} from "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import {ICreatorToken} from "@limitbreak/creator-token-standards/src/interfaces/ICreatorToken.sol";
import {ICreatorTokenLegacy} from "@limitbreak/creator-token-standards/src/interfaces/ICreatorTokenLegacy.sol";
import {
    BasicRoyaltiesBase,
    ERC2981
} from "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";

import {ISeason} from "./interfaces/ISeason.sol";
import {Rescuable} from "./utils/Rescuable.sol";

/// @title SlopPacks
/// @notice Minimal, immutable pack NFT shared across seasons. This is the one
///         contract that can never be replaced, so it owns as little as possible:
///         just the token. It can
///           * mint a pack (an owner-authorized season, or the owner directly),
///           * burn or lock a pack (the season that minted that specific pack —
///             `seasonOf` — or the owner),
///           * reassign a pack's season (owner only),
///           * block transfer of a locked pack.
///         The entire open lifecycle — request/settle/deliver, the position
///         queue, entropy, the draw, delivery, fees and the burn — lives in the
///         season contracts (state + controller), which are swappable. The engine
///         never sequences anything and never holds funds; it stores per pack only
///         which season minted it, used to authorize burn/lock and to render
///         `tokenURI`.
///
///         Because this contract is immutable, the owner — a trusted operator who
///         acts publicly (every privileged action is an on-chain event) — has
///         broad escape hatches over the pack lifecycle (burn/lock/reassign/mint)
///         for recovery and migration when a season's swappable logic is bricked.
///         These powers touch only the pack NFT; they cannot reach a season's
///         draw (the deck + settle live in the season state), so the owner can
///         never privately bias an outcome — only destroy or re-route packs, all
///         on-chain.
///
///         ERC-721C + ERC-2981: inherits Limit Break's `ERC721C` and
///         `BasicRoyaltiesBase` exactly like `Sloplings`, so the on-chain
///         creator-fee path (validator + royalty) is identical on both contracts.
///         Owner-settable royalty and transfer validator via
///         `setDefaultRoyalty` / `setTransferValidator`.
contract SlopPacks is OwnableBasic, ERC721C, BasicRoyaltiesBase, Rescuable {
    /// @notice Seasons authorized to mint packs. Owner-managed. A "season" here is
    ///         the season's durable state contract — the stable identity that
    ///         mints/burns/locks on this engine across controller (logic) swaps.
    mapping(address => bool) public isSeason;

    /// @notice The season that controls each pack: it (or the owner) may burn or
    ///         lock the pack, and it renders the pack's `tokenURI`. Set at mint;
    ///         the owner may reassign it via `setSeasonOf` (e.g. migration).
    mapping(uint256 packTokenId => address season) public seasonOf;

    /// @notice Packs a season has locked against transfer (an open is in flight).
    ///         This is the sole gate in `_beforeTokenTransfer`: a locked pack
    ///         can't move at all, so a season must unlock it before burning at
    ///         delivery.
    mapping(uint256 packTokenId => bool) public transferLocked;

    uint256 public nextPackTokenId = 1;

    error NotSeason();
    error NotPackSeasonOrOwner();
    error NotSeasonOrOwner();
    error PackLocked();
    error ZeroOwner();
    error ZeroAmount();

    event SeasonSet(address indexed season, bool allowed);
    event PackMinted(address indexed season, address indexed to, uint256 indexed packTokenId);
    event TransferLockSet(uint256 indexed packTokenId, bool locked);
    event SeasonOfSet(uint256 indexed packTokenId, address indexed season);

    /// @notice ERC-4906 metadata-update events. Off-chain consumers
    ///         (marketplaces, indexers) listen for these to refresh a token's
    ///         tokenURI cache. Underscore-prefixed names are part of the spec.
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    /// @param owner_ The contract owner (manages seasons, validator, royalty).
    /// @param royaltyReceiver_ ERC-2981 default royalty receiver. Paired with
    ///        `royaltyBps_`; both zero skips royalty setup (settable later via
    ///        `setDefaultRoyalty`).
    /// @param royaltyBps_ ERC-2981 default royalty, in basis points (out of 10_000).
    /// @param transferValidator_ ERC-721C transfer validator to point at. Zero
    ///        leaves Limit Break's canonical default (`DEFAULT_TRANSFER_VALIDATOR`)
    ///        in place; repointable later via `setTransferValidator`.
    ///
    /// @dev Constructor mirrors `Sloplings`'s config-at-deploy shape (minus the
    ///      base-URI args, which don't apply — `tokenURI` is delegated to the
    ///      season). All three config knobs are also exposed as owner setters for
    ///      post-deploy changes.
    constructor(address owner_, address royaltyReceiver_, uint96 royaltyBps_, address transferValidator_)
        ERC721OpenZeppelin("Slop Packs", "SLOPPACK")
    {
        if (owner_ == address(0)) {
            revert ZeroOwner();
        }

        if (royaltyReceiver_ != address(0) || royaltyBps_ != 0) {
            _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
        }

        // `setTransferValidator` is owner-gated; OZ4 `Ownable` sets the owner to
        // `msg.sender` (the deployer) in its constructor, so this call (and the
        // royalty setup above) run as owner BEFORE we hand off below.
        if (transferValidator_ != address(0) && transferValidator_ != getTransferValidator()) {
            setTransferValidator(transferValidator_);
        }

        // Transfer to `owner_` only if it isn't already the deployer.
        if (owner_ != msg.sender) {
            transferOwnership(owner_);
        }
    }

    /// @notice Authorize or revoke a season (its state contract) as a pack minter.
    function setSeason(address season, bool allowed) external onlyOwner {
        isSeason[season] = allowed;
        emit SeasonSet(season, allowed);
    }

    /// @dev Caller must be an authorized season.
    modifier onlyValidSeason() {
        if (!isSeason[msg.sender]) {
            revert NotSeason();
        }
        _;
    }

    /// @dev Caller must be the season that minted `packTokenId`, or the owner.
    ///      The owner is a trusted operator acting publicly; this is the
    ///      immutable-engine escape hatch for recovering a pack whose season logic
    ///      is bricked.
    modifier onlyPackSeasonOrOwner(uint256 packTokenId) {
        if (msg.sender != seasonOf[packTokenId] && msg.sender != owner()) {
            revert NotPackSeasonOrOwner();
        }
        _;
    }

    /// @dev Caller must be any authorized season (`isSeason[msg.sender]`), or
    ///      the owner. Used for actions where the natural authority is "the
    ///      season that knows the off-chain URI state" but per-pack scoping
    ///      doesn't apply — e.g. ranged ERC-4906 refresh emits.
    modifier onlyValidSeasonOrOwner() {
        if (!isSeason[msg.sender] && msg.sender != owner()) {
            revert NotSeasonOrOwner();
        }
        _;
    }

    /// @notice Mint `amount` packs to `to`. Caller must be an authorized season and
    ///         becomes every minted pack's `seasonOf` — the address that can later
    ///         burn or lock it (alongside the owner). The season owns all
    ///         gating/fees upstream. Returns the first minted id; ids are
    ///         sequential, so the batch occupies `[firstPackTokenId, firstPackTokenId + amount)`.
    function mint(address to, uint256 amount) external onlyValidSeason returns (uint256 firstPackTokenId) {
        return _mintPack(to, msg.sender, amount);
    }

    /// @notice Owner escape hatch: mint `amount` packs assigned to `season` (any
    ///         address), bypassing the season-driven path. For recovery/reissue
    ///         under the trusted-operator model.
    ///         NOTE: this does NOT touch the named season's own supply/deck
    ///         accounting (`mintedPacks`, the Fisher-Yates deck). Minting more
    ///         packs than a season's deck can back will over-draw it at settle —
    ///         use deliberately.
    function ownerMint(address to, address season, uint256 amount)
        external
        onlyOwner
        returns (uint256 firstPackTokenId)
    {
        return _mintPack(to, season, amount);
    }

    /// @dev Mint `amount` sequential pack ids to `to` and pin each pack's
    ///      controlling `season`. Emits PackMinted per pack so off-chain consumers
    ///      see every id. _mint (not _safeMint): no receiver callback — onward
    ///      handling is the recipient's problem; the engine just owns the token.
    function _mintPack(address to, address season, uint256 amount) internal returns (uint256 firstPackTokenId) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        firstPackTokenId = nextPackTokenId;
        nextPackTokenId = firstPackTokenId + amount;
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = firstPackTokenId + i;
            seasonOf[tokenId] = season;
            _mint(to, tokenId);
            emit PackMinted(season, to, tokenId);
        }
    }

    /// @notice Burn a pack. The pack's season (called at delivery) or the owner.
    ///         The pack must be unlocked first (`setTransferLocked(id, false)`) —
    ///         `_beforeTokenTransfer` blocks any movement of a locked pack, burn
    ///         included.
    function burn(uint256 packTokenId) external onlyPackSeasonOrOwner(packTokenId) {
        _burn(packTokenId);
    }

    /// @notice Unlock and burn in one call — the delivery path. The pack's season
    ///         or the owner. Saves a separate `setTransferLocked(id, false)`;
    ///         clears the lock first since `_beforeTokenTransfer` blocks burning
    ///         a locked pack.
    function unlockAndBurn(uint256 packTokenId) external onlyPackSeasonOrOwner(packTokenId) {
        transferLocked[packTokenId] = false;
        _burn(packTokenId);
    }

    /// @notice Lock or unlock a pack against transfer. The pack's season or the
    ///         owner. A season locks on open (binding the beneficiary while the
    ///         outcome is in flight) and must unlock before burning at delivery;
    ///         the owner can force-unlock a pack stranded by bricked season logic.
    function setTransferLocked(uint256 packTokenId, bool value) external onlyPackSeasonOrOwner(packTokenId) {
        transferLocked[packTokenId] = value;
        emit TransferLockSet(packTokenId, value);
    }

    /// @notice Owner override: reassign which season controls a pack (burn/lock
    ///         authority) and renders its `tokenURI` — e.g. migrating packs onto a
    ///         replacement/emergency season. Any address is accepted; point it at
    ///         an `ISeason` implementer or the pack's `tokenURI` will revert until
    ///         fixed. Reassigning a pack mid-open desyncs the old season's
    ///         in-flight state, so prefer unopened packs or a coordinated migration.
    function setSeasonOf(uint256 packTokenId, address season) external onlyOwner {
        _requireMinted(packTokenId);
        seasonOf[packTokenId] = season;
        emit SeasonOfSet(packTokenId, season);
        // Reassigning the season changes the contract that renders this pack's
        // tokenURI — tell ERC-4906 consumers to refresh.
        emit MetadataUpdate(packTokenId);
    }

    /// @notice ERC-4906 manual poke: tell off-chain consumers to refresh a
    ///         single pack's metadata. The natural authority is the season that
    ///         renders tokenURI; the owner can also call for recovery. Any
    ///         authorized season may emit for any tokenId (events are advisory —
    ///         a spurious refresh just re-reads the same URI).
    function emitMetadataUpdate(uint256 tokenId) external onlyValidSeasonOrOwner {
        emit MetadataUpdate(tokenId);
    }

    /// @notice ERC-4906 manual poke for a contiguous range of token ids. Same
    ///         authorization as `emitMetadataUpdate`: any authorized season or
    ///         the owner. Use case: a season's URI logic changes (e.g. pack
    ///         media is updated) and the season tells the engine to refresh.
    function emitBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external onlyValidSeasonOrOwner {
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    // ----- royalties (owner-settable default; matches Sloplings's surface) -----

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    // ----- hooks -----

    /// @dev Movement gate + ERC-721C validator chain. The lock check runs first
    ///      across the whole batch (a locked pack can't move at all — transfer,
    ///      mint, or burn — irrespective of validator policy), then defers to
    ///      ERC721C's hook which walks each token through the configured
    ///      `validateTransfer` (skipping mints and burns).
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override(ERC721C)
    {
        for (uint256 i = 0; i < batchSize; i++) {
            if (transferLocked[firstTokenId + i]) {
                revert PackLocked();
            }
        }
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function tokenURI(uint256 packTokenId) public view override returns (string memory) {
        _requireMinted(packTokenId);
        return ISeason(seasonOf[packTokenId]).packTokenURI(packTokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721C, ERC2981) returns (bool) {
        return interfaceId == type(ICreatorToken).interfaceId || interfaceId == type(ICreatorTokenLegacy).interfaceId
            || interfaceId == 0x49064906 // ERC-4906
            || super.supportsInterface(interfaceId);
    }

    /// @dev Rescuable: owner-only. The engine holds no assets in normal operation,
    ///      and rescueERC721 can't move a user's pack — `transferFrom(this, …)`
    ///      reverts for any token the engine doesn't itself own.
    function _authorizeRescue() internal view override {
        _checkOwner();
    }
}
