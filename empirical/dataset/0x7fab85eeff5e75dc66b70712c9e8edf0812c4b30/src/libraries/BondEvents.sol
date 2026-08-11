// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract BondEvents {
    event BondConfirmed(address indexed issuer);

    event BondRejected(address indexed issuer);

    event BondDeactivated();

    event SubscriptionWindowOpened(uint256 timestamp);

    event SubscriptionWindowClosed(uint256 timestamp);

    event SubscriptionSubmitted(
        uint256 indexed subscriptionId,
        address indexed investor,
        uint256 bondAmount,
        uint256 usdtLocked
    );

    event SubscriptionApproved(uint256 indexed subscriptionId);

    event SubscriptionRejected(uint256 indexed subscriptionId);

    event SubscriptionAllocated(
        uint256 indexed subscriptionId,
        address indexed investor,
        uint256 allocatedBonds,
        uint256 issuerProceedsUsdt,
        bool isPartial
    );

    event InvestorRefunded(
        address indexed investor,
        uint256 amountUsdt
    );

    event IssueFinalized(
        bool success,
        uint256 issuedAmount,
        uint256 totalSupplyBonds
    );

    event BondHolderRegistered(
        address indexed investor
    );

    event CouponCreated(
        uint256 indexed paymentId,
        uint256 paymentDate,
        uint256 totalAmountUsdt
    );

    event CouponReserveFunded(
        uint256 indexed paymentId,
        uint256 amountUsdt
    );

    event CouponPaid(
        uint256 indexed paymentId,
        address indexed investor,
        uint256 amountUsdt
    );

    event CouponPaymentExecuted(
        uint256 indexed paymentId,
        uint256 totalPaidUsdt,
        uint256 dustUsdt
    );

    event RedemptionReserveFunded(uint256 amountUsdt);

    event RedemptionPaid(
        address indexed investor,
        uint256 amountUsdt
    );

    event RedemptionExecuted(
        uint256 totalPaidUsdt,
        uint256 dustUsdt
    );

    event BondCreated(
        address indexed bond,
        address indexed issuer,
        uint256 indexed classId
    );
}
