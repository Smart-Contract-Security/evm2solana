// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";

library NestVaultCoreTypes {
    struct NestVaultCoreStorage {
        uint256 minRate;
        uint256 totalPendingShares;
        NestHubAccountant accountant;
        mapping(address => mapping(address => bool)) isVaultOperator;
        mapping(address => mapping(bytes32 => bool)) authorizations;
        mapping(address => PendingRedeem) pendingRedeem;
        mapping(address => ClaimableRedeem) claimableRedeem;
        mapping(Fees => Fee) maxFees;
        mapping(Fees => Fee) fees;
        mapping(Fees => uint256) claimableFees;
        OperatorRegistry operatorRegistry;
    }

    struct PendingRedeem {
        uint256 shares;
    }

    struct ClaimableRedeem {
        uint256 assets;
        uint256 shares;
    }

    enum Fees {
        InstantRedemption,
        Deposit,
        Redemption
    }

    struct Fee {
        uint32 rate;
        uint256 flat;
    }

    uint32 internal constant FEE_CAP = 0.2e6;

    uint256 internal constant UPPER_BOUND_RATE_CAP = 1e30;

    event FeeAccrued(uint8 indexed feeType, address indexed payer, uint256 amount);
}