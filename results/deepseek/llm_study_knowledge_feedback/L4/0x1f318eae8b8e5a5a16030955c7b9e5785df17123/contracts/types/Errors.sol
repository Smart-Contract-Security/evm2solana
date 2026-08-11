// SPDX-License-Identifier: MIT

/// @title  Errors Library
/// @notice This library defines common error messages used throughout the system to ensure
///         better clarity and standardized error handling.
/// @dev    Each error represents a specific failure condition, allowing contracts to handle
///         issues more easily and transparently.
library Errors {
    // Note: Solana does not support custom error definitions with revert messages.
    // Instead, we use revert with a string message or a numeric code.
    // We'll define constants for error codes to maintain similar functionality.

    /// @dev Error thrown when a caller is not authorized for an account-scoped action
    string constant Unauthorized = "Unauthorized";

    /// @dev Error thrown when an address is address(0)
    string constant ZeroAddress = "ZeroAddress";

    /// @dev Error thrown when the number of shares is zero
    string constant ZeroShares = "ZeroShares";

    /// @dev Error thrown when the number of assets is zero
    string constant ZeroAssets = "ZeroAssets";

    /// @dev Error thrown when a token name or symbol is empty
    string constant EmptyNameOrSymbol = "EmptyNameOrSymbol";

    /// @dev Error thrown when there are no pending redeem shares
    string constant NoPendingRedeem = "NoPendingRedeem";

    /// @dev Error thrown when requested amount exceeds available balance
    string constant InsufficientBalance = "InsufficientBalance";

    /// @dev Error thrown when requested amount exceeds claimable amount
    string constant InsufficientClaimable = "InsufficientClaimable";

    /// @dev Error thrown when transfer amount is lower than expected
    string constant TransferInsufficient = "TransferInsufficient";

    /// @dev Error thrown when trying to use an invalid rate
    string constant InvalidRate = "InvalidRate";

    /// @dev Error thrown when rate is outside accepted bounds
    string constant RateOutOfBounds = "RateOutOfBounds";

    /// @dev Error thrown when fee exceeds configured max fee
    string constant InvalidFee = "InvalidFee";

    /// @dev Error thrown when an operation attempts to modify an account's own operator status
    string constant ERC7540SelfOperatorNotAllowed = "ERC7540SelfOperatorNotAllowed";

    /// @dev Error thrown when an ERC7540 authorization has expired
    string constant ERC7540Expired = "ERC7540Expired";

    /// @dev Error thrown when an ERC7540 authorization has already been used
    string constant ERC7540UsedAuthorization = "ERC7540UsedAuthorization";

    /// @dev Error thrown when an invalid signer is detected for ERC7540 authorization
    string constant ERC7540InvalidSigner = "ERC7540InvalidSigner";

    /// @dev Error thrown when the payout is set to zero in an ERC7540 operation
    string constant ERC7540ZeroPayout = "ERC7540ZeroPayout";

    /// @dev Error thrown when user attempts to call sync preview functions in async ERC7540 flow
    string constant ERC7540AsyncFlow = "ERC7540AsyncFlow";

    /// @dev Error thrown when unauthorized user tries to perform transaction via predicate proxy
    string constant NestPredicateProxyPredicateUnauthorizedTransaction = "NestPredicateProxyPredicateUnauthorizedTransaction";

    /// @dev Error thrown when the new upper exchange-rate bound is set below the minimum allowed value
    string constant UpperBoundTooSmall = "UpperBoundTooSmall";

    /// @dev Error thrown when the new lower exchange-rate bound is set above the maximum allowed value
    string constant LowerBoundTooLarge = "LowerBoundTooLarge";

    /// @dev Error thrown when attempting to set a management fee greater than the permitted maximum (20%)
    string constant ManagementFeeTooLarge = "ManagementFeeTooLarge";

    /// @dev Error thrown when a function is called while the contract is paused
    string constant Paused = "Paused";

    /// @dev Error thrown when attempting to claim fees but no fees are owed
    string constant ZeroFeesOwed = "ZeroFeesOwed";

    /// @dev Error thrown when a function restricted to the NestShare is called by another address
    string constant OnlyCallableByNestShare = "OnlyCallableByNestShare";

    /// @dev Error thrown when the update delay exceeds the maximum allowed duration of 14 days
    string constant UpdateDelayTooLarge = "UpdateDelayTooLarge";

    /// @dev Error thrown when exchange-rate update is attempted before minimumUpdateDelayInSeconds elapses
    string constant MinimumUpdateDelayNotPassed = "MinimumUpdateDelayNotPassed";

    /// @dev Error thrown when a message-only compose operation receives non-zero OFT tokens
    string constant UnexpectedNonZeroAmount = "UnexpectedNonZeroAmount";

    /// @dev Error thrown when an unrecognized redeem type is provided in compose payload
    string constant UnknownRedeemType = "UnknownRedeemType";

    /// @dev Error thrown when the share OFT is not a valid NestShare
    string constant ShareOFTNotNestShare = "ShareOFTNotNestShare";

    /// @dev Error thrown when the share token does not match the vault's share token
    string constant ShareTokenNotVaultShare = "ShareTokenNotVaultShare";

    /// @dev Error thrown when a recover call fails
    string constant RecoverFailed = "RecoverFailed";

    /// @dev Error thrown when msg.value is non-zero in a local cross-chain operation
    string constant NonZeroMsgValueLocal = "NonZeroMsgValueLocal";

    /// @dev Error thrown when attempting to set a performance fee greater than the permitted maximum (50%)
    string constant PerformanceFeeTooLarge = "PerformanceFeeTooLarge";

    /// @dev Error thrown when attempting to set a hurdle rate greater than the permitted maximum (30%)
    string constant HurdleRateTooLarge = "HurdleRateTooLarge";

    /// @dev Error thrown when attempting to set a holdback rate greater than 100%
    string constant HoldbackRateTooLarge = "HoldbackRateTooLarge";

    /// @dev Error thrown when attempting to set a crystallization window greater than the permitted maximum (365 days)
    string constant CrystallizationWindowTooLarge = "CrystallizationWindowTooLarge";

    /// @dev Error thrown when attempting to set epochs per window greater than the permitted maximum (52)
    string constant EpochsPerWindowTooLarge = "EpochsPerWindowTooLarge";

    /// @dev Error thrown when an update attempts to reapply the current value
    string constant SameValue = "SameValue";

    /// @dev Error thrown when attempting to renounce ownership (disabled for upgradeable flow)
    string constant RenounceOwnershipDisabled = "RenounceOwnershipDisabled";

    /// @dev Error thrown when the accountant does not implement the required rate-provider interface.
    string constant IncompatibleAccountant = "IncompatibleAccountant";

    /// @dev Error thrown when operator registry does not implement IERC7540Operator.isOperator(address,address)
    string constant IncompatibleOperatorRegistry = "IncompatibleOperatorRegistry";

    /// @dev Error thrown when keeper-supplied total share supply is below the local chain's totalSupply
    string constant TotalSupplyBelowLocal = "TotalSupplyBelowLocal";

    /// @dev Error thrown when a fee-related function is called on a spoke accountant
    string constant FeeAccrualDisabled = "FeeAccrualDisabled";
}