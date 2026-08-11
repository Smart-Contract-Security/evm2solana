//SPDX-License-Identifier: CC-BY-NC-ND-4.0

/// @notice ITermAuctionBidLockerEvents is an interface that defines all events emitted by the Term Auction Bid Locker.
interface ITermAuctionBidLockerEvents {
    event TermAuctionBidLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionBidLocker,
        uint64 auctionStartTime,
        uint64 revealTime,
        uint64 maxBidPrice,
        uint64 minimumTenderAmount,
        uint64 dayCountFractionMantissa
    );

    event BidLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address bidder,
        bytes32 bidPrice,
        uint64 amount,
        address token,
        address[] collateralTokens,
        uint64[] collateralAmounts,
        bool isRollover,
        address rolloverPairOffTermRepoServicer,
        address referralAddress
    );

    event BidRevealed(bytes32 termAuctionId, bytes32 id, uint64 bidPrice);

    event BidUnlocked(bytes32 termAuctionId, bytes32 id);

    event BidInShortfall(bytes32 termAuctionId, bytes32 id);

    event BidLockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event BidLockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);

    event BidUnlockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event BidUnlockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);
}