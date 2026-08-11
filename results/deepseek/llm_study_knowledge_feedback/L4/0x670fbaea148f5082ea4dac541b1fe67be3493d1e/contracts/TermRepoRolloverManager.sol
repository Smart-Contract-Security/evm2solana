//SPDX-License-Identifier: Unlicense

import {ITermAuctionBidLocker} from "./interfaces/ITermAuctionBidLocker.sol";
import {ITermAuctionOfferLocker} from "./interfaces/ITermAuctionOfferLocker.sol";
import {ITermEventEmitter} from "./interfaces/ITermEventEmitter.sol";
import {ITermRepoCollateralManager} from "./interfaces/ITermRepoCollateralManager.sol";
import {ITermRepoServicer} from "./interfaces/ITermRepoServicer.sol";
import {ITermController} from "./interfaces/ITermController.sol";
import {ExponentialNoError} from "./lib/ExponentialNoError.sol";
import {TermAuctionBid} from "./lib/TermAuctionBid.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct TermRepoRolloverElection {
    address rolloverAuctionBidLocker;
    uint64 rolloverAmount;
    bytes32 rolloverBidPriceHash;
    bool processed;
}

struct TermRepoRolloverElectionSubmission {
    address rolloverAuctionBidLocker;
    uint64 rolloverAmount;
    bytes32 rolloverBidPriceHash;
}

/// @author TermLabs
/// @title Term Repo Rollover Manager
/// @notice This contract accepts and carries out borrower Term Repo rollover instructions
/// @dev This contract belongs to the Term Servicer group of contracts and is specific to a Term Repo deployment
contract TermRepoRolloverManager is ExponentialNoError {
    // ========================================================================
    // = Access Role  =========================================================
    // ========================================================================

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEVOPS_ROLE = keccak256("DEVOPS_ROLE");
    bytes32 public constant INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");
    bytes32 public constant ROLLOVER_BID_FULFILLER_ROLE =
        keccak256("ROLLOVER_BID_FULFILLER_ROLE");
    bytes32 public constant DIAMOND_ROLE = keccak256("DIAMOND_ROLE");

    // ========================================================================
    // = State Variables ======================================================
    // ========================================================================
    bytes32 public termRepoId;
    address internal termRepoCollateralManager;
    address internal termRepoServicer;
    address public termController;
    address internal emitter;

    // Mapping that returns true for approved Borrower Rollover Auction Bid Lockers
    mapping(address => bool) internal approvedRolloverAuctionBidLockers;

    // Borrow Rollover Ledger
    // For each borrower wallet address, keep ledger of borrow rollver election addresses.
    mapping(address => TermRepoRolloverElection) internal rolloverElections;

    bool internal termContractPaired;

    // Access control mapping
    mapping(address => mapping(bytes32 => bool)) private _roles;

    // ========================================================================
    // = Modifiers ============================================================
    // ========================================================================

    modifier notPastRepaymentWindow() {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp >= ITermRepoServicer(termRepoServicer).endOfRepurchaseWindow()) {
            revert("EndOfRepurchaseWindowReached");
        }
        _;
    }

    modifier notTermContractPaired() {
        if (termContractPaired) {
            revert("AlreadyTermContractPaired");
        }
        termContractPaired = true;
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(_roles[tx.accounts.dataAccount.key][role], "AccessControl: missing role");
        _;
    }

    // ========================================================================
    // = Deploy  ==============================================================
    // ========================================================================

    function initialize(
        string calldata termRepoId_,
        address termRepoServicer_,
        address termRepoCollateralManager_,
        address termController_,
        address termInitializer_
    ) external {
        require(!termContractPaired, "Already initialized");

        termRepoId = keccak256(abi.encodePacked(termRepoId_));
        termRepoCollateralManager = termRepoCollateralManager_;
        termRepoServicer = termRepoServicer_;
        termController = termController_;

        termContractPaired = false;

        _grantRole(INITIALIZER_ROLE, termInitializer_);
    }

    function pairTermContracts(
        address termRepoServicer_,
        address termDiamond_,
        address emitter_,
        address devopsMultisig_,
        address adminWallet_
    ) external onlyRole(INITIALIZER_ROLE) notTermContractPaired {
        emitter = emitter_;
        _grantRole(ROLLOVER_BID_FULFILLER_ROLE, termRepoServicer_);
        _grantRole(DEVOPS_ROLE, devopsMultisig_);
        _grantRole(ADMIN_ROLE, adminWallet_);
        _grantRole(DIAMOND_ROLE, termDiamond_);

        ITermEventEmitter(emitter).emitTermRepoRolloverManagerInitialized(
            termRepoId,
            address(this)
        );
    }

    // ========================================================================
    // = APIs  ================================================================
    // ========================================================================

    /// @notice An external function that accepted Term Repo rollover instructions
    /// @param termRepoRolloverElectionSubmission A struct containing borrower rollover instructions
    function electRollover(
        TermRepoRolloverElectionSubmission
            calldata termRepoRolloverElectionSubmission
    ) external notPastRepaymentWindow {
        _electRolloverInternal(tx.accounts.dataAccount.key, termRepoRolloverElectionSubmission);
    }

    /// @notice Allows DIAMOND_ROLE to elect rollover on behalf of a borrower
    /// @param borrower The address of the borrower for whom rollover is being elected
    /// @param termRepoRolloverElectionSubmission A struct containing borrower rollover instructions
    function electRolloverFor(
        address borrower,
        TermRepoRolloverElectionSubmission
            calldata termRepoRolloverElectionSubmission
    ) external notPastRepaymentWindow onlyRole(DIAMOND_ROLE)  {
        _electRolloverInternal(
            borrower,
            termRepoRolloverElectionSubmission
        );
    }

    /// @notice A view function that returns borrower rollover instructions
    /// @param borrower The address of the borrower
    /// @return A struct containing borrower rollover instructions
    function getRolloverInstructions(
        address borrower
    ) external view returns (TermRepoRolloverElection memory) {
        return rolloverElections[borrower];
    }

    /// @notice An external function to cancel previously submitted rollover instructions
    function cancelRollover() external {
        address borrower = tx.accounts.dataAccount.key;
        _cancelRolloverInternal(borrower);
    }

    /// @notice Allows DIAMOND_ROLE to cancel rollover on behalf of a borrower
    /// @param borrower The address of the borrower for whom rollover is being cancelled
    function cancelRolloverFor(address borrower) external onlyRole(DIAMOND_ROLE) {
        _cancelRolloverInternal(borrower);
    }


    // ========================================================================
    // = Fulfiller Functions ================================================
    // ========================================================================

    /// @notice An external function called by repo servicer to mark rollover as fulfilled
    /// @param borrower The address of the borrower
    function fulfillRollover(
        address borrower
    ) external onlyRole(ROLLOVER_BID_FULFILLER_ROLE) {
        rolloverElections[borrower].processed = true;
        ITermEventEmitter(emitter).emitRolloverProcessed(termRepoId, borrower);
    }

    // ========================================================================
    // = Admin Functions ======================================================
    // ========================================================================

    /// @param auctionBidLocker The address for ITermAuctionBidLocker interface
    function approveRolloverAuction(
        address auctionBidLocker
    ) external notPastRepaymentWindow onlyRole(ADMIN_ROLE) {
        if (!ITermController(termController).isTermDeployed(auctionBidLocker) && !ITermController(termController).isFactoryDeployed(auctionBidLocker)) {
            revert("NotTermContract");
        }

        if (
            ITermAuctionBidLocker(auctionBidLocker).auctionEndTime() >=
            ITermRepoServicer(termRepoServicer).endOfRepurchaseWindow()
        ) {
            revert("AuctionEndsAfterRepayment");
        }
        if (
            ITermAuctionBidLocker(auctionBidLocker).auctionEndTime() <
            ITermRepoServicer(termRepoServicer).maturityTimestamp()
        ) {
            revert("AuctionEndsBeforeMaturity");
        }
        if (
            ITermRepoServicer(termRepoServicer).purchaseToken() !=
            address(ITermAuctionBidLocker(auctionBidLocker).purchaseToken())
        ) {
            revert("DifferentPurchaseToken");
        }

        uint64 numOfAcceptedCollateralTokens = ITermRepoCollateralManager(termRepoCollateralManager)
            .numOfAcceptedCollateralTokens();

        for (uint64 i = 0; i < numOfAcceptedCollateralTokens; ++i) {
            address supportedIERC20Collateral = ITermRepoCollateralManager(termRepoCollateralManager).collateralTokens(i);
            if (!ITermAuctionBidLocker(auctionBidLocker).collateralTokens(supportedIERC20Collateral)) {
                revert("CollateralTokenNotSupported");
            }
        }

        approvedRolloverAuctionBidLockers[auctionBidLocker] = true;

        address termAuction = address(ITermAuctionBidLocker(auctionBidLocker).termAuction());

        ITermRepoServicer(termRepoServicer).approveRolloverAuction(termAuction);
        ITermRepoCollateralManager(termRepoCollateralManager).approveRolloverAuction(termAuction);

        _grantRole(ROLLOVER_BID_FULFILLER_ROLE, termAuction);

        ITermEventEmitter(emitter).emitRolloverTermApproved(
            termRepoId,
            ITermAuctionBidLocker(auctionBidLocker).termAuctionId()
        );
    }

    /// @param auctionBidLocker The address for ITermAuctionBidLocker interface
    function revokeRolloverApproval(
        address auctionBidLocker
    ) external onlyRole(ADMIN_ROLE) {
        approvedRolloverAuctionBidLockers[auctionBidLocker] = false;

        ITermEventEmitter(emitter).emitRolloverTermApprovalRevoked(
            termRepoId,
            ITermAuctionBidLocker(auctionBidLocker).termAuctionId()
        );
    }

    // ========================================================================
    // = Internal =============================================================
    // ========================================================================

    function _electRolloverInternal(
        address borrower,
        TermRepoRolloverElectionSubmission calldata termRepoRolloverElectionSubmission
    ) internal {
        uint64 borrowerRepurchaseObligation = ITermRepoServicer(termRepoServicer)
            .getBorrowerRepurchaseObligation(borrower);
        if (borrowerRepurchaseObligation == 0) {
            revert("ZeroBorrowerRepurchaseObligation");
        }
        if (
            !approvedRolloverAuctionBidLockers[
                termRepoRolloverElectionSubmission.rolloverAuctionBidLocker
            ]
        ) {
            revert("RolloverAddressNotApproved");
        }

        if (rolloverElections[borrower].processed) {
            revert("RolloverProcessedToTerm");
        }

        if (termRepoRolloverElectionSubmission.rolloverAmount == 0) {
            revert("InvalidParameters");
        }

        if (
            borrowerRepurchaseObligation <
            termRepoRolloverElectionSubmission.rolloverAmount
        ) {
            revert("BorrowerRepurchaseObligationInsufficient");
        }

        if (
            rolloverElections[borrower].rolloverAuctionBidLocker !=
            address(0) &&
            rolloverElections[borrower].rolloverAuctionBidLocker !=
            termRepoRolloverElectionSubmission.rolloverAuctionBidLocker
        ) {
            rolloverElections[borrower].rolloverAmount = 0;
            _processRollover(borrower);
        }

        rolloverElections[borrower] = TermRepoRolloverElection({
            rolloverAuctionBidLocker: termRepoRolloverElectionSubmission
                .rolloverAuctionBidLocker,
            rolloverAmount: termRepoRolloverElectionSubmission.rolloverAmount,
            rolloverBidPriceHash: termRepoRolloverElectionSubmission
                .rolloverBidPriceHash,
            processed: false
        });

        address auctionBidLocker = termRepoRolloverElectionSubmission.rolloverAuctionBidLocker;

        ITermEventEmitter(emitter).emitRolloverElection(
            termRepoId,
            ITermAuctionBidLocker(auctionBidLocker).termRepoId(),
            borrower,
            termRepoRolloverElectionSubmission.rolloverAuctionBidLocker,
            termRepoRolloverElectionSubmission.rolloverAmount,
            termRepoRolloverElectionSubmission.rolloverBidPriceHash
        );

        _processRollover(borrower);
    }

    function _cancelRolloverInternal(address borrower) internal {
        if (ITermRepoServicer(termRepoServicer).getBorrowerRepurchaseObligation(borrower) == 0) {
            revert("ZeroBorrowerRepurchaseObligation");
        }

        if (rolloverElections[borrower].rolloverAmount == 0) {
            revert("NoRolloverToCancel");
        }

        if (rolloverElections[borrower].processed) {
            revert("RolloverProcessedToTerm");
        }

        rolloverElections[borrower].rolloverAmount = 0;

        _processRollover(borrower);

        delete rolloverElections[borrower];

        ITermEventEmitter(emitter).emitRolloverCancellation(termRepoId, borrower);
    }

    function _processRollover(address borrowerToRollover) internal {
        TermRepoRolloverElection memory rolloverElection = rolloverElections[
            borrowerToRollover
        ];

        address termAuctionBidLocker = rolloverElection.rolloverAuctionBidLocker;

        address futureTermRepoServicer = ITermAuctionBidLocker(termAuctionBidLocker)
            .termRepoServicer();

        uint64 servicingFeeProRatedMantissa = mul_(
            Exp({mantissa: ITermAuctionBidLocker(termAuctionBidLocker).dayCountFractionMantissa()}),
            Exp({mantissa: ITermRepoServicer(futureTermRepoServicer).servicingFee()})
        ).mantissa;

        uint64 bidAmount;

        if (rolloverElection.rolloverAmount > 0) {
            bidAmount = truncate(
                div_(
                    Exp({mantissa: rolloverElection.rolloverAmount * expScale}),
                    Exp({mantissa: expScale - servicingFeeProRatedMantissa})
                )
            );
        } else {
            bidAmount = 0;
        }

        (address[] memory collateralTokens, ) = ITermRepoCollateralManager(termRepoCollateralManager)
            .getCollateralBalances(borrowerToRollover);

        uint64[] memory collateralAmounts = new uint64[](
            collateralTokens.length
        );

        TermAuctionBid memory termAuctionBid = TermAuctionBid({
            id: keccak256(abi.encodePacked(address(this), borrowerToRollover)),
            bidder: borrowerToRollover,
            bidPriceHash: rolloverElection.rolloverBidPriceHash,
            bidPriceRevealed: 0,
            amount: bidAmount,
            collateralTokens: collateralTokens,
            collateralAmounts: collateralAmounts,
            purchaseToken: ITermRepoServicer(termRepoServicer).purchaseToken(),
            isRollover: true,
            rolloverPairOffTermRepoServicer: termRepoServicer,
            isRevealed: false
        });

        ITermAuctionBidLocker(termAuctionBidLocker).lockRolloverBid(termAuctionBid);
    }

    ///@dev required override by the OpenZeppelin UUPS module
    ///@param impl new impl address for proxy upgrade
    function _authorizeUpgrade(
        address impl
    ) internal onlyRole(DEVOPS_ROLE) {
        ITermEventEmitter(emitter).emitTermContractUpgraded(address(this), impl);
    }

    // ========================================================================
    // = Access Control Internal ==============================================
    // ========================================================================

    function _grantRole(bytes32 role, address account) internal {
        _roles[account][role] = true;
    }
}