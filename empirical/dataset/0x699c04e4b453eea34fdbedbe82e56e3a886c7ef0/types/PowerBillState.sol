// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Per-wallet power-bill state. Bills apply only to rooms at index >= 2.
struct PowerBillState {
    uint64 billLastSettlementTimestamp;
    uint64 billWindowStart;
    uint64 billWindowEnd;
    uint128 billDebtAccrued; // dMETH wei
    bool powerOffline;
}
