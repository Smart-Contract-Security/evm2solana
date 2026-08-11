// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20
} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    IBondContract
} from "../interfaces/IBondContract.sol";

import {
    BondStatus,
    SubscriptionStatus,
    PaymentStatus
} from "../libraries/BondEnums.sol";

import {
    Subscription,
    FixedPayment
} from "../libraries/BondStructs.sol";

import "../libraries/BondErrors.sol";

import {
    BondEvents
} from "../libraries/BondEvents.sol";

import {
    EscrowVault
} from "./EscrowVault.sol";

/// @title BondContract
/// @notice MVP private RWA bond issuance with PUSH payouts.
///
///         UNITS / SEMANTICS:
///         - 1 bond is an integer (no decimals).
///         - `priceInUSDT`  = USDT smallest units paid by an
///           investor per 1 bond at issuance.
///         - `faceValue`   = USDT smallest units paid back to
///           the investor per 1 bond at maturity.
///         - `balances[x]` = number of bonds held by x.
///         - `totalSupply` = number of bonds outstanding.
///         - `subscription.bondAmount` = bonds requested.
///         - `subscription.usdtLocked` = bondAmount * priceInUSDT
///           locked in escrow.
///
///         PUSH MODEL:
///         Investors never call this contract after the
///         subscription stage. The operator (owner) is
///         responsible for pushing coupons and redemption.
///
///         KNOWN LIMITATIONS:
///         - executeCouponPayment / executeRedemption loop
///           over every bond holder. If any safeTransfer
///           reverts (e.g. blacklisted USDT recipient) the
///           whole push transaction reverts. Operator must
///           ensure recipients are transferable before push.
///         - Gas budget grows linearly with holder count.
///         - Rounding dust from coupon distribution stays in
///           the vault as unowned funds.
contract BondContract is
    IBondContract,
    BondEvents,
    ReentrancyGuard
{
    // =====================================================
    // ROLES / IMMUTABLES
    // =====================================================

    address public immutable owner;
    address public immutable issuer;

    IERC20 public immutable usdt;

    EscrowVault public immutable escrowVault;

    /// Operator-assigned business identifier for the issue
    /// (ФТ п.4.2). Unique across the whole factory.
    uint256 public immutable classId;

    uint256 public immutable issueStartDate;
    uint256 public immutable issueEndDate;
    uint256 public immutable maturityDate;

    /// Max number of bonds the issuance can produce.
    uint256 public immutable issueVolume;

    /// Minimum number of bonds required to consider the
    /// issuance successful.
    uint256 public immutable minTokensForIssue;

    /// USDT smallest units per 1 bond at issuance.
    uint256 public immutable priceInUSDT;

    /// USDT smallest units per 1 bond paid at maturity.
    uint256 public immutable faceValue;

    /// Off-chain document reference (e.g. IPFS CID / URL hash).
    /// Informational only; set at deployment, never updated.
    string public docHash;

    // =====================================================
    // STATE
    // =====================================================

    BondStatus public status;

    /// Total bonds across all live (non-rejected,
    /// non-cancelled, non-refunded) subscriptions.
    /// Used only for analytics / external dashboards.
    uint256 public totalSubscribed;

    /// Total bonds across subscriptions that the operator
    /// explicitly approved AND that the investor has not
    /// later cancelled. This is the figure compared against
    /// `minTokensForIssue` in `finalizeIssue`.
    uint256 public totalApproved;

    /// Total bonds allocated during finalizeIssue.
    /// Equal to totalSupply after finalize.
    uint256 public issuedAmount;

    /// Outstanding bonds. Goes to 0 after executeRedemption.
    uint256 public totalSupply;

    uint256 public subscriptionCount;
    uint256 public paymentCount;

    bool public finalized;
    bool public redemptionReserveFunded;

    mapping(address => uint256) public balances;

    mapping(uint256 => Subscription) public subscriptions;

    mapping(uint256 => FixedPayment) public payments;

    /// Index of a scheduled / funded / completed payment by
    /// its paymentDate. Used to reject duplicate coupons on
    /// the same date. 0 means no payment exists.
    mapping(uint256 => uint256) public paymentIdByDate;

    /// Set of unique bond holders for push iteration.
    address[] public bondHolders;
    mapping(address => bool) public isBondHolder;

    // =====================================================
    // MODIFIERS
    // =====================================================

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    modifier onlyIssuer() {
        if (msg.sender != issuer) {
            revert OnlyIssuer();
        }
        _;
    }

    modifier inStatus(BondStatus expected) {
        if (status != expected) {
            revert InvalidStatus();
        }
        _;
    }

    /// Kill-switch guard: once DEACTIVATED, no state-changing
    /// operation may proceed (prevents funds getting stuck in
    /// half-funded coupon/redemption buckets).
    modifier notDeactivated() {
        if (status == BondStatus.DEACTIVATED) {
            revert InvalidStatus();
        }
        _;
    }

    // =====================================================
    // CONSTRUCTOR
    // =====================================================

    constructor(
        address _owner,
        address _issuer,
        address _usdt,
        uint256 _classId,
        uint256 _issueStartDate,
        uint256 _issueEndDate,
        uint256 _maturityDate,
        uint256 _issueVolume,
        uint256 _minTokensForIssue,
        uint256 _priceInUSDT,
        uint256 _faceValue,
        string memory _docHash
    ) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_issuer == address(0)) revert ZeroAddress();
        if (_usdt == address(0)) revert ZeroAddress();
        if (_classId == 0) revert InvalidClassId();

        if (_issueStartDate >= _issueEndDate) {
            revert InvalidDate();
        }

        if (_issueEndDate >= _maturityDate) {
            revert InvalidDate();
        }

        if (_issueVolume == 0) revert ZeroAmount();

        if (_minTokensForIssue == 0) revert ZeroAmount();
        if (_minTokensForIssue > _issueVolume) {
            revert ZeroAmount();
        }

        if (_priceInUSDT == 0) revert InvalidPrice();
        if (_faceValue == 0) revert InvalidPrice();

        owner = _owner;
        issuer = _issuer;
        classId = _classId;

        usdt = IERC20(_usdt);

        issueStartDate = _issueStartDate;
        issueEndDate = _issueEndDate;
        maturityDate = _maturityDate;

        issueVolume = _issueVolume;
        minTokensForIssue = _minTokensForIssue;
        priceInUSDT = _priceInUSDT;
        faceValue = _faceValue;
        docHash = _docHash;

        status = BondStatus.DRAFT;

        escrowVault = new EscrowVault(
            _usdt,
            address(this)
        );
    }

    // =====================================================
    // LIFECYCLE
    // =====================================================

    /// @notice Issuer confirms the issue and simultaneously
    ///         deposits collateral equal to
    ///         `minTokensForIssue * faceValue` (ФТ).
    /// @dev    The issuer MUST approve EscrowVault for that
    ///         exact amount before calling this function.
    ///         The collateral guarantees that the minimum
    ///         possible redemption payout is already on-chain
    ///         before any investor is exposed.
    function confirmIssue()
        external
        onlyIssuer
        nonReentrant
        inStatus(BondStatus.DRAFT)
    {
        uint256 collateral = minTokensForIssue * faceValue;

        // EFFECTS
        status = BondStatus.READY_FOR_SUBSCRIPTION;

        // INTERACTION (pull USDT from issuer into escrow)
        escrowVault.lockIssuerCollateral(
            msg.sender,
            collateral
        );

        emit BondConfirmed(msg.sender);
    }

    function rejectIssue()
        external
        onlyIssuer
        inStatus(BondStatus.DRAFT)
    {
        status = BondStatus.ISSUER_REJECTED;
        emit BondRejected(msg.sender);
    }

    function openSubscriptionWindow()
        external
        onlyOwner
        inStatus(BondStatus.READY_FOR_SUBSCRIPTION)
    {
        if (block.timestamp < issueStartDate) {
            revert InvalidDate();
        }

        // ФТ: opening the window after the deadline is
        // meaningless and must be refused. Without this guard
        // the operator could open a subscription that
        // submitSubscription would immediately reject.
        if (block.timestamp > issueEndDate) {
            revert InvalidDate();
        }

        status = BondStatus.SUBSCRIPTION_OPEN;
        emit SubscriptionWindowOpened(block.timestamp);
    }

    function closeSubscriptionWindow()
        external
        onlyOwner
        inStatus(BondStatus.SUBSCRIPTION_OPEN)
    {
        if (block.timestamp <= issueEndDate) {
            revert SubscriptionNotClosed();
        }

        status = BondStatus.SUBSCRIPTION_CLOSED;
        emit SubscriptionWindowClosed(block.timestamp);
    }

    function deactivate() external onlyOwner {
        if (status == BondStatus.DEACTIVATED) {
            revert AlreadyDeactivated();
        }

        status = BondStatus.DEACTIVATED;
        emit BondDeactivated();
    }

    // =====================================================
    // SUBSCRIPTIONS
    // =====================================================

    /// @notice Investor commits `bondAmount` bonds and locks
    ///         `bondAmount * priceInUSDT` USDT in escrow.
    /// @dev    Investor MUST approve EscrowVault to spend
    ///         that exact USDT amount before calling.
    ///         There is no on-chain whitelist: the operator
    ///         filters investors at the review stage via
    ///         `reviewSubscription` (approve or reject).
    function submitSubscription(
        uint256 bondAmount
    )
        external
        nonReentrant
        inStatus(BondStatus.SUBSCRIPTION_OPEN)
    {
        // ФТ п.5.2: window is bounded by time even if the
        // operator has not yet called closeSubscriptionWindow.
        if (block.timestamp > issueEndDate) {
            revert SubscriptionClosed();
        }

        if (bondAmount == 0) revert ZeroAmount();

        uint256 usdtLocked = bondAmount * priceInUSDT;

        uint256 subscriptionId = ++subscriptionCount;

        // EFFECTS

        subscriptions[subscriptionId] = Subscription({
            id: subscriptionId,
            investor: msg.sender,
            bondAmount: bondAmount,
            usdtLocked: usdtLocked,
            allocatedBonds: 0,
            createdAt: block.timestamp,
            status: SubscriptionStatus.PENDING
        });

        totalSubscribed += bondAmount;

        // INTERACTION

        escrowVault.lockSubscriptionFunds(
            msg.sender,
            usdtLocked
        );

        emit SubscriptionSubmitted(
            subscriptionId,
            msg.sender,
            bondAmount,
            usdtLocked
        );
    }

    function reviewSubscription(
        uint256 subscriptionId,
        bool approve
    ) external onlyOwner nonReentrant {
        if (status != BondStatus.SUBSCRIPTION_OPEN) {
            revert SubscriptionClosed();
        }

        Subscription storage s = subscriptions[
            subscriptionId
        ];

        if (s.id == 0) revert InvalidSubscription();
        if (s.status != SubscriptionStatus.PENDING) {
            revert AlreadyReviewed();
        }

        if (approve) {
            s.status = SubscriptionStatus.OWNER_APPROVED;
            totalApproved += s.bondAmount;
            emit SubscriptionApproved(subscriptionId);
            return;
        }

        // Reject path: refund and remove demand. The
        // subscription was still PENDING so it had not yet
        // contributed to totalApproved.

        s.status = SubscriptionStatus.OWNER_REJECTED;

        totalSubscribed -= s.bondAmount;

        uint256 refundAmount = s.usdtLocked;

        escrowVault.refundInvestor(
            s.investor,
            refundAmount
        );

        emit SubscriptionRejected(subscriptionId);
        emit InvestorRefunded(s.investor, refundAmount);
    }

    // =====================================================
    // FINALIZATION
    // =====================================================

    /// @notice Allocates bonds FIFO by subscription id.
    ///         - PENDING and OWNER_APPROVED are processed.
    ///         - PENDING are treated as not approved and
    ///           auto-refunded (so investor cash never gets
    ///           stuck due to operator inactivity).
    ///         - Over-allocated subscriptions get partial
    ///           allocation + USDT remainder refund.
    ///         - Subscriptions after the volume is exhausted
    ///           get a full refund.
    function finalizeIssue()
        external
        onlyOwner
        nonReentrant
    {
        // Order matters: a second call must surface
        // AlreadyFinalized, not InvalidStatus.
        if (finalized) revert AlreadyFinalized();
        if (status != BondStatus.SUBSCRIPTION_CLOSED) {
            revert InvalidStatus();
        }
        finalized = true;

        // The issuance threshold is checked against the
        // operator-APPROVED demand only. PENDING and
        // OWNER_REJECTED subscriptions never contribute to it.
        if (totalApproved < minTokensForIssue) {
            status = BondStatus.NOT_ISSUED;
            _refundAllNonFinalSubscriptions();
            _returnIssuerCollateral();
            emit IssueFinalized(false, 0, 0);
            return;
        }

        uint256 remainingVolume = issueVolume;
        uint256 issuerProceedsUsdt;

        for (uint256 i = 1; i <= subscriptionCount; i++) {
            Subscription storage s = subscriptions[i];

            // PENDING -> auto refund (operator skipped review)
            if (s.status == SubscriptionStatus.PENDING) {
                s.status = SubscriptionStatus.REFUNDED;
                totalSubscribed -= s.bondAmount;

                escrowVault.refundInvestor(
                    s.investor,
                    s.usdtLocked
                );
                emit InvestorRefunded(
                    s.investor,
                    s.usdtLocked
                );
                continue;
            }

            if (
                s.status !=
                SubscriptionStatus.OWNER_APPROVED
            ) {
                // Skip OWNER_REJECTED / REFUNDED / others
                continue;
            }

            // Volume already exhausted -> full refund
            if (remainingVolume == 0) {
                s.status = SubscriptionStatus.REFUNDED;
                totalSubscribed -= s.bondAmount;
                totalApproved -= s.bondAmount;

                escrowVault.refundInvestor(
                    s.investor,
                    s.usdtLocked
                );
                emit InvestorRefunded(
                    s.investor,
                    s.usdtLocked
                );
                continue;
            }

            uint256 allocationBonds;
            bool isPartial;

            if (s.bondAmount <= remainingVolume) {
                allocationBonds = s.bondAmount;
                s.status =
                    SubscriptionStatus.ALLOCATED_FULL;
            } else {
                allocationBonds = remainingVolume;
                isPartial = true;
                s.status =
                    SubscriptionStatus.ALLOCATED_PARTIAL;
            }

            s.allocatedBonds = allocationBonds;

            uint256 allocationUsdt =
                allocationBonds * priceInUSDT;

            _registerHolder(s.investor);

            balances[s.investor] += allocationBonds;
            issuedAmount += allocationBonds;
            totalSupply += allocationBonds;

            issuerProceedsUsdt += allocationUsdt;
            remainingVolume -= allocationBonds;

            emit SubscriptionAllocated(
                s.id,
                s.investor,
                allocationBonds,
                allocationUsdt,
                isPartial
            );

            if (isPartial) {
                uint256 unallocatedBonds =
                    s.bondAmount - allocationBonds;
                uint256 refundUsdt =
                    s.usdtLocked - allocationUsdt;

                totalSubscribed -= unallocatedBonds;
                totalApproved -= unallocatedBonds;

                escrowVault.refundInvestor(
                    s.investor,
                    refundUsdt
                );
                emit InvestorRefunded(
                    s.investor,
                    refundUsdt
                );
            }
        }

        if (issuerProceedsUsdt > 0) {
            escrowVault.releaseToIssuer(
                issuer,
                issuerProceedsUsdt
            );
        }

        // Defense-in-depth: a successful issuance must
        // produce at least the configured minimum supply.
        // Given the gate `totalApproved >= minTokensForIssue`
        // and the constructor invariant
        // `minTokensForIssue <= issueVolume`, FIFO allocation
        // is guaranteed to reach this number.
        if (issuedAmount < minTokensForIssue) {
            revert AccountingMismatch();
        }

        status = BondStatus.ISSUED;

        emit IssueFinalized(
            true,
            issuedAmount,
            totalSupply
        );
    }

    function _refundAllNonFinalSubscriptions() internal {
        for (uint256 i = 1; i <= subscriptionCount; i++) {
            Subscription storage s = subscriptions[i];

            bool wasApproved =
                s.status ==
                SubscriptionStatus.OWNER_APPROVED;

            bool refundable =
                s.status == SubscriptionStatus.PENDING ||
                wasApproved;

            if (!refundable) continue;

            s.status = SubscriptionStatus.REFUNDED;
            totalSubscribed -= s.bondAmount;
            if (wasApproved) {
                totalApproved -= s.bondAmount;
            }

            escrowVault.refundInvestor(
                s.investor,
                s.usdtLocked
            );
            emit InvestorRefunded(
                s.investor,
                s.usdtLocked
            );
        }
    }

    /// @dev Pulls the full collateral back to the issuer.
    ///      Called on the NOT_ISSUED branch of finalizeIssue.
    function _returnIssuerCollateral() internal {
        uint256 outstanding = escrowVault.issuerCollateral();
        if (outstanding == 0) return;
        escrowVault.releaseIssuerCollateral(
            issuer,
            outstanding
        );
    }

    function _registerHolder(address investor) internal {
        if (isBondHolder[investor]) return;
        isBondHolder[investor] = true;
        bondHolders.push(investor);
        emit BondHolderRegistered(investor);
    }

    // =====================================================
    // COUPON PAYMENTS (PUSH MODEL)
    // =====================================================

    function createFixedPayment(
        uint256 paymentDate,
        uint256 totalAmount
    ) external onlyOwner inStatus(BondStatus.ISSUED) {
        if (paymentDate <= block.timestamp) {
            revert InvalidDate();
        }
        if (paymentDate > maturityDate) {
            revert InvalidDate();
        }
        if (paymentDate <= issueEndDate) {
            revert SubscriptionNotClosed();
        }
        if (totalAmount == 0) revert ZeroAmount();

        // Guard against double-clicks: only one coupon per
        // calendar second / unix timestamp.
        if (paymentIdByDate[paymentDate] != 0) {
            revert DuplicatePayment();
        }

        paymentCount++;

        payments[paymentCount] = FixedPayment({
            id: paymentCount,
            paymentDate: paymentDate,
            actualPaymentDate: 0,
            totalAmount: totalAmount,
            remainingAmount: totalAmount,
            status: PaymentStatus.SCHEDULED,
            reserveFunded: false
        });

        paymentIdByDate[paymentDate] = paymentCount;

        emit CouponCreated(
            paymentCount,
            paymentDate,
            totalAmount
        );
    }

    /// @notice Issuer funds the coupon reserve up-front.
    /// @dev    Issuer MUST approve EscrowVault for the full
    ///         `totalAmount` of this payment beforehand.
    function fundCouponReserve(
        uint256 paymentId
    ) external onlyIssuer nonReentrant notDeactivated {
        FixedPayment storage p = payments[paymentId];

        if (p.id == 0) revert InvalidPayment();
        if (p.reserveFunded) revert AlreadyFunded();

        p.reserveFunded = true;
        p.status = PaymentStatus.FUNDED;

        escrowVault.fundCouponReserve(
            issuer,
            p.totalAmount
        );

        emit CouponReserveFunded(paymentId, p.totalAmount);
    }

    /// @notice PUSH all coupons for `paymentId` to every
    ///         current bond holder.
    /// @dev    Owner only. Atomic: if any push fails the
    ///         whole transaction reverts and the operator
    ///         must address the issue and retry.
    function executeCouponPayment(
        uint256 paymentId
    )
        external
        onlyOwner
        nonReentrant
        inStatus(BondStatus.ISSUED)
    {
        FixedPayment storage p = payments[paymentId];

        if (p.id == 0) revert InvalidPayment();
        if (!p.reserveFunded) revert NotFunded();
        if (block.timestamp < p.paymentDate) {
            revert InvalidDate();
        }
        if (p.status == PaymentStatus.COMPLETED) {
            revert AlreadyPaid();
        }

        uint256 supply = totalSupply;
        if (supply == 0) revert NoHolders();

        uint256 holdersLength = bondHolders.length;
        uint256 totalPaid;

        for (uint256 i = 0; i < holdersLength; i++) {
            address holder = bondHolders[i];
            uint256 holderBonds = balances[holder];
            if (holderBonds == 0) continue;

            uint256 share =
                (holderBonds * p.totalAmount) / supply;
            if (share == 0) continue;

            escrowVault.payCouponClaim(holder, share);

            totalPaid += share;

            emit CouponPaid(paymentId, holder, share);
        }

        // Dust = rounding remainder, stays in vault.
        uint256 dust = p.totalAmount - totalPaid;
        p.remainingAmount = dust;
        p.status = PaymentStatus.COMPLETED;
        p.actualPaymentDate = block.timestamp;

        emit CouponPaymentExecuted(
            paymentId,
            totalPaid,
            dust
        );
    }

    // =====================================================
    // REDEMPTION (PUSH MODEL)
    // =====================================================

    /// @notice Issuer funds the redemption reserve. The
    ///         collateral deposited at confirmIssue is moved
    ///         into the redemption bucket in-place; the
    ///         issuer only needs to top up the difference.
    /// @dev    Issuer MUST approve EscrowVault for at least
    ///         `totalSupply * faceValue - collateralLocked`
    ///         USDT beforehand.
    function fundRedemptionReserve()
        external
        onlyIssuer
        nonReentrant
        notDeactivated
        inStatus(BondStatus.ISSUED)
    {
        if (redemptionReserveFunded) {
            revert AlreadyFunded();
        }

        uint256 needed = totalSupply * faceValue;
        if (needed == 0) revert NoHolders();

        redemptionReserveFunded = true;

        uint256 fromCollateral = escrowVault.issuerCollateral();
        if (fromCollateral > needed) {
            // Should never happen (collateral was sized for
            // minTokensForIssue and totalSupply >= that), but
            // clip just in case so we don't double-spend.
            fromCollateral = needed;
        }

        if (fromCollateral > 0) {
            escrowVault.convertCollateralToRedemption(
                fromCollateral
            );
        }

        uint256 topUp = needed - fromCollateral;
        if (topUp > 0) {
            escrowVault.fundRedemptionReserve(issuer, topUp);
        }

        emit RedemptionReserveFunded(needed);
    }

    /// @notice PUSH redemption to every current bond holder.
    /// @dev    Owner only. After successful execution the
    ///         bond status moves to REDEEMED and all
    ///         `balances` are zeroed.
    function executeRedemption()
        external
        onlyOwner
        nonReentrant
        inStatus(BondStatus.ISSUED)
    {
        if (block.timestamp < maturityDate) {
            revert NotMatured();
        }
        if (!redemptionReserveFunded) {
            revert NotFunded();
        }

        // ФТ п.5.5: redemption is blocked while any coupon
        // obligation is still SCHEDULED or only FUNDED.
        // Holders must receive every scheduled coupon before
        // the principal is paid back.
        uint256 pCount = paymentCount;
        for (uint256 i = 1; i <= pCount; i++) {
            if (payments[i].status != PaymentStatus.COMPLETED) {
                revert CouponsUnpaid();
            }
        }

        uint256 holdersLength = bondHolders.length;
        uint256 totalPaid;

        for (uint256 i = 0; i < holdersLength; i++) {
            address holder = bondHolders[i];
            uint256 holderBonds = balances[holder];
            if (holderBonds == 0) continue;

            uint256 amount = holderBonds * faceValue;

            balances[holder] = 0;

            escrowVault.payRedemption(holder, amount);

            totalPaid += amount;

            emit RedemptionPaid(holder, amount);
        }

        uint256 expected = totalSupply * faceValue;
        uint256 dust = expected - totalPaid;

        totalSupply = 0;
        status = BondStatus.REDEEMED;

        emit RedemptionExecuted(totalPaid, dust);
    }

    // =====================================================
    // VIEWS
    // =====================================================

    function balanceOf(address user)
        external
        view
        returns (uint256)
    {
        return balances[user];
    }

    function bondHoldersCount()
        external
        view
        returns (uint256)
    {
        return bondHolders.length;
    }

    // =====================================================
    // ERC-20-LIKE STUBS  (ФТ п.5.3: non-transferable)
    // =====================================================
    //
    // The contract intentionally mimics the ERC-20 selectors
    // for `transfer`, `transferFrom`, `approve` and
    // `allowance` so that ERC-20-aware wallets and indexers
    // get an explicit, on-chain refusal instead of a silent
    // "function does not exist" error. Bond balances are
    // strictly non-transferable.

    function transfer(address, uint256)
        external
        pure
        returns (bool)
    {
        revert TransfersDisabled();
    }

    function transferFrom(address, address, uint256)
        external
        pure
        returns (bool)
    {
        revert TransfersDisabled();
    }

    function approve(address, uint256)
        external
        pure
        returns (bool)
    {
        revert TransfersDisabled();
    }

    function allowance(address, address)
        external
        pure
        returns (uint256)
    {
        return 0;
    }
}
