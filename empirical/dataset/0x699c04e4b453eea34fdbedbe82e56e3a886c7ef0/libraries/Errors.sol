// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Errors {
    // Onboarding / room state
    error IncorrectValue();
    error AlreadyPurchasedInitialFactory();
    error NeedToInitializeFacility();
    error AlreadyAtMaxFacility();
    error CantBuyNewFacilityYet();
    error NewFacilityNotInProduction();
    error InvalidFacilityIndex();
    error NonExistentFacility();
    error CantModifyStarterFacility();
    error FacilityDimensionsInvalid();
    error InvalidPowerOutput();

    // Miners
    error StarterMinerAlreadyAcquired();
    error InvalidMinerCoordinates();
    error FacilityInadequatePowerOutput();
    error MinerCapacityReached();
    error MinerNotInProduction();
    error PlayerDoesNotOwnMiner();
    error InvalidMinerIndex();
    error NonExistentMiner();
    error CantModifyStarterMiner();
    error InvalidReferrer();

    // Rewards / claims
    error NoRewardsPending();
    error MiningHasntStarted();
    error SeasonNotStarted();
    error SeasonAlreadyStarted();
    error SeasonEnded();
    error InvalidClaimSplit();
    error PlayerOnClaimCooldown();

    // Power bill
    error NoPowerBill();
    error NoBillDue();
    error RoomOffline();

    // Generic
    error TooPoor();
    error InvalidFee();
    error WithdrawFailed();
    error ZeroAddress();
    error NotAuthorized();
}
