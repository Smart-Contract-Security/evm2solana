//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import 'solana';

struct AuctionMetadata {
    bytes32 termAuctionId;
    uint256 auctionClearingRate;
    uint256 auctionClearingBlockTimestamp;
}