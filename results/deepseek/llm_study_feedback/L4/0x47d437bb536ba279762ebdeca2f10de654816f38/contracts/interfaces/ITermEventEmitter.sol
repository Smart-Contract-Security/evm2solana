//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

// Solang does not support importing external Solidity files in the same way.
// We define the required interfaces and structs inline.

interface ITermAuctionEvents {
    // Events from ITermAuctionEvents would be declared here.
    // Since they are not directly used in this file beyond inheritance,
    // we provide an empty interface to satisfy the compiler.
}

interface ITermAuctionBidLockerEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermAuctionOfferLockerEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermRepoCollateralManagerEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermRepoServicerEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermRepoRolloverManagerEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermRepoLockerEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermRepoTokenEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermIntentEvents {
    // Empty interface to satisfy inheritance.
}

interface ITermEventEmitterEvents {
    // Empty interface to satisfy inheritance.
}

// Define the missing structs.
struct TermAuctionBid {
    bytes32 id;
    address bidder;
    uint256 amount;
    bytes32 hashedPrice;
    // Add other fields as needed by the actual implementation.
}

struct RepoTokenSwapData {
    bytes32 orderHash;
    bytes32 termRepoId;
    address maker;
    address taker;
    // Add other fields as needed.
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

    function emitTermAuctionInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuction,
        uint256 auctionEndTime,
        address deployerWallet,
        string calldata version
    ) external;

    function emitBidAssigned(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 amount
    ) external;

    function emitOfferAssigned(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 amount
    ) external;

    function emitAuctionCompleted(
        bytes32 termAuctionId,
        uint256 timestamp,
        uint256 blockNumber,
        uint256 totalAssignedBids,
        uint256 totalAssignedOffers,
        uint256 clearingPrice
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

    function emitTermAuctionBidLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionBidLocker,
        uint256 auctionStartTime,
        uint256 revealTime,
        uint256 maxBidPrice,
        uint256 minimumTenderAmount,
        uint256 dayCountFractionMantissa
    ) external;

    function emitBidLocked(
        bytes32 termAuctionId,
        TermAuctionBid calldata bid,
        address referralAddress
    ) external;

    function emitBidRevealed(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 bidPrice
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

    function emitTermAuctionOfferLockerInitialized(
        bytes32 termRepoId,
        bytes32 termAuctionId,
        address termAuctionOfferLocker,
        uint256 auctionStartTime,
        uint256 revealTime,
        uint256 maxOfferPrice,
        uint256 minimumTenderAmount
    ) external;

    function emitOfferLocked(
        bytes32 termAuctionId,
        bytes32 id,
        address offeror,
        bytes32 offerPrice,
        uint256 amount,
        address purchaseToken,
        address referralAddress
    ) external;

    function emitOfferRevealed(
        bytes32 termAuctionId,
        bytes32 id,
        uint256 offerPrice
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

    function emitTermRepoCollateralManagerInitialized(
        bytes32 termRepoId,
        address termRepoCollateralManager,
        address[] calldata collateralTokens,
        uint256[] calldata initialCollateralRatios,
        uint256[] calldata maintenanceCollateralRatios,
        uint256[] calldata liquidatedDamagesSchedule
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
        uint256 amount
    ) external;

    function emitCollateralUnlocked(
        bytes32 termRepoId,
        address borrower,
        address collateralToken,
        uint256 amount
    ) external;

    function emitLiquidation(
        bytes32 termRepoId,
        address borrower,
        address liquidator,
        uint256 closureAmount,
        address collateralToken,
        uint256 amountLiquidated,
        uint256 protocolSeizureAmount,
        bool defaultLiquidation
    ) external;

    function emitLiquidationPaused(bytes32 termRepoId) external;

    function emitLiquidationUnpaused(bytes32 termRepoId) external;

    function emitTermRepoServicerInitialized(
        bytes32 termRepoId,
        address termRepoServicer,
        address purchaseToken,
        uint256 maturityTimestamp,
        uint256 endOfRepurchaseWindow,
        uint256 redemptionTimestamp,
        uint256 servicingFee,
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
        uint256 amount
    ) external;

    function emitOfferUnlockedByServicer(
        bytes32 termRepoId,
        address offeror,
        uint256 amount
    ) external;

    function emitOfferFulfilled(
        bytes32 offerId,
        address offeror,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 repoTokensMinted
    ) external;

    function emitTermRepoTokensRedeemed(
        bytes32 termRepoId,
        address redeemer,
        uint256 redemptionAmount,
        uint256 redemptionHaircut
    ) external;

    function emitBidFulfilled(
        bytes32 termRepoId,
        address bidder,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 servicingFees
    ) external;

    function emitExposureOpenedOnRolloverNew(
        bytes32 termRepoId,
        address borrower,
        uint256 purchasePrice,
        uint256 repurchasePrice,
        uint256 servicingFees
    ) external;

    function emitExposureClosedOnRolloverExisting(
        bytes32 termRepoId,
        address borrower,
        uint256 amountRolled
    ) external;

    function emitRepurchasePaymentSubmitted(
        bytes32 termRepoId,
        address borrower,
        uint256 amount
    ) external;

    function emitMintExposureAccessGranted(
        bytes32 termRepoId,
        address authedUser
    ) external;

    function emitMintExposure(
        bytes32 termRepoId,
        address minter,
        uint256 netTokensReceived,
        uint256 servicingFeeTokens,
        uint256 repurchasePrice
    ) external;

    function emitBurnCollapseExposure(
        bytes32 termRepoId,
        address borrower,
        uint256 closeAmount
    ) external;

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
        uint256 rolloverAmount,
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

    function emitTermRepoLockerInitialized(
        bytes32 termRepoId,
        address termRepoLocker
    ) external;

    function emitTermRepoLockerTransfersPaused(bytes32 termRepoId) external;

    function emitTermRepoLockerTransfersUnpaused(bytes32 termRepoId) external;

    function emitTermRepoTokenInitialized(
        bytes32 termRepoId,
        address termRepoToken,
        uint256 redemptionRatio
    ) external;

    function emitTermRepoTokenMintingPaused(bytes32 termRepoId) external;

    function emitTermRepoTokenMintingUnpaused(bytes32 termRepoId) external;

    function emitTermRepoTokenBurningPaused(bytes32 termRepoId) external;

    function emitTermRepoTokenBurningUnpaused(bytes32 termRepoId) external;

    function emitIntentFilled(
        bytes32 orderHash,
        bytes32 termRepoId,
        address purchaseToken,
        address maker,
        address taker,
        address makerToken,
        address takerToken,
        uint256 offerRate,
        uint256 makerTokenAmountFilled,
        uint256 takerTokenAmountFilled,
        uint256 proratedBorrowFee,
        address feeRecipient,
        uint256 originalOrderAmount,
        uint256 expiry,
        uint256 salt
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
        uint256 minSaltValue
    ) external;

    function emitSwapOrderTokenPairMinSaltValue(
        address maker,
        address makerToken,
        address takerToken,
        uint256 minSaltValue
    ) external;

    function emitDelistTermRepo(bytes32 termRepoId) external;

    function emitDelistTermAuction(bytes32 termAuctionId) external;

    function emitTermContractUpgraded(
        address proxy,
        address implementation
    ) external;
}