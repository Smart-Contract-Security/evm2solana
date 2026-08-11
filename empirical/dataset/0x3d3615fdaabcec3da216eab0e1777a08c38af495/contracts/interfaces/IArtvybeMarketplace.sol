// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IArtvybeMarketplace {
    enum ListingType { FixedPrice, EnglishAuction }
    
    struct Bidder {
        address bidder;
        uint256 bidAmount;
    }
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        ListingType listingType;
        uint256 price;
        address paymentCurrency; // address(0) for native token, ERC20 address for tokens
        uint256 startTime;
        uint256 endTime;
        Bidder[5] topBidders; // Top 5 bidders, sorted by bid amount (highest first)
        uint256 bidderCount; // Number of active bidders (0-5)
        bool active;
    }
    
    struct Offer {
        address offerer;
        address nftContract;
        uint256 tokenId;
        uint256 offerAmount;
        address paymentCurrency; 
        uint256 offerTime;
        uint256 expiryTime;
        bool active;
    }

    /// @notice One row of a multi-listing checkout. The caller's basket
    ///         on chain X is collapsed into a single `batchBuy` call by
    ///         the frontend; per-item `expectedPrice` + `expectedCurrency`
    ///         are passed so the contract can short-circuit any item whose
    ///         on-chain listing has drifted (cancel-and-relist races,
    ///         delistings, sniping, currency change). See `batchBuy`.
    struct BatchBuyItem {
        address nftContract;
        uint256 tokenId;
        uint256 expectedPrice;
        address expectedCurrency; // address(0) for native
    }

    // Events
    event FixedPriceListed(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 price,
        address paymentCurrency
    );
    
    event AuctionListed(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 reservePrice,
        address paymentCurrency,
        uint256 endTime
    );
    
    event ItemBought(
        address indexed buyer,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 price,
        address paymentCurrency
    );
    
    event BidPlaced(
        address indexed bidder,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 bidAmount,
        address paymentCurrency
    );
    
    event BidCancelled(
        address indexed bidder,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 bidAmount,
        address paymentCurrency
    );
    
    event AuctionFinalized(
        address indexed winner,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 finalPrice,
        address paymentCurrency
    );
    
    event ListingCancelled(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId
    );
    
    // Offer events
    event OfferMade(
        address indexed offerer,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 offerAmount,
        address paymentCurrency,
        uint256 expiryTime
    );
    
    event OfferAccepted(
        address indexed offerer,
        address indexed nftOwner,
        address indexed nftContract,
        uint256 tokenId,
        uint256 offerAmount,
        address paymentCurrency
    );
    
    event OfferRejected(
        address indexed offerer,
        address indexed nftContract,
        uint256 indexed tokenId
    );
    
    event OfferCancelled(
        address indexed offerer,
        address indexed nftContract,
        uint256 indexed tokenId
    );
    
    event AllOffersCancelled(
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 cancelledCount
    );

    /// @notice Emitted once at the end of a `batchBuy`, summarising the
    ///         outcome so the frontend can refresh the basket in one read.
    event BatchBuyExecuted(
        address indexed buyer,
        uint256 totalItems,
        uint256 boughtCount,
        uint256 skippedCount,
        uint256 nativeRefunded
    );

    /// @notice Emitted per skipped item in a non-strict `batchBuy`. The
    ///         reason is a short ASCII tag — see the constants in the
    ///         implementation (LISTING_INACTIVE, NOT_FIXED_PRICE,
    ///         PRICE_MISMATCH, CURRENCY_MISMATCH, SELF_PURCHASE).
    event BatchItemSkipped(
        address indexed buyer,
        address indexed nftContract,
        uint256 indexed tokenId,
        bytes32 reason
    );

    event PlatformTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event PlatformFeeUpdated(uint96 oldFeeBps, uint96 newFeeBps);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event CollectionRoyaltyUpdated(address indexed collection, address indexed receiver, uint96 bps);
    event CollectionRoyaltyCleared(address indexed collection);
    event CollectionRoyaltyAdminUpdated(address indexed collection, address indexed admin);

    // Core functions
    function listFixedPrice(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address paymentCurrency
    ) external;
    
    function listAuction(
        address nftContract,
        uint256 tokenId,
        uint256 reservePrice,
        address paymentCurrency,
        uint256 duration
    ) external;
    
    function buyFixed(address nftContract, uint256 tokenId) external payable;

    /**
     * @notice Atomically attempt to buy a basket of fixed-price listings
     *         on this chain. Multi-currency-safe: each item's payment is
     *         settled in its own currency (native via shared `msg.value`
     *         tally; ERC20 via per-item `transferFrom` from the caller).
     *
     *         If `strict` is false (recommended), an item that has gone
     *         stale (delisted, sold, currency or price drifted, or whose
     *         seller is the caller) is skipped — the rest of the batch
     *         still settles, and any unspent native is refunded at the
     *         end of the tx.
     *
     *         If `strict` is true, any single failure reverts the entire
     *         tx — caller's gas is wasted but settlement is atomic.
     *
     *         Cross-chain note: this function is per-chain only. A basket
     *         spanning multiple chains is N separate `batchBuy` calls,
     *         one per chain.
     */
    function batchBuy(BatchBuyItem[] calldata items, bool strict) external payable;

    function placeBid(address nftContract, uint256 tokenId, uint256 bidAmount) external payable;
    function cancelBid(address nftContract, uint256 tokenId) external;
    function finalizeAuction(address nftContract, uint256 tokenId) external;
    function cancelListing(address nftContract, uint256 tokenId) external;
    
    // Offer functions
    function makeOffer(
        address nftContract,
        uint256 tokenId,
        address paymentCurrency,
        uint256 offerAmount,
        uint256 offerDuration
    ) external payable;
    
    function acceptOffer(
        address nftContract,
        uint256 tokenId,
        address offerer
    ) external;
    
    function rejectOffer(
        address nftContract,
        uint256 tokenId,
        address offerer
    ) external;
    
    function cancelOffer(
        address nftContract,
        uint256 tokenId
    ) external;
    
    // View functions
    function getListing(address nftContract, uint256 tokenId) external view returns (Listing memory);
    function isListingActive(address nftContract, uint256 tokenId) external view returns (bool);
    function getOffer(address nftContract, uint256 tokenId, address offerer) external view returns (Offer memory);
    function getActiveOffers(address nftContract, uint256 tokenId) external view returns (Offer[] memory);
    
    // Admin functions
    function setAdmin(address newAdmin) external;
    function getAdmin() external view returns (address);
    function setPlatformTreasury(address newTreasury) external;
    function setPlatformFeeBps(uint96 newFeeBps) external;
    function setPaused(bool paused) external;
    function setCollectionRoyaltyAdmin(address collection, address adminWallet) external;
    function configureCollectionRoyalty(address collection, address receiver, uint96 bps) external;
    function clearCollectionRoyalty(address collection) external;
    function getCollectionRoyalty(address collection) external view returns (address receiver, uint96 bps, bool enabled);
    function cancelAllOffers(address nftContract, uint256 tokenId) external;
    function recoverETH(address to, uint256 amount) external;
    function recoverERC20(address token, address to, uint256 amount) external;
    function recoverNFT(address nftContract, uint256 tokenId, address to) external;

    // Pull-payment ledger
    function withdrawPendingRefund(address currency) external;
    function getPendingRefund(address currency, address user) external view returns (uint256);
    function totalOwed(address currency) external view returns (uint256);
    function pendingRefunds(address currency, address user) external view returns (uint256);

    // Royalty admin clear
    function clearCollectionRoyaltyAdmin(address collection) external;

    // Payment-currency allowlist (per-chain stablecoin configuration)
    event PaymentCurrencyConfigured(address indexed currency, bool allowed, uint256 minBidIncrement);

    function setPaymentCurrency(address currency, bool allowed, uint256 minBidIncrement) external;
    function paymentCurrencies(address currency) external view returns (bool allowed, uint256 minBidIncrement);
    function minBidIncrementFor(address currency) external view returns (uint256);
} 