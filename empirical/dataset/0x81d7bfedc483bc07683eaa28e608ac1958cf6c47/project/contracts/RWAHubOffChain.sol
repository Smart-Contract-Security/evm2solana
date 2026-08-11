//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/RWAHub.sol";
import "contracts/interfaces/IRWAHubOffChainRedemptions.sol";
import "contracts/interfaces/IRWAHubOffChainSubscriptions.sol";

abstract contract RWAHubOffChainRedemptions is
  RWAHub,
  IRWAHubOffChainRedemptions,
  IRWAHubOffChainSubscriptions
{
  // To enable and disable off chain redemptions
  bool public offChainRedemptionPaused;

  // To enable and disable off chain subscriptions
  bool public offChainSubscriptionPaused;

  // Minting fee specified in basis points
  uint256 public offChainMintFee = 0;

  constructor(
    address _collateral,
    address _rwa,
    address managerAdmin,
    address _assetSender,
    address _feeRecipient,
    address _assetRecipient,
    uint256 _minimumDepositAmount,
    uint256 _minimumRedemptionAmount,
    uint256 _maximumDepositAmount,
    uint256 _maximumRedemptionAmount
  )
    RWAHub(
      _collateral,
      _rwa,
      managerAdmin,
      _assetSender,
      _feeRecipient,
      _assetRecipient,
      _minimumDepositAmount,
      _minimumRedemptionAmount,
      _maximumDepositAmount,
      _maximumRedemptionAmount
    )
  {}

  /**
   * @notice Request a redemption to be serviced off chain.
   *
   * @param amountRWATokenToRedeem The requested redemption amount
   * @param offChainDestination    A hash of the destination to which
   *                               the request should be serviced to.
   */
  function requestRedemptionServicedOffchain(
    uint256 amountRWATokenToRedeem,
    bytes32 offChainDestination
  ) public virtual nonReentrant ifNotPaused(offChainRedemptionPaused) {
    if (amountRWATokenToRedeem < minimumRedemptionAmount) {
      revert RedemptionTooSmall();
    }

    if (amountRWATokenToRedeem > maximumRedemptionAmount) {
      revert RedemptionTooLarge();
    }

    bytes32 redemptionId = bytes32(redemptionRequestCounter++);

    rwa.burnFrom(msg.sender, amountRWATokenToRedeem);

    emit RedemptionRequestedServicedOffChain(
      msg.sender,
      redemptionId,
      amountRWATokenToRedeem,
      offChainDestination
    );
  }

  /**
   * @notice Function to pause off chain redemptoins
   */
  function pauseOffChainRedemption() external onlyRole(PRODUCT_ADMIN) {
    offChainRedemptionPaused = true;
    emit OffChainRedemptionPaused(msg.sender);
  }

  /**
   * @notice Function to unpause off chain redemptoins
   */
  function unpauseOffChainRedemption() external onlyRole(PRODUCT_ADMIN) {
    offChainRedemptionPaused = false;
    emit OffChainRedemptionUnpaused(msg.sender);
  }

  /**
   * @notice Request a subscription to be serviced off chain.
   *
   * @param user                   The address of the user who made the deposit
   * @param amount                 The requested subscription amount
   * @param offChainDestination    A hash of the destination to which
   *                               the request should be serviced to.
   */
  function requestSubscriptionServicedOffchain(
    address user,
    uint256 amount,
    bytes32 offChainDestination
  )
    public
    virtual
    nonReentrant
    onlyRole(OFFCHAIN_ADMIN)
    ifNotPaused(offChainSubscriptionPaused)
    checkRestrictions(user)
  {
    if (user == address(0)) {
      revert UserZeroAddress();
    }
    if (amount < minimumDepositAmount) {
      revert DepositTooSmall();
    }
    if (amount > maximumDepositAmount) {
      revert DepositTooLarge();
    }

    uint256 feesInCollateral = _getOffChainMintFees(amount);
    uint256 depositAmountAfterFee = amount - feesInCollateral;

    // Link the depositor to their deposit ID
    bytes32 depositId = bytes32(subscriptionRequestCounter++);
    depositIdToDepositor[depositId] = Depositor(
      user,
      depositAmountAfterFee,
      0
    );

    emit SubscriptionRequestedServicedOffChain(
      user,
      depositId,
      amount,
      depositAmountAfterFee,
      feesInCollateral,
      offChainDestination
    );
  }


  /**
   * @notice Function to pause off chain scriptions
   */
  function pauseOffChainSubscription() external onlyRole(PRODUCT_ADMIN) {
    offChainSubscriptionPaused = true;
    emit OffChainSubscriptionPaused(msg.sender);
  }

  /**
   * @notice Function to unpause off chain scriptions
   */
  function unpauseOffChainSubscription() external onlyRole(PRODUCT_ADMIN) {
    offChainSubscriptionPaused = false;
    emit OffChainSubscriptionUnpaused(msg.sender);
  }

  /**
   * @notice Admin function to set the mint fee
   *
   * @param _offChainMintFee The new mint fee specified in basis points
   *
   * @dev The maximum fee that can be set is 10_000 bps, or 100%
   */
  function setOffChainMintFee(uint256 _offChainMintFee) external onlyRole(LIMITATION_ADMIN) {
    if (_offChainMintFee > BPS_DENOMINATOR) {
      revert FeeTooLarge();
    }
    uint256 oldOffChainMintFee = offChainMintFee;
    offChainMintFee = _offChainMintFee;
    emit OffChainMintFeeSet(oldOffChainMintFee, _offChainMintFee);
  }

  /**
   * @notice Given amount of `collateral`, returns how much in fees
   *         are owed
   *
   *
   * @param collateralAmount Amount `collateral` to calculate fees
   *                         (in decimals of `collateral`)
   */
  function _getOffChainMintFees(
    uint256 collateralAmount
  ) internal view returns (uint256) {
    return (collateralAmount * offChainMintFee) / BPS_DENOMINATOR;
  }
}
