// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library BoostHubErrors {
    error ZeroAddress();
    error ZeroAmount();
    error InvalidPool();
    error PoolInactive();
    error PoolShutdown();
    error StrategyNotApproved();
    error RewardTokenNotRegistered();
    error RewardTokenLimitExceeded();
    error DuplicateRewardToken();
    error InvalidGaugeAsset();
    error CheckpointFailed();
    error CheckpointSelectorNotSet();
    error InvalidFee();
    error NothingToClaim();
    error LengthMismatch();
    error ZeroSelector();
    error InvalidUpdateCallArg();
    error InvalidUpdateCallReturn();
    error InvalidSnapshotSpace();
}
