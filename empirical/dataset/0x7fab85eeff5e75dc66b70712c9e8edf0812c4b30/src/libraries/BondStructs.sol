// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    SubscriptionStatus,
    PaymentStatus
} from "./BondEnums.sol";

struct Subscription {
    uint256 id;
    address investor;
    /// Number of bonds requested.
    uint256 bondAmount;
    /// USDT smallest units locked = bondAmount * priceInUSDT.
    uint256 usdtLocked;
    /// Number of bonds actually allocated after finalize.
    uint256 allocatedBonds;
    uint256 createdAt;
    SubscriptionStatus status;
}

struct FixedPayment {
    uint256 id;
    uint256 paymentDate;
    /// Block timestamp when `executeCouponPayment` actually ran.
    /// 0 until the payment is COMPLETED.
    uint256 actualPaymentDate;
    /// Total USDT smallest units to distribute to all holders.
    uint256 totalAmount;
    /// USDT remaining (= rounding dust after executeCouponPayment).
    uint256 remainingAmount;
    PaymentStatus status;
    bool reserveFunded;
}
