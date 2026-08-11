// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Errors
/// @notice Shared custom errors used across the suite. Centralising these
/// avoids accidental string-revert drift between modules and is meaningfully
/// cheaper than `require(..., "msg")`.
library Errors {
    error NotAuthorized();          // generic auth failure
    error WrongPhase();             // operation called in the wrong protocol phase
    error ZeroAddress();
    error ZeroAmount();
    error AlreadyInitialised();
    error InvalidRarity();
    error InvalidStat();
    error InvalidTraitIndex();
    error PotentialOverflow();
    error UnknownPlayer();
    error CardDoesNotExist();
    error PackTierUnknown();
    error PackAlreadyOpened();
    error CallbackOutOfOrder();
    error InsufficientPayment();
}
