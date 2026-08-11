//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import 'solana';

struct AuctionMetadata {
    bytes32 termAuctionId;
    uint256 auctionClearingRate;
    uint256 auctionClearingBlockTimestamp;
}

contract AuctionMetadataStore {
    mapping(bytes32 => AuctionMetadata) private auctions;

    function storeAuctionMetadata(AuctionMetadata calldata metadata) external {
        auctions[metadata.termAuctionId] = metadata;
    }

    function getAuctionMetadata(bytes32 termAuctionId) external view returns (AuctionMetadata memory) {
        return auctions[termAuctionId];
    }
}