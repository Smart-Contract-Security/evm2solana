// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {ProtocolPhase} from "../protocol/ProtocolPhase.sol";
import {IHatCard} from "../card/IHatCard.sol";
import {IEntropy} from "../entropy/IEntropy.sol";
import {IPackSale} from "./IPackSale.sol";
import {PackTiers} from "./PackTiers.sol";
import {Errors} from "../util/Errors.sol";

/// @title PackSale
/// @notice Sells packs, escrows funds, requests VRF on open, and mints the
/// resulting cards on the VRF callback.
///
/// Lifecycle of a pack (whitepaper §02):
///
///                 buy() ─────► OWNED
///                                │
///                       open() ──┤  burns the pack, requests VRF
///                                ▼
///                            REQUESTED
///                                │
///                  onEntropy() ──┤  derives pulls, mints cards
///                                ▼
///                             OPENED
///
/// A REQUESTED pack is dead — neither owner nor anyone else can retry the
/// open. This is what the whitepaper means by "no party can see or bias the
/// outcome between request and fulfilment."
contract PackSale is Ownable, ReentrancyGuard, IPackSale {
    using SafeERC20 for IERC20;
    using PackTiers for PackTiers.Tier;

    enum Status { NONE, OWNED, REQUESTED, OPENED }

    struct Pack {
        address owner;
        PackTiers.Tier tier;
        Status status;
        uint64 boughtAt;            // block.timestamp at buy
    }

    IProtocolRegistry public immutable registry;
    IERC20            public immutable paymentToken;       // stablecoin paid by buyers
    address           public           treasuryReceiver;    // where pack revenue lands

    /// @dev Tier price in `paymentToken`'s smallest unit. Settable until
    /// the protocol advances past PRESALE.
    mapping(PackTiers.Tier => uint256) public tierPrice;

    uint256 public nextPackId = 1;
    mapping(uint256 => Pack) public packs;
    mapping(uint256 => uint256) public requestToPack;   // VRF requestId → packId

    /// @dev Per-(playerId, rarity) serial counter, used when writing card data.
    mapping(uint16 => mapping(IHatCard.Rarity => uint32)) public serialCounter;

    event PackBought(uint256 indexed packId, address indexed buyer, PackTiers.Tier tier, uint256 price);
    event PackOpenRequested(uint256 indexed packId, uint256 indexed requestId);
    event PackOpened(uint256 indexed packId, uint256 firstTokenId, uint256 lastTokenId);
    event TierPriceSet(PackTiers.Tier tier, uint256 price);
    event TreasuryReceiverSet(address receiver);

    constructor(IProtocolRegistry _registry, IERC20 _paymentToken, address _initialOwner, address _treasuryReceiver)
        Ownable(_initialOwner)
    {
        if (address(_paymentToken) == address(0) || _treasuryReceiver == address(0)) revert Errors.ZeroAddress();
        registry         = _registry;
        paymentToken     = _paymentToken;
        treasuryReceiver = _treasuryReceiver;
    }

    // ─── owner setters (PRESALE only) ────────────────────────────────────

    modifier onlyInPresale() {
        if (registry.phase() != ProtocolPhase.Phase.PRESALE) revert Errors.WrongPhase();
        _;
    }

    function setTierPrice(PackTiers.Tier tier, uint256 price) external onlyOwner onlyInPresale {
        tierPrice[tier] = price;
        emit TierPriceSet(tier, price);
    }

    function setTreasuryReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        treasuryReceiver = receiver;
        emit TreasuryReceiverSet(receiver);
    }

    // ─── buy ─────────────────────────────────────────────────────────────

    /// @notice Buy a pack of a given tier. Caller must have approved
    /// `paymentToken` to this contract for the tier's price.
    function buy(PackTiers.Tier tier) external nonReentrant returns (uint256 packId) {
        ProtocolPhase.Phase ph = registry.phase();
        // Pack sales are open during PRESALE and WHITELIST per whitepaper §09.
        if (ph != ProtocolPhase.Phase.PRESALE && ph != ProtocolPhase.Phase.WHITELIST) revert Errors.WrongPhase();

        uint256 price = tierPrice[tier];
        if (price == 0) revert Errors.PackTierUnknown();

        paymentToken.safeTransferFrom(msg.sender, treasuryReceiver, price);

        packId = nextPackId++;
        packs[packId] = Pack({
            owner: msg.sender,
            tier: tier,
            status: Status.OWNED,
            boughtAt: uint64(block.timestamp)
        });
        emit PackBought(packId, msg.sender, tier, price);
    }

    // ─── open ────────────────────────────────────────────────────────────

    /// @notice Open an owned pack. Burns it (status → REQUESTED) and asks
    /// Entropy for `pulls(tier)` random words. The cards are minted on the
    /// callback.
    function open(uint256 packId) external nonReentrant {
        Pack storage p = packs[packId];
        if (p.owner != msg.sender) revert Errors.NotAuthorized();
        if (p.status != Status.OWNED) revert Errors.PackAlreadyOpened();
        p.status = Status.REQUESTED;

        uint32 numWords = uint32(uint8(PackTiers.pulls(p.tier)));
        uint256 requestId = IEntropy(registry.entropy()).requestRandomness(packId, msg.sender, numWords);
        requestToPack[requestId] = packId;
        emit PackOpenRequested(packId, requestId);
    }

    // ─── VRF callback ────────────────────────────────────────────────────

    /// @inheritdoc IPackSale
    /// @dev Only Entropy can call. Mints the cards in one ERC-721A range
    /// mint, then writes per-card data slot by slot.
    function onEntropy(uint256 requestId, uint256[] calldata words) external override {
        if (msg.sender != registry.entropy()) revert Errors.NotAuthorized();
        uint256 packId = requestToPack[requestId];
        if (packId == 0) revert Errors.CallbackOutOfOrder();
        delete requestToPack[requestId];

        Pack storage p = packs[packId];
        if (p.status != Status.REQUESTED) revert Errors.CallbackOutOfOrder();
        p.status = Status.OPENED;

        uint8 pullCount = PackTiers.pulls(p.tier);
        require(words.length >= pullCount, "PackSale: words too short");

        IHatCard card = IHatCard(registry.hatCard());

        // Range-mint all the cards to the owner in one storage write.
        uint256 firstTokenId = card.mintBatch(p.owner, pullCount);

        // Pity floor: if no pull in the pack reached `floor(tier)`, the LAST
        // pull is promoted to it (whitepaper §04). We track the max rarity
        // seen across pulls; if it falls short, we force the final pull's
        // rarity to the floor when computing pull data.
        IHatCard.Rarity floorRarity = PackTiers.floor(p.tier);
        IHatCard.Rarity maxSeen = IHatCard.Rarity.BASE;

        // First pass to determine max rarity at standard odds.
        uint256[] memory rarityRoll = new uint256[](pullCount);
        for (uint256 i = 0; i < pullCount; ++i) {
            uint256 r = uint256(uint8(words[i] % PackTiers.W_TOTAL));
            IHatCard.Rarity rarity = PackTiers.drawRarity(r);
            rarityRoll[i] = uint256(rarity);
            if (uint8(rarity) > uint8(maxSeen)) maxSeen = rarity;
        }
        if (uint8(maxSeen) < uint8(floorRarity)) {
            rarityRoll[pullCount - 1] = uint256(floorRarity);
        }

        // Second pass: derive and write each card.
        for (uint256 i = 0; i < pullCount; ++i) {
            IHatCard.Card memory c = _derivePull(words[i], IHatCard.Rarity(uint8(rarityRoll[i])));
            card.setCardData(firstTokenId + i, c);
        }

        emit PackOpened(packId, firstTokenId, firstTokenId + pullCount - 1);
    }

    /// @dev Derive one card's identity + traits from a single VRF word and
    /// a (possibly pity-floored) rarity. Extracted to avoid stack-too-deep
    /// in the parent loop.
    ///
    /// Trait magnitudes + scores are zero here; Phase 3 (ScoringEngine)
    /// plugs in the per-stat magnitude pool. The invariant we guarantee on
    /// chain at mint is the only one HatCard enforces: three traits with
    /// DISTINCT statIds in [0, 17].
    function _derivePull(uint256 word, IHatCard.Rarity rarity)
        internal
        returns (IHatCard.Card memory c)
    {
        uint16 playerId = uint16(1 + (word >> 8) % 1248);     // 1..1248
        uint8  nation   = uint8 (1 + ((word >> 24) % 48));     // 1..48
        uint32 serial   = ++serialCounter[playerId][rarity];

        (uint8 s0, uint8 s1, uint8 s2) = _distinctStatTriple(word);

        c = IHatCard.Card({
            playerId: playerId,
            nation:   nation,
            rarity:   rarity,
            serial:   serial,
            potential: 0,
            trait0:   IHatCard.Trait({statId: s0, delta: 0, score: 0}),
            trait1:   IHatCard.Trait({statId: s1, delta: 0, score: 0}),
            trait2:   IHatCard.Trait({statId: s2, delta: 0, score: 0})
        });
    }

    /// @dev Three distinct stat ids in [0, 17], derived from one VRF word
    /// by clean modular reduction with guaranteed distinctness:
    ///   s0 ∈ [0, 18)
    ///   s1 ∈ [0, 18) \ {s0}                    via shift-by-1 around s0
    ///   s2 ∈ [0, 18) \ {s0, s1}                via two shift-by-1's
    /// Deterministic and always succeeds, including for the all-zero word.
    function _distinctStatTriple(uint256 word) internal pure returns (uint8 s0, uint8 s1, uint8 s2) {
        s0 = uint8((word >> 32) % 18);

        // s1 picked from 17 remaining slots; map back to [0,18) skipping s0.
        s1 = uint8((word >> 80) % 17);
        if (s1 >= s0) s1 += 1;

        // s2 picked from 16 remaining slots; map back to [0,18) skipping
        // {s0, s1}. Apply skips in ascending order.
        s2 = uint8((word >> 128) % 16);
        uint8 lo  = s0 < s1 ? s0 : s1;
        uint8 hi  = s0 < s1 ? s1 : s0;
        if (s2 >= lo) s2 += 1;
        if (s2 >= hi) s2 += 1;
    }
}
