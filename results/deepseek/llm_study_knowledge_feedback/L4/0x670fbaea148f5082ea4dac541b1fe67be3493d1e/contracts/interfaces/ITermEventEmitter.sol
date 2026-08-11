//SPDX-License-Identifier: CC-BY-NC-ND-4.0

import {TermAuctionBid} from "../lib/TermAuctionBid.sol";

struct RepoTokenSwapData {
    bytes32 termRepoId;
    address purchaseToken;
    address maker;
    address taker;
    address makerToken;
    address takerToken;
    uint64 offerRate;
    uint64 makerTokenAmountFilled;
    uint64 takerTokenAmountFilled;
    uint64 proratedBorrowFee;
    address feeRecipient;
    uint64 originalOrderAmount;
    uint64 expiry;
    uint64 salt;
}

interface ITermAuctionEvents {
    function emitTermAuctionInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuction,
        uint64 auctionEndTime,
        address deployerWallet,
        string calldata version
    ) external;

    function emitBidAssigned(
        bytes32 termAuctionId,
        bytes32 id,
        uint64 amount
    ) external;

    function emitOfferAssigned(
        bytes32 termAuctionId,
        bytes32 id,
        uint64 amount
    ) external;

    function emitAuctionCompleted(
        bytes32 termAuctionId,
        uint64 timestamp,
        uint64 blockNumber,
        uint64 totalAssignedBids,
        uint64 totalAssignedOffers,
        uint64 clearingPrice
    ) external;

    function emitAuctionCancelled(
        bytes32 termAuctionId,
        bool nonViableAuction,
        bool auctionCancelledforWithdrawal
    ) external;

    function emitCompleteAuctionPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitCompleteAuctionUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;
}

interface ITermAuctionBidLockerEvents {
    function emitTermAuctionBidLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionBidLocker,
        uint64 auctionStartTime,
        uint64 revealTime,
        uint64 maxBidPrice,
        uint64 minimumTenderAmount,
        uint64 dayCountFractionMantissa
    ) external;

    function emitBidLocked(
        bytes32 termAuctionId,
        TermAuctionBid calldata bid,
        address referralAddress
    ) external;

    function emitBidRevealed(
        bytes32 termAuctionId,
        bytes32 id,
        uint64 bidPrice
    ) external;

    function emitBidUnlocked(bytes32 termAuctionId, bytes32 id) external;

    function emitBidInShortfall(bytes32 termAuctionId, bytes32 id) external;

    function emitBidLockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitBidLockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitBidUnlockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitBidUnlockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;
}

interface ITermAuctionOfferLockerEvents {
    function emitTermAuctionOfferLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionOfferLocker,
        uint64 auctionStartTime,
        uint64 revealTime,
        uint64 maxOfferPrice,
        uint64 minimumTenderAmount
    ) external;

    function emitOfferLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address offeror,
        bytes32 offerPrice,
        uint64 amount,
        address purchaseToken,
        address referralAddress
    ) external;

    function emitOfferRevealed(
        bytes32 termAuctionId,
        bytes32 id,
        uint64 offerPrice
    ) external;

    function emitOfferUnlocked(bytes32 termAuctionId, bytes32 id) external;

    function emitOfferLockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitOfferLockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitOfferUnlockingPaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;

    function emitOfferUnlockingUnpaused(
        bytes32 termAuctionId,
        bytes32 termRepoId
    ) external;
}

interface ITermRepoCollateralManagerEvents {
    function emitTermRepoCollateralManagerInitialized(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address[] calldata collateralTokens,
        uint64[] calldata initialCollateralRatios,
        uint64[] calldata maintenanceCollateralRatios,
        uint64[] calldata liquidatedDamagesSchedule
    ) external;

    function emitPairReopeningBidLocker(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address termAuctionBidLocker
    ) external;

    function emitCollateralLocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint64 amount
    ) external;

    function emitCollateralUnlocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint64 amount
    ) external;

    function emitLiquidation(
        bytes32 termRepoId,
        address borrower,
        address liquidator,
        uint64 closureAmount,
        address collateralToken,
        uint64 amountLiquidated,
        uint64 protocolSeizureAmount,
        bool defaultLiquidation
    ) external;

    function emitLiquidationPaused(bytes32 termRepoId) external;

    function emitLiquidationUnpaused(bytes32 termRepoId) external;
}

interface ITermRepoServicerEvents {
    function emitTermRepoServicerInitialized(
        bytes32 termRepoId,
        address termRepoServicer,
        address purchaseToken,
        uint64 maturityTimestamp,
        uint64 endOfRepurchaseWindow,
        uint64 redemptionTimestamp,
        uint64 servicingFee,
        address deployerWallet,
        string calldata version
    ) external;

    function emitReopeningOfferLockerPaired(
        bytes32 termRepoId,
        address termRepoServicer,
        address termAuctionOfferLocker,
        address termAuction
    ) external;

    function emitOfferLockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint64 amount
    ) external;

    function emitOfferUnlockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint64 amount
    ) external;

    function emitOfferFulfilled(
        bytes32 offerId,
        address offeror,
        uint64 purchasePrice,
        uint64 repurchasePrice,
        uint64 repoTokensMinted
    ) external;

    function emitTermRepoTokensRedeemed(
        bytes32 termRepoId,
        address redeemer,
        uint64 redemptionAmount,
        uint64 redemptionHaircut
    ) external;

    function emitBidFulfilled(
        bytes32 termRepoId,
        address bidder,
        uint64 purchasePrice,
        uint64 repurchasePrice,
        uint64 servicingFees
    ) external;

    function emitExposureOpenedOnRolloverNew(
        bytes32 termRepoId,
        address borrower,
        uint64 purchasePrice,
        uint64 repurchasePrice,
        uint64 servicingFees
    ) external;

    function emitExposureClosedOnRolloverExisting(
        bytes32 termRepoId,
        address borrower,
        uint64 amountRolled
    ) external;

    function emitRepurchasePaymentSubmitted(
        bytes32 termRepoId,
        address borrower,
        uint64 amount
    ) external;

    function emitMintExposureAccessGranted(
        bytes32 termRepoId,
        address authedUser
    ) external;

    function emitMintExposure(
        bytes32 termRepoId,
        address minter,
        uint64 netTokensReceived,
        uint64 servicingFeeTokens,
        uint64 repurchasePrice
    ) external;

    function emitBurnCollapseExposure(
        bytes32 termRepoId,
        address borrower,
        uint64 closeAmount
    ) external;
}

interface ITermRepoRolloverManagerEvents {
    function emitTermRepoRolloverManagerInitialized(
        bytes32 termRepoId,
        address rolloverManager
    ) external;

    function emitRolloverTermApproved(
        bytes32 termRepoId,
        bytes32 rolloverTermAuctionId
    ) external;

    function emitRolloverTermApprovalRevoked(
        bytes32 termRepoId,
        bytes32 rolloverTermAuctionId
    ) external;

    function emitRolloverElection(
        bytes32 termRepoId,
        bytes32 rolloverTermRepoId,
        address borrower,
        address rolloverAuction,
        uint64 rolloverAmount,
        bytes32 hashedBidPrice
    ) external;

    function emitRolloverCancellation(
        bytes32 termRepoId,
        address borrower
    ) external;

    function emitRolloverProcessed(
        bytes32 termRepoId,
        address borrower
    ) external;
}

interface ITermRepoLockerEvents {
    function emitTermRepoLockerInitialized(
        bytes32 termRepoId,
        address termRepoLocker
    ) external;

    function emitTermRepoLockerTransfersPaused(bytes32 termRepoId) external;

    function emitTermRepoLockerTransfersUnpaused(bytes32 termRepoId) external;
}

interface ITermRepoTokenEvents {
    function emitTermRepoTokenInitialized(
        bytes32 termRepoId,
        address termRepoToken,
        uint64 redemptionRatio
    ) external;

    function emitTermRepoTokenMintingPaused(bytes32 termRepoId) external;

    function emitTermRepoTokenMintingUnpaused(bytes32 termRepoId) external;

    function emitTermRepoTokenBurningPaused(bytes32 termRepoId) external;

    function emitTermRepoTokenBurningUnpaused(bytes32 termRepoId) external;
}

interface ITermIntentEvents {
    function emitIntentFilled(
        bytes32 orderHash,
        bytes32 termRepoId,
        address purchaseToken,
        address maker,
        address taker,
        address makerToken,
        address takerToken,
        uint64 offerRate,
        uint64 makerTokenAmountFilled,
        uint64 takerTokenAmountFilled,
        uint64 proratedBorrowFee,
        address feeRecipient,
        uint64 originalOrderAmount,
        uint64 expiry,
        uint64 salt
    ) external;

    function emitIntentCancelled(bytes32 orderHash) external;

    function emitRepoTokenSwapFilled(
        bytes32 orderHash,
        RepoTokenSwapData calldata swapData
    ) external;

    function emitLimitOrderTokenPairMinSaltValue(
        address maker,
        address makerToken,
        address takerToken,
        uint64 minSaltValue
    ) external;

    function emitSwapOrderTokenPairMinSaltValue(
        address maker,
        address makerToken,
        address takerToken,
        uint64 minSaltValue
    ) external;
}

interface ITermEventEmitterEvents {
    function emitDelistTermRepo(bytes32 termRepoId) external;

    function emitDelistTermAuction(bytes32 termAuctionId) external;

    function emitTermContractUpgraded(
        address proxy,
        address implementation
    ) external;
}

interface ITermEventEmitter is
    ITermAuctionEvents,
    ITermAuctionBidLockerEvents,
    ITermAuctionOfferLockerEvents,
    ITermRepoCollateralManagerEvents,
    ITermRepoServicerEvents,
    ITermRepoRolloverManagerEvents,
    ITermRepoLockerEvents,
    ITermRepoTokenEvents,
    ITermIntentEvents,
    ITermEventEmitterEvents
{
    function pairTermContract(address termContract) external;
}