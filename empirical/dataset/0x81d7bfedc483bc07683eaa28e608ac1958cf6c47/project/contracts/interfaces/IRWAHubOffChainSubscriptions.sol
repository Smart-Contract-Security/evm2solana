// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

/**
 * @title IRWAHubOffChainSubscriptions
 * @notice Interface for handling off-chain subscriptions in the Real World Assets (RWA) hub.
 * @dev This interface defines functions related to off-chain subscription requests and their management.
 */
interface IRWAHubOffChainSubscriptions {
  /**
   * @notice Requests an off-chain subscription for a specific amount of collateral.
   * @dev This function initiates a subscription request to be serviced off-chain.
   * @param user The address of the user requesting the subscription.
   * @param amount The amount of collateral the user wishes to subscribe to.
   * @param offChainDestination The destination address or identifier for the off-chain subscription.
   */
  function requestSubscriptionServicedOffchain(
    address user,
    uint256 amount,
    bytes32 offChainDestination
  ) external;

  /**
   * @notice Pauses off-chain subscription requests.
   * @dev This function stops any new off-chain subscription requests from being processed.
   */
  function pauseOffChainSubscription() external;

  /**
   * @notice Unpauses off-chain subscription requests.
   * @dev This function allows off-chain subscription requests to be processed again after a pause.
   */
  function unpauseOffChainSubscription() external;

  /**
   * @notice Event emitted when offchain subscription request is submitted
   *
   * @param user                      The user requesting to mint
   * @param depositId                 The depositId of the request
   * @param collateralAmountDeposited The total amount deposited
   * @param depositAmountAfterFee     The value deposited - fee
   * @param feeAmount                 The fee amount taken
   *                                  (units of collateral)
   * @param offChainDestination       Hash of destination to which the
   *                                  request should be serviced to
   */
  event SubscriptionRequestedServicedOffChain(
    address indexed user,
    bytes32 indexed depositId,
    uint256 collateralAmountDeposited,
    uint256 depositAmountAfterFee,
    uint256 feeAmount,
    bytes32 offChainDestination
  );



  /**
   * @notice Event emitted when the off chain subscription feature is
   *         paused
   *
   * @param caller Address which initiated the pause
   */
  event OffChainSubscriptionPaused(address caller);

  /**
   * @notice Event emitted when the off chain subscription feature is
   *         unpaused
   *
   * @param caller Address which initiated the unpause
   */
  event OffChainSubscriptionUnpaused(address caller);

  /**
   * @notice Error thrown when attempting to use a zero address as a valid user.
   * @dev The zero address is not allowed for users in this context, as it represents an invalid or uninitialized address.
   */
  error UserZeroAddress();
}
