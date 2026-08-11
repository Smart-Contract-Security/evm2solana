// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

abstract contract MarketplaceEvents {
  /// @dev Emitted when a new listing is created.
    event ListingCreated(
        bytes32 listingId,
        uint256 tokenId,
        address indexed seller,
        address indexed tokenAddress,
        address indexed paymentToken,
        uint256 amount,
        uint256 price,
        uint8 tokenType,
        uint8 listingType,
        uint64 listingEndTime,
        uint64 timestamp
    );

    /// @dev Emitted when a listing is canceled.
    event ListingCancelled(
        bytes32 listingId,
        uint256 indexed tokenId,
        address indexed tokenAddress,
        address indexed seller,
        uint64 timestamp
    );

    /// @dev Emitted when a listing is sold.
    event ListingSold(
        bytes32 listingId,
        uint256 tokenId,
        address indexed seller,
        address indexed tokenAddress,
        address indexed paymentToken,
        address buyer,
        uint256 amount,
        uint256 price,
        uint64 timestamp
    );

    /// @dev Emitted when an auction ends.
    event AuctionEnded(
        bytes32 listingId,
        uint256 tokenId,
        address indexed tokenAddress,
        address indexed winner,
        uint256 price,
        uint64 timestamp
    );

    /// @dev Emitted when a user claimed his bid.
    event BidClaimed(
        bytes32 listingId,
        address indexed bidder,
        address indexed paymentToken,
        uint256 amount,
        uint64 timestamp
    );

    /// @dev Emitted when the fee basis points are updated.
    // event FeeUpdated(uint256 indexed newFeeBasisPoints);

    /// @dev Emitted when the claim period is updated.
    // event ClaimPeriodUpdated(uint256 indexed newClaimPeriod);

    /// @dev Emitted when the tax receiver address is updated.
    event TaxReceiverUpdated(address indexed newTaxReceiver);

    /// @dev Emitted when a bid is placed in an auction.
    event BidPlaced(
        bytes32 listingId,
        uint256 tokenId,
        address indexed tokenAddress,
        address indexed bidder,
        uint256 price,
        uint64 timestamp
    );

    /// @dev Emitted when a token is added.
    event TokenAdded(address tokenAddress, uint64 timestamp);

    /// @dev Emitted when a token is removed.
    event TokenRemoved(address tokenAddress, uint64 timestamp);

    /// @dev Emitted when bulk token is added.
    event BulkTokenAdded(address[] tokenAddress, uint64 timestamp);

    /// @dev Emitted when bulk token is removed.
    event BulkTokenRemoved(address[] tokenAddress, uint64 timestamp);

    /// @dev Emitted when a payment token is added.
    event PaymentTokenAdded(address tokenAddress, uint64 timestamp);

    /// @dev Emitted when a payment token is removed.
    event PaymentTokenRemoved(address tokenAddress, uint64 timestamp);

    /// @dev Emitted when bulk payment token is added.
    event BulkPaymentTokenAdded(address[] tokenAddress, uint64 timestamp);

    /// @dev Emitted when bulk payment token is removed.
    event BulkPaymentTokenRemoved(address[] tokenAddress, uint64 timestamp);
}