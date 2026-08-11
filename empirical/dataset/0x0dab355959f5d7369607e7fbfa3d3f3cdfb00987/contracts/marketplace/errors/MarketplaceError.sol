// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Reverts when the token is not whitelisted.
error ErrorTokenNotWhitelisted(address _token);

/// @dev Reverts when the payment token is not whitelisted.
error ErrorPaymentTokenNotWhitelisted(address _token);

/// @dev Reverts when the listing is not active.
error ErrorListingNotActive(bytes32 _listingId);

/// @dev Reverts when an invalid price is provided.
error ErrorInvalidPrice();

/// @dev Reverts when an invalid amount is provided.
error ErrorInvalidAmount();

/// @dev Reverts when the caller does not have enough balance.
error ErrorCallerNotEnoughBalance(
    address _caller,
    address _token,
    uint256 _amount,
    uint256 _balance
);

/// @dev Reverts when the caller is not the seller of the token.
error ErrorCallerNotSeller(address _caller, bytes32 _lisingId);

/// @dev Reverts when the auction doesn't have a buy-out price.
error ErrorNoBuyoutPrice(bytes32 _lisingId);

/// @dev Reverts when the listing is not of type Auction.
error ErrorListingNotAuction(bytes32 _lisingId);

/// @dev Reverts when the auction has already ended.
error ErrorAuctionEnded(bytes32 _lisingId);

/// @dev Reverts when the listing end time has not been met.
error ErrorlistingEndTimeNotMet(bytes32 _lisingId);

/// @dev Reverts when the auction is not claimable.
error ErrorAuctionNotClaimable(bytes32 _listingId);

/// @dev Reverts when the bid is too low.
error ErrorBidTooLow(bytes32 _lisingId, uint256 _bid);

/// @dev Reverts when an invalid address is provided.
error ErrorInvalidAddress();

/// @dev Reverts when native payment tokens are not allowed.
error ErrorNativePaymentTokenNotAllowed();

/// @dev Reverts when the token type is invalid.
error ErrorInvalidTokenType();

/// @dev Reverts when a zero address is provided where it is not allowed.
error ErrorAddressZero();

/// @dev Reverts when the listing duration is invalid.
error ErrorInvalidListingDuration();

/// @dev Thrown when trying to change same value.
error ErrorSameValue();

/// @dev Thrown when trying to cancel locked listing.
error ErrorListingIsLocked();

/// @dev Thrown when fee basis points is invalid.
error ErrorInvalidFeeBasisPoints();

/// @dev Thrown when claim period is invalid.
error ErrorInvalidClaimPeriod();

/// @dev Thrown when trying to auction an auction that reached the target bid.
error ErrorCannotCancelAuction();

/// @dev Thrown when user has no bid for this auction.
error ErrorNoUserBid(bytes32 _lisingId);