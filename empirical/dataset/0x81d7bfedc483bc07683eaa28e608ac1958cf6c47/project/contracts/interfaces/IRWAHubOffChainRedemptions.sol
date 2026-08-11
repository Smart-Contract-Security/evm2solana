// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

/**
 * @title IRWAHubOffChainRedemptions
 * @notice Interface for handling off-chain redemptions in the Real World Assets (RWA) hub.
 * @dev This interface defines functions related to off-chain redemption requests and their management.
 */
interface IRWAHubOffChainRedemptions {
  /**
   * @notice Requests an off-chain redemption for a specific amount of RWA tokens.
   * @dev This function initiates a redemption request to be serviced off-chain.
   * @param amountRWATokenToRedeem The amount of RWA tokens the user wishes to redeem.
   * @param offChainDestination The destination address or identifier for the off-chain redemption.
   */
  function requestRedemptionServicedOffchain(
    uint256 amountRWATokenToRedeem,
    bytes32 offChainDestination
  ) external;

  /**
   * @notice Pauses off-chain redemption requests.
   * @dev This function stops any new off-chain redemption requests from being processed.
   */
  function pauseOffChainRedemption() external;

  /**
   * @notice Unpauses off-chain redemption requests.
   * @dev This function allows off-chain redemption requests to be processed again after a pause.
   */
  function unpauseOffChainRedemption() external;

  /**
   * @notice Event emitted when redemption request is submitted
   *
   * @param user                The user submitting the offchain redemption request
   * @param redemptionId        The id corresponding to a given offchain redemption request
   * @param rwaTokenAmountIn    The amount of cash being burned
   * @param offChainDestination Hash of destination to which the request
   *                            should be serviced to
   */
  event RedemptionRequestedServicedOffChain(
    address indexed user,
    bytes32 indexed redemptionId,
    uint256 rwaTokenAmountIn,
    bytes32 offChainDestination
  );

  /**
   * @notice Event emitted when the off chain redemption feature is
   *         paused
   *
   * @param caller Address which initiated the pause
   */
  event OffChainRedemptionPaused(address caller);

  /**
   * @notice Event emitted when the off chain redemption feature is
   *         unpaused
   *
   * @param caller Address which initiated the unpause
   */
  event OffChainRedemptionUnpaused(address caller);

}
