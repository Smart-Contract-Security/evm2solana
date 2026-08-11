// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IHatCard
/// @notice Read + restricted-write interface for HAT-TRICK player cards.
interface IHatCard {
    enum Rarity { BASE, RARE, MYTHIC, LEGENDARY }

    /// @dev One card's state. Identity fields are immutable from mint; only
    /// `potential` mutates, via MatchOracle.
    struct Card {
        uint16 playerId;       // canonical footballer id (1..1248)
        uint8 nation;          // 1..48
        Rarity rarity;
        uint32 serial;         // mint index within (playerId, rarity)
        uint128 potential;     // 1e18-scaled scalar; capped per rarity
        Trait trait0;
        Trait trait1;
        Trait trait2;
    }

    /// @dev One trait. `statId ∈ [0, 17]`. `delta` is the signed change to
    /// the displayed stat. `score` is the signed score contribution.
    struct Trait {
        uint8 statId;
        int16 delta;
        int32 score;
    }

    // ─── read ────────────────────────────────────────────────────────────
    function getCard(uint256 tokenId) external view returns (Card memory);
    function potentialOf(uint256 tokenId) external view returns (uint128);
    function rarityCeiling(Rarity r) external view returns (uint128);

    // ─── restricted writes ───────────────────────────────────────────────
    /// @dev PackSale only. Mints `quantity` cards to `to`. Each card's state
    /// is set in `setCardData` calls that follow within the same callback;
    /// using ERC-721A's range-mint means token ids are contiguous.
    function mintBatch(address to, uint256 quantity) external returns (uint256 firstTokenId);

    /// @dev PackSale only. Writes the per-card state for a card minted in
    /// the same callback. Reverts if the card already has data.
    function setCardData(uint256 tokenId, Card calldata card) external;

    /// @dev MatchOracle only. Raises a card's potential. Reverts on
    /// non-monotone or above-ceiling updates (whitepaper INV-02).
    function evolve(uint256 tokenId, uint128 newPotential) external;
}
