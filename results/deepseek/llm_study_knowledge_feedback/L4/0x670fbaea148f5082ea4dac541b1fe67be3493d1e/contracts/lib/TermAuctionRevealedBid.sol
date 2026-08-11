@program_id("AddressOfTermAuctionRevealedBid")
contract TermAuctionRevealedBid {
    struct RevealedBid {
        bytes32 id;
        address bidder;
        uint64 bidPriceRevealed;
        uint64 amount;
        uint64[] collateralAmounts;
        address purchaseToken;
        address[] collateralTokens;
        bool isRollover;
        address rolloverPairOffTermRepoServicer;
    }
}