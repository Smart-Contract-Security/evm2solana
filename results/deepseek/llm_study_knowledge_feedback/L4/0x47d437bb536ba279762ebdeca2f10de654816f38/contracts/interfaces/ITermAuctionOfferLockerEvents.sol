//SPDX-License-Identifier: CC-BY-NC-ND-4.0

/// @notice ITermAuctionOfferLockerEvents is an interface that defines all events emitted by the Term Auction Offer Locker.
interface ITermAuctionOfferLockerEvents {
    event TermAuctionOfferLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionOfferLocker,
        uint64 auctionStartTime,
        uint64 revealTime,
        uint64 maxOfferPrice,
        uint64 minimumTenderAmount
    );

    event OfferLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address offeror,
        bytes32 offerPrice,
        uint64 amount,
        address token,
        address referralAddress
    );

    event OfferRevealed(bytes32 termAuctionId, bytes32 id, uint64 offerPrice);

    event OfferUnlocked(bytes32 termAuctionId, bytes32 id);

    event OfferLockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event OfferLockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);

    event OfferUnlockingPaused(bytes32 termAuctionId, bytes32 termRepoId);

    event OfferUnlockingUnpaused(bytes32 termAuctionId, bytes32 termRepoId);
}