// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

/**
 * @title IAoABTManager
 * @notice Interface for the Centralized Multi-Manager Fund (AoABT) Manager contract.
 * @dev This interface defines the functions and events required to manage user operations
 *      such as deposits and redemptions in an epoch-based system.
 */
interface IAoABTManager {
  /**
   * @notice Struct representing a user's operation (deposit or redemption).
   * @dev Contains the amount involved in the operation and the epoch timestamp.
   * @param amount The amount the user is depositing or redeeming.
   * @param epochTimestamp The epoch timestamp associated with the operation.
   */
  struct UserOperator {
    uint256 amount;
    uint256 epochTimestamp;
  }

  /**
   * @notice Sets the total maximum deposit amount allowed in a single epoch.
   * @param _totalMaximumDepositAmountInEpoch The new maximum deposit amount.
   */
  function setTotalMaximumDepositAmountInEpoch(
    uint256 _totalMaximumDepositAmountInEpoch
  ) external;

  /**
   * @notice Sets the total maximum redemption amount allowed in a single epoch.
   * @param _totalMaximumRedemptionAmountInEpoch The new maximum redemption amount.
   */
  function setTotalMaximumRedemptionAmountInEpoch(
    uint256 _totalMaximumRedemptionAmountInEpoch
  ) external;

  /**
   * @notice Sets the start time of the epoch.
   * @param _epochStartTime The new epoch start timestamp.
   */
  function setEpochStartTime(
    uint256 _epochStartTime
  ) external;

  /**
   * @notice Sets the interval duration between epochs.
   * @param _epochInterval The new epoch interval duration.
   */
  function setEpochInterval(
    uint256 _epochInterval
  ) external;

  /**
   * @notice Event emitted when a new epoch total deposit maximum is set.
   *         All units are in 1e18
   *
   * @param oldTotalEpochDepositMaximum The old total deposit maximum value
   * @param newTotalEpochDepositMaximum The new total deposit maximum value
   */
  event TotalMaximumDepositAmountInEpochSet(
    uint256 oldTotalEpochDepositMaximum,
    uint256 newTotalEpochDepositMaximum
  );

  /**
   * @notice Event emitted when a new epoch total redemption maximum is set.
   *         All units are in 1e18
   *
   * @param oldTotalEpochRedemptionMaximum The old total redemption maximum value
   * @param newTotalEpochRedemptionMaximum The new total redemption maximum value
   */
  event TotalMaximumRedemptionAmountInEpochSet(
    uint256 oldTotalEpochRedemptionMaximum,
    uint256 newTotalEpochRedemptionMaximum
  );

  /**
   * @notice Event emitted when a new epoch start time is set.
   *
   * @param oldEpochStartTime The old epoch start timestamp value
   * @param newEpochStartTime The new epoch start timestamp value
   */
  event EpochStartTimestampSet(
    uint256 oldEpochStartTime,
    uint256 newEpochStartTime
  );

  /**
   * @notice Event emitted when a new epoch interval is set.
   *
   * @param oldEpochInterval The old epoch interval value
   * @param newEpochInterval The new epoch interval value
   */
  event EpochIntervalSet(
    uint256 oldEpochInterval,
    uint256 newEpochInterval
  );

  /**
   * @notice Error thrown when the provided epoch start timestamp is not in the past.
   */
  error EpochStartTimestampNotPast();

  /**
   * @notice Error thrown when a deposit amount exceeds the total maximum allowed for the epoch.
   */
  error DepositAmountExceedEpochTotalMaximum();

  /**
   * @notice Error thrown when a redemption amount exceeds the total maximum allowed for the epoch.
   */
  error RedemptionAmountExceedEpochTotalMaximum();
}
