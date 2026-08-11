// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title  ErrorsLib
 * @notice Custom error definitions for the CoinBank deposit / staking system.
 *         Using custom errors instead of revert strings reduces gas costs and
 *         improves ABI clarity for off-chain tooling.
 */
library ErrorsLib {
    error PlanNotFound(uint256 planId);
    error NoPlanForDuration(uint256 lockDuration);

    error ZeroAmount();
    error ZeroTokenAddress();
    error ZeroDepositId();
    error ZeroLockDuration();
    error TokenNotAuthorized(address token);

    error DepositIdAlreadyUsed(bytes32 depositId);
    error DepositNotFound(bytes32 depositId);
    error NotDepositor(address caller, address depositor);

    error LockPeriodNotExpired(uint256 unlocksAt, uint256 currentTime);
    error AlreadyWithdrawn();
    error NoProfitAccrued();
    error InsufficientContractBalance(uint256 required, uint256 available);

    error InvalidKeeperAddress();

    error InsufficientReserveForProfit(address token, uint256 required, uint256 available);
    error ExceedsRescuableAmount(address token, uint256 requested, uint256 available);
}
