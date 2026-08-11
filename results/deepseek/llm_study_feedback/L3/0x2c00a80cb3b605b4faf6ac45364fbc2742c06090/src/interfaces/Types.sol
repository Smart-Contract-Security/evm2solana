// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'solana';

struct PriceEntry {
    address asset;
    uint256 price;
    uint8 priceDecimals;
    uint64 asOfTimestamp;
}

struct SignedPriceBundle {
    uint64 round;
    uint64 deadline;
    PriceEntry[] entries;
    bytes32 assetSetDigest;
    address signer;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct OndoTarget {
    address token;
    uint16 bps;
}

struct BatchHint {
    uint16 maxSlippageBps;
    uint16 maxLossPercentBps;
}

struct Trade {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
}

struct RebalanceBuy {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
}

enum RequestStatus {
    Executing,
    Completed,
    Failed
}

enum BatchStatus {
    PendingProxy,
    Settled,
    Failed
}

enum RebalanceTrigger {
    Active,
    PassivePeriodic,
    PassiveRiskEvent
}

struct PassiveRebalanceParams {
    Trade[] sells;
    RebalanceBuy[] buys;
    address[] targetTokens;
    uint256[] targetWeights;
    RebalanceTrigger trigger;
    uint8 riskLevel;
    bytes32 reasonHash;
    SignedPriceBundle priceBundle;
}