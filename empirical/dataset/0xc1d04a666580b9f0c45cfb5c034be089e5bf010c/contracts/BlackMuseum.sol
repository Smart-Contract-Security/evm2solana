// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title THE BLACK MUSEUM
 * @notice Generative ERC-721 (supply 10,000), open mint, flat-priced.
 *
 * Design:
 *  - Every token's generative `hash` is committed BEFORE the sale via a Merkle
 *    tree whose leaves bind (tokenId, tier, priceWei). The contract stores only
 *    the root, so the team cannot re-assign rarity or price after commit.
 *  - The site/Worker hands a buyer an unminted tokenId plus its Merkle proof;
 *    the contract verifies the proof and the payment.
 *  - Pricing is flat: paid tokens cost `priceWei` (0.001 ETH). ~1,000 of the
 *    weakest generations are FREE (priceWei == 0) with no balance requirement.
 *  - Per-wallet limits: max 1 FREE token and max 13 PAID tokens per wallet.
 *  - Mint is OPEN to everyone once the owner flips the phase to Public. There is
 *    no allowlist.
 *  - Anomaly (1/1) tokens are excluded from the public Merkle and are sold via an
 *    on-chain English auction (`startAuction` / `bid` / `settleAuction`) or minted
 *    by the owner via `reserve` (team / giveaways).
 */
contract BlackMuseum is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 10_000;
    uint8 public constant ANOMALY_TIER = 7;

    enum Phase {
        Paused,
        Public
    }

    Phase public phase = Phase.Paused;

    /// leaf = keccak256(abi.encodePacked(tokenId, tier, priceWei))
    bytes32 public priceMerkleRoot;
    /// commitment to the full tokenId -> generative hash list (revealed after sellout)
    bytes32 public provenanceHash;

    /// Per-wallet mint caps.
    uint256 public maxFreePerWallet = 1;
    uint256 public maxPaidPerWallet = 13;

    uint256 public totalMinted;
    bool public revealed;
    string private _baseTokenURI;
    string private _unrevealedURI;

    mapping(uint256 => bool) public minted;
    mapping(address => uint256) public freeMintedBy;
    mapping(address => uint256) public paidMintedBy;

    // ---- 1/1 anomaly auctions ----
    struct Auction {
        uint64 endTime;
        uint96 minBid; // reserve / starting price
        address highestBidder;
        uint96 highestBid;
        bool active;
        bool settled;
    }

    /// Anti-snipe: a bid in the final window extends the auction by this much.
    uint64 public constant AUCTION_EXTENSION = 10 minutes;

    mapping(uint256 => Auction) public auctions;
    /// Outbid funds are held for withdrawal (pull-payment, avoids griefing).
    mapping(address => uint256) public pendingReturns;

    event Minted(address indexed to, uint256 indexed tokenId, uint8 tier, uint256 pricePaid);
    event PhaseChanged(Phase phase);
    event Revealed(string baseURI);
    event AuctionStarted(uint256 indexed tokenId, uint96 minBid, uint64 endTime);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint96 amount, uint64 endTime);
    event AuctionSettled(uint256 indexed tokenId, address indexed winner, uint256 amount);
    event AuctionCancelled(uint256 indexed tokenId);

    constructor(address royaltyReceiver, uint96 royaltyFeeBps)
        ERC721("The Black Museum", "BLACKMUSEUM")
        Ownable(msg.sender)
    {
        require(royaltyReceiver != address(0), "receiver=0");
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeBps);
    }

    // ---------------------------------------------------------------------
    // Minting (open to everyone)
    // ---------------------------------------------------------------------

    /**
     * @param tokenId    the specific token being claimed (1..MAX_SUPPLY)
     * @param tier       tier code (0=FREE, 1..6=I..VI) — bound in the leaf
     * @param priceWei   price for this token (0 for FREE, 0.001 ETH otherwise) — bound in the leaf
     * @param priceProof Merkle proof for (tokenId, tier, priceWei)
     */
    function mint(
        uint256 tokenId,
        uint8 tier,
        uint256 priceWei,
        bytes32[] calldata priceProof
    ) external payable nonReentrant {
        require(phase == Phase.Public, "sale not open");
        require(msg.sender == tx.origin, "no contracts");
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "bad tokenId");
        require(!minted[tokenId], "already minted");
        require(totalMinted < MAX_SUPPLY, "sold out");

        bytes32 leaf = keccak256(abi.encodePacked(tokenId, tier, priceWei));
        require(MerkleProof.verify(priceProof, priceMerkleRoot, leaf), "bad price proof");

        if (priceWei == 0) {
            require(msg.value == 0, "free token");
            require(freeMintedBy[msg.sender] < maxFreePerWallet, "free limit reached");
            unchecked {
                freeMintedBy[msg.sender] += 1;
            }
        } else {
            require(msg.value == priceWei, "wrong price");
            require(paidMintedBy[msg.sender] < maxPaidPerWallet, "paid limit reached");
            unchecked {
                paidMintedBy[msg.sender] += 1;
            }
        }

        minted[tokenId] = true;
        unchecked {
            totalMinted += 1;
        }
        _safeMint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, tier, priceWei);
    }

    /// @notice Owner mint for reserved tokens (team / giveaways / settled anomalies).
    function reserve(address to, uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            require(id >= 1 && id <= MAX_SUPPLY, "bad tokenId");
            require(!minted[id], "already minted");
            require(!auctions[id].active, "auction live");
            minted[id] = true;
            unchecked {
                totalMinted += 1;
            }
            _safeMint(to, id);
            emit Minted(to, id, ANOMALY_TIER, 0);
        }
    }

    // ---------------------------------------------------------------------
    // 1/1 Anomaly auctions
    // ---------------------------------------------------------------------

    /// @notice Owner opens an English auction for a (so-far unminted) 1/1 anomaly token.
    function startAuction(uint256 tokenId, uint96 minBid, uint64 duration) external onlyOwner {
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "bad tokenId");
        require(!minted[tokenId], "already minted");
        require(!auctions[tokenId].active, "auction live");
        require(duration > 0, "bad duration");
        uint64 end = uint64(block.timestamp) + duration;
        auctions[tokenId] = Auction({
            endTime: end,
            minBid: minBid,
            highestBidder: address(0),
            highestBid: 0,
            active: true,
            settled: false
        });
        emit AuctionStarted(tokenId, minBid, end);
    }

    /// @notice Place a bid on a live anomaly auction. Outbid funds are withdrawable.
    function bid(uint256 tokenId) external payable nonReentrant {
        Auction storage a = auctions[tokenId];
        require(a.active && !a.settled, "no auction");
        require(block.timestamp < a.endTime, "auction ended");
        require(msg.value <= type(uint96).max, "bid too large");
        uint96 amount = uint96(msg.value);

        if (a.highestBidder == address(0)) {
            require(amount >= a.minBid, "below reserve");
        } else {
            require(amount > a.highestBid, "bid too low");
            pendingReturns[a.highestBidder] += a.highestBid;
        }

        a.highestBidder = msg.sender;
        a.highestBid = amount;

        // anti-snipe extension
        if (a.endTime - block.timestamp < AUCTION_EXTENSION) {
            a.endTime = uint64(block.timestamp) + AUCTION_EXTENSION;
        }
        emit BidPlaced(tokenId, msg.sender, amount, a.endTime);
    }

    /// @notice Settle a finished auction: mint to the winner (proceeds stay in the contract).
    ///         Callable by anyone once the auction has ended.
    function settleAuction(uint256 tokenId) external nonReentrant {
        Auction storage a = auctions[tokenId];
        require(a.active && !a.settled, "no auction");
        require(block.timestamp >= a.endTime, "not ended");

        a.active = false;
        a.settled = true;
        address winner = a.highestBidder;

        if (winner != address(0) && !minted[tokenId]) {
            minted[tokenId] = true;
            unchecked {
                totalMinted += 1;
            }
            _safeMint(winner, tokenId);
            emit Minted(winner, tokenId, ANOMALY_TIER, a.highestBid);
            emit AuctionSettled(tokenId, winner, a.highestBid);
        } else {
            // no bids, or the token was already minted elsewhere -> refund any bid
            if (winner != address(0)) {
                pendingReturns[winner] += a.highestBid;
            }
            emit AuctionSettled(tokenId, address(0), 0);
        }
    }

    /// @notice Owner may cancel an auction that has not yet received a bid.
    function cancelAuction(uint256 tokenId) external onlyOwner {
        Auction storage a = auctions[tokenId];
        require(a.active && !a.settled, "no auction");
        require(a.highestBidder == address(0), "has bids");
        a.active = false;
        a.settled = true;
        emit AuctionCancelled(tokenId);
    }

    /// @notice Withdraw funds from being outbid in an auction.
    function withdrawRefund() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "nothing to withdraw");
        pendingReturns[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "refund failed");
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (!revealed) return _unrevealedURI;
        return string.concat(_baseTokenURI, tokenId.toString());
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setPhase(Phase p) external onlyOwner {
        phase = p;
        emit PhaseChanged(p);
    }

    function setPriceMerkleRoot(bytes32 root) external onlyOwner {
        priceMerkleRoot = root;
    }

    function setProvenanceHash(bytes32 h) external onlyOwner {
        provenanceHash = h;
    }

    function setMintLimits(uint256 maxFree, uint256 maxPaid) external onlyOwner {
        maxFreePerWallet = maxFree;
        maxPaidPerWallet = maxPaid;
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        _baseTokenURI = uri;
    }

    function setUnrevealedURI(string calldata uri) external onlyOwner {
        _unrevealedURI = uri;
    }

    function reveal(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
        revealed = true;
        emit Revealed(baseURI);
    }

    function setDefaultRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        _setDefaultRoyalty(receiver, feeBps);
    }

    function withdraw(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "to=0");
        (bool ok,) = to.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }
}