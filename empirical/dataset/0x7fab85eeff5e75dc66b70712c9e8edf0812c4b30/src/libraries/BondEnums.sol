// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum BondStatus {
    DRAFT,
    ISSUER_REJECTED,
    READY_FOR_SUBSCRIPTION,
    SUBSCRIPTION_OPEN,
    SUBSCRIPTION_CLOSED,
    ISSUED,
    NOT_ISSUED,
    REDEEMED,
    DEACTIVATED
}

enum SubscriptionStatus {
    PENDING,
    OWNER_APPROVED,
    OWNER_REJECTED,
    ALLOCATED_FULL,
    ALLOCATED_PARTIAL,
    REFUNDED,
    CANCELLED
}

enum PaymentStatus {
    SCHEDULED,
    FUNDED,
    COMPLETED
}