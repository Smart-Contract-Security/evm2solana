// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "../Interfaces/ITroveManager.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IBoldToken.sol";
import "../Types/LatestTroveData.sol";
import "../Types/LatestBatchData.sol";
import "../Interfaces/ISortedTroves.sol";

// -- individual delegation --
struct InterestIndividualDelegate {
    address account;
    uint128 minInterestRate;
    uint128 maxInterestRate;
    uint256 minInterestRateChangePeriod;
}

struct InterestBatchManager {
    uint128 minInterestRate;
    uint128 maxInterestRate;
    uint256 minInterestRateChangePeriod;
}

struct LocalVariables_openTrove {
    ITroveManager troveManager;
    IActivePool activePool;
    IBoldToken boldToken;
    uint256 troveId;
    uint256 price;
    uint256 avgInterestRate;
    uint256 entireDebt;
    uint256 ICR;
    uint256 newTCR;
    bool newOracleFailureDetected;
}

struct LocalVariables_adjustTrove {
    IActivePool activePool;
    IBoldToken boldToken;
    LatestTroveData trove;
    uint256 price;
    bool isBelowCriticalThreshold;
    uint256 newICR;
    uint256 newDebt;
    uint256 newColl;
    bool newOracleFailureDetected;
}

struct LocalVariables_setInterestBatchManager {
    ITroveManager troveManager;
    IActivePool activePool;
    ISortedTroves sortedTroves;
    address oldBatchManager;
    LatestTroveData trove;
    LatestBatchData oldBatch;
    LatestBatchData newBatch;
}
