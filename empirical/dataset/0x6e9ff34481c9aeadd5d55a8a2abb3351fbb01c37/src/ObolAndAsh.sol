// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Types} from "./lib/Types.sol";
import {Traits} from "./lib/Traits.sol";
import {Metadata} from "./lib/Metadata.sol";

/// @title Obol & Ash — 10,000 souls ferried across the River Styx
/// @notice Fully onchain SVG ERC-721 with burn-to-Cross evolution and ETH payout.
contract ObolAndAsh is ERC721, ERC721Burnable, IERC2981, IERC4906, Ownable, ReentrancyGuard {

    // ----------------------------------------------------------
    // Storage
    // ----------------------------------------------------------

    /// @dev tokenId => packed TokenData (see Types.pack)
    mapping(uint256 => uint256) private _packed;

    /// @dev Next token id to mint (1-indexed for human-friendly token numbers)
    uint256 public nextTokenId = 1;

    /// @dev Total minted (includes burned tokens)
    uint256 public totalMinted;

    /// @dev Mythic tokens minted so far (against the 10 cap)
    uint256 public mythicCount;

    /// @dev Free souls handed out so far (via the decaying free curve)
    uint256 public freeMinted;

    /// @dev Total souls minted per wallet (hard cap = maxMintsPerWallet)
    mapping(address => uint256) public mintedPerWallet;

    /// @dev Last mint timestamp per wallet (enforces the anti-spam cooldown)
    mapping(address => uint256) public lastMintAt;

    /// @dev Owner-set USD per ETH rate (e.g., 2080 means 1 ETH = $2080)
    uint256 public ethUsdRate;

    /// @dev Owner-adjustable price per soul, in bps of USD ($1.00 = 10000; 2500 = $0.25; 0 = free for all)
    uint256 public priceBps;

    /// @dev Owner-adjustable EIP-2981 royalty, in bps (1000 = 10%; 0 = royalties off). Capped at 10%.
    uint256 public royaltyBps;

    /// @dev Owner-adjustable hard cap of total souls a single wallet may mint
    uint256 public maxMintsPerWallet;

    /// @dev Owner-adjustable cooldown (seconds) a wallet must wait between mints
    uint256 public mintCooldown;

    /// @dev Backend signer that authorizes Soul Passcodes for the Ferryman mint path
    address public passSigner;

    /// @dev Spent Soul Passcodes (single-use) keyed by their signed digest
    mapping(bytes32 => bool) public passUsed;

    /// @dev Decaying free-mint curve endpoints (bps of 10000). Linear from start (at 0 minted)
    ///      down to end (at TOTAL_SUPPLY). One continuous wave; never zero so minting never stalls.
    uint256 public freeStartBps;
    uint256 public freeEndBps;

    /// @dev Evolve (Crossing/Sacrifice) phase gate — independent of the mint sale.
    bool public evolveActive;

    /// @dev Ascensions performed + owner cap (keeps higher tiers scarce). 0 cap = unlimited.
    uint256 public ascensionCount;
    uint256 public maxAscensions;

    /// @dev Fail-echo odds (bps of 10000) when BOTH souls were paid. Rare by design.
    ///      evolveHalfBps: chance to refund HALF the burned fuel's mint price.
    ///      evolveDoubleBps: chance to refund DOUBLE it. Remainder = nothing back.
    ///      Best-effort: paid only if the treasury holds funds; never blocks a Crossing.
    uint256 public evolveHalfBps;
    uint256 public evolveDoubleBps;

    /// @dev Sale gates
    bool public saleActive;

    /// @dev Per-collection seed used for trait resolution (set at deploy)
    bytes32 private immutable _collectionSeed;

    /// @dev Internal randomness counter (mixed into every roll)
    uint256 private _rngCounter;

    // ----------------------------------------------------------
    // Events (lore-named)
    // ----------------------------------------------------------

    event Summoned(address indexed minter, uint256 indexed tokenId, uint8 tier);
    /// @dev Emitted on a Crossing attempt. fuelId is burned; ascended=true means main rose a tier.
    event Sacrificed(address indexed owner, uint256 indexed mainId, uint256 indexed fuelId, bool ascended, uint8 newTier, uint256 payoutWei);
    event EvolveStatusUpdated(bool active);
    event EthUsdRateUpdated(uint256 newRate);
    event SaleStatusUpdated(bool active);
    event PriceBpsUpdated(uint256 newPriceBps);
    event RoyaltyBpsUpdated(uint256 newRoyaltyBps);
    event MaxMintsPerWalletUpdated(uint256 newMax);
    event MintCooldownUpdated(uint256 newCooldownSeconds);
    event PassSignerUpdated(address newSigner);
    event FreeCurveUpdated(uint256 startBps, uint256 endBps);

    // ----------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------

    constructor(uint256 initialEthUsdRate)
        ERC721("Obol and Ash", "SOUL")
        Ownable(msg.sender)
    {
        require(initialEthUsdRate > 0, "rate=0");
        ethUsdRate = initialEthUsdRate;

        // Adjustable economy defaults (owner can change anytime, no redeploy).
        priceBps = Types.PRICE_BPS;     // $0.25
        royaltyBps = Types.ROYALTY_BPS; // 10% default — owner can drop to 0 anytime
        maxMintsPerWallet = 10;          // hard cap per wallet
        mintCooldown = 5;                // seconds between mints
        passSigner = msg.sender;         // owner is the default Soul Passcode signer

        // Launch curve: ~35% early → ~25% late (averages ~30% free / ~70% paid). Paid-heavy
        // "test the water" start; owner can loosen toward free-favored anytime via setFreeCurve.
        freeStartBps = 3500;
        freeEndBps = 2500;

        // Evolve phase: OFF at launch (turn on later as phase 2). Rare fail-jackpot.
        evolveActive = false;
        maxAscensions = 0;               // 0 = unlimited
        evolveHalfBps = 800;             // 8% chance: half the fuel's mint price back
        evolveDoubleBps = 200;           // 2% chance: double it. 90% = nothing.

        _collectionSeed = keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            msg.sender,
            address(this)
        ));
        emit EthUsdRateUpdated(initialEthUsdRate);
    }

    // ----------------------------------------------------------
    // Mint (Summon)
    // ----------------------------------------------------------

    /// @notice FALLBACK MINT (permissionless, no backend). Summon `quantity` souls; each
    ///         soul independently rolls the decaying free chance on-chain. Free souls cost
    ///         nothing — the caller sends the full price up front and is auto-refunded for
    ///         every free soul (and any unminted soul if the collection sells out mid-batch).
    ///         This path keeps minting alive even if the website/backend is down.
    /// @param quantity 1..MAX_QTY_PER_TX
    function summon(uint8 quantity) external payable nonReentrant {
        require(saleActive, "sale closed");
        require(quantity > 0 && quantity <= Types.MAX_QTY_PER_TX, "bad quantity");
        require(block.timestamp >= lastMintAt[msg.sender] + mintCooldown, "cooldown");
        require(mintedPerWallet[msg.sender] + quantity <= maxMintsPerWallet, "wallet cap");
        require(totalMinted < Types.TOTAL_SUPPLY, "sold out");

        uint256 perSoul = pricePerSoul();
        require(msg.value == perSoul * quantity, "wrong msg.value");

        lastMintAt[msg.sender] = block.timestamp;

        uint256 paidCount;
        uint256 mintedNow;
        for (uint8 i = 0; i < quantity; i++) {
            if (totalMinted >= Types.TOTAL_SUPPLY) break;

            // Free roll uses the CURRENT minted count, so the chance decays soul-by-soul.
            uint256 roll = _random("free") % 10_000;
            bool isFree = roll < _freeChanceBps(totalMinted);

            uint16 snapshot;
            if (isFree) {
                freeMinted++;
                snapshot = 0;
            } else {
                paidCount++;
                snapshot = uint16(priceBps);
            }

            uint256 tierRng = _random("tier");
            uint8 tier = Traits.rollTier(tierRng, mythicCount);
            _mintOne(msg.sender, tier, snapshot);
            mintedNow++;
        }

        mintedPerWallet[msg.sender] += mintedNow;

        // Refund free souls + any soul we couldn't mint (sold out mid-batch).
        uint256 owed = perSoul * paidCount;
        if (msg.value > owed) {
            _safeRefund(msg.sender, msg.value - owed);
        }
    }

    /// @notice FERRYMAN MINT (website path). Mint exactly one soul using a single-use Soul
    ///         Passcode signed by the backend `passSigner`. The passcode declares whether
    ///         this soul crosses FREE or PAID (the backend rolled the decaying curve). The
    ///         contract enforces the per-wallet cap and cooldown trustlessly, so the backend
    ///         stays stateless. Free => send 0; paid => send exactly pricePerSoul().
    /// @param isFree    whether this soul crosses free (true) or paid (false)
    /// @param mintIndex the wallet's mint slot this passcode is valid for (== mintedPerWallet).
    ///                  Binds the verdict to one slot so free passes can't be stockpiled.
    /// @param expires   unix timestamp after which the passcode is void
    /// @param nonce     unique per-passcode value (prevents collisions / replay)
    /// @param sig       passSigner's signature over the passcode digest
    function summonWithCode(bool isFree, uint256 mintIndex, uint256 expires, uint256 nonce, bytes calldata sig)
        external
        payable
        nonReentrant
    {
        require(saleActive, "sale closed");
        require(block.timestamp <= expires, "passcode expired");
        require(block.timestamp >= lastMintAt[msg.sender] + mintCooldown, "cooldown");
        require(mintedPerWallet[msg.sender] < maxMintsPerWallet, "wallet cap");
        require(mintedPerWallet[msg.sender] == mintIndex, "stale passcode");
        require(totalMinted < Types.TOTAL_SUPPLY, "sold out");

        bytes32 digest = passcodeDigest(msg.sender, isFree, mintIndex, expires, nonce);
        require(!passUsed[digest], "passcode used");
        require(_recover(digest, sig) == passSigner && passSigner != address(0), "bad passcode");
        passUsed[digest] = true;

        uint16 snapshot;
        if (isFree) {
            require(msg.value == 0, "free: send 0");
            freeMinted++;
            snapshot = 0;
        } else {
            uint256 perSoul = pricePerSoul();
            require(msg.value >= perSoul, "underpaid");
            snapshot = uint16(priceBps);
            if (msg.value > perSoul) _safeRefund(msg.sender, msg.value - perSoul);
        }

        lastMintAt[msg.sender] = block.timestamp;
        mintedPerWallet[msg.sender] += 1;

        uint256 tierRng = _random("tier");
        uint8 tier = Traits.rollTier(tierRng, mythicCount);
        _mintOne(msg.sender, tier, snapshot);
    }

    /// @notice The digest a Soul Passcode signs over. Bound to this contract + chain to
    ///         prevent cross-contract / cross-chain replay.
    function passcodeDigest(address minter, bool isFree, uint256 mintIndex, uint256 expires, uint256 nonce)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(address(this), block.chainid, minter, isFree, mintIndex, expires, nonce));
    }

    /// @dev Recover the signer of a raw (non-EIP-191) 65-byte signature over `digest`.
    function _recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        return ecrecover(digest, v, r, s);
    }

    function _mintOne(address to, uint8 tier, uint16 priceSnapshotBps) internal {
        uint256 tokenId = nextTokenId++;
        totalMinted++;

        if (tier == Types.TIER_MYTHIC) {
            mythicCount++;
        }

        // Instant reveal: roll full traits at mint time, seeded by per-collection seed + tokenId.
        uint256 baseSeed = uint256(keccak256(abi.encodePacked(_collectionSeed, tokenId)));
        Types.TokenData memory d = Traits.rollAll(tier, baseSeed);
        d.mintPriceSnapshotBps = priceSnapshotBps;
        d.ascensionCount = 0;

        _packed[tokenId] = Types.pack(d);
        _safeMint(to, tokenId);

        emit Summoned(to, tokenId, tier);
    }

    /// @notice Price for a single soul, in wei, at the current ETH/USD rate and priceBps.
    ///         Returns 0 when priceBps is 0 (owner set "free for all").
    function pricePerSoul() public view returns (uint256) {
        return (priceBps * 1 ether) / (10_000 * ethUsdRate);
    }

    /// @notice Read-only MAX cost for `quantity` souls (before free refunds).
    function costFor(uint8 quantity) public view returns (uint256) {
        return pricePerSoul() * uint256(quantity);
    }

    /// @notice Decaying free-mint chance (bps of 10000) at a given minted count.
    ///         Linear from freeStartBps (at 0 minted) to freeEndBps (at TOTAL_SUPPLY).
    ///         One continuous wave across the whole collection; random per soul.
    ///         Owner-adjustable via setFreeCurve. Never below freeEndBps, so the free
    ///         lottery survives to the last soul and minting never stalls.
    function _freeChanceBps(uint256 minted) internal view returns (uint256) {
        if (minted >= Types.TOTAL_SUPPLY) return freeEndBps;
        // start - (start - end) * minted / supply   (start >= end enforced by setter)
        uint256 drop = ((freeStartBps - freeEndBps) * minted) / Types.TOTAL_SUPPLY;
        return freeStartBps - drop;
    }

    /// @notice Current free-mint chance (bps of 10000) at the live minted count — for the UI meter.
    function currentFreeChanceBps() external view returns (uint256) {
        return _freeChanceBps(totalMinted);
    }

    /// @notice Free chance (bps) at an arbitrary minted count — lets the UI render the full curve.
    function freeChanceBpsAt(uint256 minted) external view returns (uint256) {
        return _freeChanceBps(minted);
    }

    // ----------------------------------------------------------
    // Crossing (burn-to-evolve)
    // ----------------------------------------------------------

    /// @notice THE CROSSING (Sacrifice). Burn a `fuelId` soul to attempt evolving `mainId`
    ///         up one tier. The fuel is ALWAYS consumed; the main is NEVER burned.
    ///         Success → main ascends in place (same tokenId). Fail → main stays untouched.
    ///         A fail pays ETH back ONLY when BOTH souls were paid mints, and even then only
    ///         on a rare jackpot roll: half or double the burned fuel's mint price; else nothing.
    function attemptCrossing(uint256 mainId, uint256 fuelId) external nonReentrant {
        require(evolveActive, "evolve closed");
        require(mainId != fuelId, "same token");
        require(ownerOf(mainId) == msg.sender, "not main owner");
        require(ownerOf(fuelId) == msg.sender, "not fuel owner");

        Types.TokenData memory m = _unpacked(mainId);
        require(m.tier < Types.TIER_MYTHIC, "mythic is terminal");

        uint8 newTier = m.tier + 1;
        // Guard scarcity BEFORE consuming fuel (a revert leaves the fuel intact).
        if (newTier == Types.TIER_MYTHIC) {
            require(mythicCount < Types.MYTHIC_CAP, "mythic cap reached");
        }
        if (maxAscensions != 0) {
            require(ascensionCount < maxAscensions, "ascension cap");
        }

        // Snapshot fuel data before burning (needed for the paid/paid payout basis).
        Types.TokenData memory f = _unpacked(fuelId);
        bool bothPaid = (m.mintPriceSnapshotBps > 0) && (f.mintPriceSnapshotBps > 0);
        uint16 fuelBps = f.mintPriceSnapshotBps;

        // Burn the fuel soul (the sacrifice) — always.
        delete _packed[fuelId];
        _burn(fuelId);

        uint16 failBps = _breakBps(m.tier);
        uint256 roll = _random("cross") % 10_000;

        if (roll >= failBps) {
            // SUCCESS — ascend the main soul in place, keeping its tokenId.
            ascensionCount++;
            if (newTier == Types.TIER_MYTHIC) mythicCount++;
            uint256 seed = uint256(keccak256(abi.encodePacked(_collectionSeed, mainId, "ascend", m.ascensionCount + 1)));
            Types.TokenData memory n = Traits.rollAll(newTier, seed);
            n.mintPriceSnapshotBps = m.mintPriceSnapshotBps;
            n.ascensionCount = m.ascensionCount + 1;
            _packed[mainId] = Types.pack(n);
            emit Sacrificed(msg.sender, mainId, fuelId, true, newTier, 0);
            emit MetadataUpdate(mainId);
            return;
        }

        // FAIL — main stays. Rare ETH echo only when BOTH souls were paid mints.
        // BEST-EFFORT: the echo pays only if the treasury can cover it. If the owner has
        // withdrawn the funds, the Crossing STILL completes (fuel burned, main preserved) —
        // the holder simply receives nothing. The payout NEVER blocks or reverts evolution.
        uint256 payoutWei = 0;
        if (bothPaid) {
            uint256 jackpot = _random("payout") % 10_000;
            uint256 basis = (uint256(fuelBps) * 1 ether) / (10_000 * ethUsdRate); // burned fuel's mint price
            uint256 intended;
            if (jackpot < evolveDoubleBps) {
                intended = basis * 2;
            } else if (jackpot < evolveDoubleBps + evolveHalfBps) {
                intended = basis / 2;
            }
            if (intended > 0 && address(this).balance >= intended) {
                (bool ok, ) = payable(msg.sender).call{value: intended}("");
                if (ok) payoutWei = intended; // credited only on success; otherwise silent
            }
        }
        emit Sacrificed(msg.sender, mainId, fuelId, false, m.tier, payoutWei);
    }

    function _breakBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 0) return Types.BREAK_BPS_T0;
        if (tier == 1) return Types.BREAK_BPS_T1;
        if (tier == 2) return Types.BREAK_BPS_T2;
        if (tier == 3) return Types.BREAK_BPS_T3;
        if (tier == 4) return Types.BREAK_BPS_T4;
        revert("no break bps");
    }

    // ----------------------------------------------------------
    // Randomness (free, onchain-pure)
    // ----------------------------------------------------------

    function _random(string memory salt) internal returns (uint256) {
        _rngCounter++;
        return uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            msg.sender,
            _rngCounter,
            salt
        )));
    }

    // ----------------------------------------------------------
    // tokenURI / royalty
    // ----------------------------------------------------------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return Metadata.buildTokenURI(tokenId, _unpacked(tokenId));
    }

    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = owner();
        royaltyAmount = (salePrice * royaltyBps) / 10_000;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId
            || interfaceId == bytes4(0x49064906) // ERC-4906
            || super.supportsInterface(interfaceId);
    }

    // ----------------------------------------------------------
    // Admin
    // ----------------------------------------------------------

    function setEthUsdRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "rate=0");
        ethUsdRate = newRate;
        emit EthUsdRateUpdated(newRate);
    }

    function setSaleActive(bool active) external onlyOwner {
        saleActive = active;
        emit SaleStatusUpdated(active);
    }

    /// @notice Adjust the price per soul (bps of USD). 2500 = $0.25, 1000 = $0.10, 0 = free for all.
    /// @dev Capped at 65535 so it fits the per-token uint16 price snapshot.
    function setPriceBps(uint256 newPriceBps) external onlyOwner {
        require(newPriceBps <= 65535, "priceBps too high");
        priceBps = newPriceBps;
        emit PriceBpsUpdated(newPriceBps);
    }

    /// @notice Adjust the EIP-2981 royalty (bps). 1000 = 10%, 0 = royalties off. Capped at 10%.
    function setRoyaltyBps(uint256 newRoyaltyBps) external onlyOwner {
        require(newRoyaltyBps <= 1000, "royalty max 10%");
        royaltyBps = newRoyaltyBps;
        emit RoyaltyBpsUpdated(newRoyaltyBps);
    }

    /// @notice Adjust the hard cap of total souls a single wallet may mint.
    function setMaxMintsPerWallet(uint256 newMax) external onlyOwner {
        require(newMax > 0, "max=0");
        maxMintsPerWallet = newMax;
        emit MaxMintsPerWalletUpdated(newMax);
    }

    /// @notice Adjust the anti-spam cooldown (seconds) between a wallet's mints.
    function setMintCooldown(uint256 newCooldownSeconds) external onlyOwner {
        mintCooldown = newCooldownSeconds;
        emit MintCooldownUpdated(newCooldownSeconds);
    }

    /// @notice Set the backend signer that authorizes Soul Passcodes for the Ferryman path.
    function setPassSigner(address newSigner) external onlyOwner {
        passSigner = newSigner;
        emit PassSignerUpdated(newSigner);
    }

    /// @notice Adjust the decaying free curve. startBps (at 0 minted) → endBps (at sellout).
    ///         start >= end, both <= 10000. Average ≈ total free % of supply.
    function setFreeCurve(uint256 startBps, uint256 endBps) external onlyOwner {
        require(startBps <= 10_000 && endBps <= startBps, "bad curve");
        freeStartBps = startBps;
        freeEndBps = endBps;
        emit FreeCurveUpdated(startBps, endBps);
    }

    /// @notice Open or close the Evolve (Crossing) phase — independent of the mint sale.
    function setEvolveActive(bool active) external onlyOwner {
        evolveActive = active;
        emit EvolveStatusUpdated(active);
    }

    /// @notice Cap total Ascensions (0 = unlimited) to keep higher tiers scarce.
    function setMaxAscensions(uint256 cap) external onlyOwner {
        maxAscensions = cap;
    }

    /// @notice Adjust the fail-echo odds (bps). half + double must be <= 10000.
    function setEvolveOdds(uint256 halfBps, uint256 doubleBps) external onlyOwner {
        require(halfBps + doubleBps <= 10_000, "bad odds");
        evolveHalfBps = halfBps;
        evolveDoubleBps = doubleBps;
    }

    /// @notice Owner-only reserve mint for team/dev allocation, giveaways, and partnerships.
    /// @dev Bypasses the sale gate and payment. Respects the 10,000 supply cap. Does NOT
    ///      consume the public free-mint pool. Tiers roll normally so reserve tokens are
    ///      indistinguishable from public mints. Price snapshot is 0 (free allocation).
    ///      Large batches may exceed block gas — batch across calls if needed.
    /// @param to        recipient of the reserved tokens
    /// @param quantity  number of tokens to mint (>= 1)
    function devMint(address to, uint16 quantity) external onlyOwner nonReentrant {
        require(to != address(0), "zero addr");
        require(quantity > 0, "qty=0");
        require(totalMinted + quantity <= Types.TOTAL_SUPPLY, "exceeds supply");

        for (uint16 i = 0; i < quantity; i++) {
            uint256 tierRng = _random("devtier");
            uint8 tier = Traits.rollTier(tierRng, mythicCount);
            _mintOne(to, tier, 0);
        }
    }

    /// @notice Withdraw the FULL treasury balance to `to`. Total owner control, no reserve.
    ///         Safe to call anytime — the evolve echo is best-effort, so an empty treasury
    ///         never blocks a Crossing (the holder just receives nothing on a fail-echo).
    function withdraw(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "zero addr");
        uint256 bal = address(this).balance;
        require(bal > 0, "nothing to withdraw");
        (bool ok, ) = to.call{value: bal}("");
        require(ok, "withdraw failed");
    }

    /// @notice Disabled. Renouncing would permanently lock every setter, withdrawals, and
    ///         any treasury ETH. Transfer ownership to a new secure wallet instead.
    function renounceOwnership() public view override onlyOwner {
        revert("renounce disabled");
    }

    // ----------------------------------------------------------
    // Internal helpers
    // ----------------------------------------------------------

    function _unpacked(uint256 tokenId) internal view returns (Types.TokenData memory) {
        return Types.unpack(_packed[tokenId]);
    }

    function _safeRefund(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "refund failed");
    }

    // ----------------------------------------------------------
    // Public view helpers (for website wiring)
    // ----------------------------------------------------------

    /// @notice Returns the unpacked token data for a given tokenId (must exist).
    function getTokenData(uint256 tokenId) external view returns (Types.TokenData memory) {
        _requireOwned(tokenId);
        return _unpacked(tokenId);
    }

    receive() external payable {}
}
