// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    BondStatus
} from "../libraries/BondEnums.sol";

interface IBondContract {

    // =====================================================
    // LIFECYCLE
    // =====================================================

    function confirmIssue() external;

    function rejectIssue() external;

    function openSubscriptionWindow() external;

    function closeSubscriptionWindow() external;

    function deactivate() external;

    // =====================================================
    // SUBSCRIPTIONS
    // =====================================================

    function submitSubscription(
        uint256 bondAmount
    ) external;

    function reviewSubscription(
        uint256 subscriptionId,
        bool approve
    ) external;

    function finalizeIssue() external;

    // =====================================================
    // COUPON PAYMENTS (PUSH MODEL)
    // =====================================================

    function createFixedPayment(
        uint256 paymentDate,
        uint256 totalAmount
    ) external;

    function fundCouponReserve(
        uint256 paymentId
    ) external;

    function executeCouponPayment(
        uint256 paymentId
    ) external;

    // =====================================================
    // REDEMPTION (PUSH MODEL)
    // =====================================================

    function fundRedemptionReserve() external;

    function executeRedemption() external;

    // =====================================================
    // VIEWS
    // =====================================================

    function status()
        external
        view
        returns (BondStatus);

    function issuer()
        external
        view
        returns (address);

    function classId()
        external
        view
        returns (uint256);

    function priceInUSDT()
        external
        view
        returns (uint256);

    function faceValue()
        external
        view
        returns (uint256);

    function totalSupply()
        external
        view
        returns (uint256);

    function balanceOf(address investor)
        external
        view
        returns (uint256);

    function bondHoldersCount()
        external
        view
        returns (uint256);
}
