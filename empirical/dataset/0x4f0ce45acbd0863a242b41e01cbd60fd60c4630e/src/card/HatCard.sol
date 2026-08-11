// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721A, IERC721A} from "erc721a/contracts/ERC721A.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHatCard} from "./IHatCard.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {Errors} from "../util/Errors.sol";

/// @title HatCard
/// @notice ERC-721 player cards for HAT-TRICK · World Cup 2026.
///
/// Why ERC721A
/// -----------
/// Pack opens mint up to 50 consecutive token ids to a single owner in a
/// single VRF callback. ERC721A's range-mint compresses 50 ownership writes
/// into one slot, which is the difference between a survivable Apex pack
/// (~$130 in gas at 10 gwei) and a fee-dead one. The per-card state is
/// written separately to a `cards` mapping so the optimisation holds.
///
/// Authority (whitepaper INV-03)
/// -----------------------------
/// `mintBatch` and `setCardData` are callable only by ProtocolRegistry.packSale.
/// `evolve` is callable only by ProtocolRegistry.matchOracle. Both addresses
/// are settable once on the registry, so the authority is permanent after
/// deployment.
contract HatCard is ERC721A, Ownable, IHatCard {
    IProtocolRegistry public immutable registry;

    /// @dev Per-card state. Keyed by tokenId. Identity fields are written
    /// once at mint and never change; only `potential` mutates.
    mapping(uint256 => Card) private _cards;

    /// @dev Per-rarity potential ceiling π̄(r). Settable by owner during
    /// PRESALE; frozen thereafter. Set in 1e18-scaled fixed point.
    mapping(Rarity => uint128) public override rarityCeiling;
    bool private _ceilingsFrozen;

    event CardMinted(uint256 indexed tokenId, address indexed to, uint16 playerId, Rarity rarity);
    event CardEvolved(uint256 indexed tokenId, uint128 oldPotential, uint128 newPotential);
    event RarityCeilingsFrozen();

    constructor(IProtocolRegistry _registry, address _owner)
        ERC721A("HAT-TRICK Player Card", "HATCARD")
        Ownable(_owner)
    {
        registry = _registry;
    }

    // ─── auth modifiers ──────────────────────────────────────────────────

    modifier onlyPackSale() {
        if (msg.sender != registry.packSale()) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyMatchOracle() {
        if (msg.sender != registry.matchOracle()) revert Errors.NotAuthorized();
        _;
    }

    // ─── owner: rarity ceilings (one-shot freeze) ────────────────────────

    /// @notice Set the per-rarity potential ceiling π̄(r). Must be called
    /// once per rarity before `freezeRarityCeilings()`.
    function setRarityCeiling(Rarity r, uint128 ceiling) external onlyOwner {
        if (_ceilingsFrozen) revert Errors.AlreadyInitialised();
        rarityCeiling[r] = ceiling;
    }

    /// @notice Lock the rarity ceilings permanently. Should be called before
    /// PRESALE → WHITELIST advance.
    function freezeRarityCeilings() external onlyOwner {
        _ceilingsFrozen = true;
        emit RarityCeilingsFrozen();
    }

    // ─── read ────────────────────────────────────────────────────────────

    function getCard(uint256 tokenId) external view override returns (Card memory) {
        if (!_exists(tokenId)) revert Errors.CardDoesNotExist();
        return _cards[tokenId];
    }

    function potentialOf(uint256 tokenId) external view override returns (uint128) {
        if (!_exists(tokenId)) revert Errors.CardDoesNotExist();
        return _cards[tokenId].potential;
    }

    /// @dev ERC721A starts ids at 0 by default; we override to 1 so a fresh
    /// `_cards[0]` can never collide with a real card.
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ─── restricted writes ───────────────────────────────────────────────

    function mintBatch(address to, uint256 quantity)
        external
        override
        onlyPackSale
        returns (uint256 firstTokenId)
    {
        if (quantity == 0) revert Errors.ZeroAmount();
        firstTokenId = _nextTokenId();
        _mint(to, quantity);          // ERC721A range-mint, one storage write
    }

    function setCardData(uint256 tokenId, Card calldata card) external override onlyPackSale {
        if (!_exists(tokenId)) revert Errors.CardDoesNotExist();
        Card storage stored = _cards[tokenId];
        // Identity slot empty == not yet written. Use playerId as the marker.
        if (stored.playerId != 0) revert Errors.AlreadyInitialised();
        if (card.playerId == 0) revert Errors.UnknownPlayer();
        if (uint8(card.rarity) > uint8(Rarity.LEGENDARY)) revert Errors.InvalidRarity();
        // Cap potential at the rarity ceiling at write time too — defensive.
        if (card.potential > rarityCeiling[card.rarity]) revert Errors.PotentialOverflow();
        // Traits' statIds within [0,17].
        if (card.trait0.statId > 17 || card.trait1.statId > 17 || card.trait2.statId > 17) {
            revert Errors.InvalidStat();
        }
        // Three traits MUST be on distinct stats (whitepaper §04).
        if (
            card.trait0.statId == card.trait1.statId ||
            card.trait0.statId == card.trait2.statId ||
            card.trait1.statId == card.trait2.statId
        ) revert Errors.InvalidTraitIndex();

        _cards[tokenId] = card;
        emit CardMinted(tokenId, ownerOf(tokenId), card.playerId, card.rarity);
    }

    function evolve(uint256 tokenId, uint128 newPotential) external override onlyMatchOracle {
        if (!_exists(tokenId)) revert Errors.CardDoesNotExist();
        Card storage c = _cards[tokenId];
        uint128 ceiling = rarityCeiling[c.rarity];
        if (newPotential > ceiling) newPotential = ceiling;       // saturate, per §03
        uint128 old = c.potential;
        if (newPotential <= old) return;                           // monotone — no-op on non-increase
        c.potential = newPotential;
        emit CardEvolved(tokenId, old, newPotential);
    }
}
