// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/RWAHubOffChain.sol";
import "contracts/AoABT/blocklist/BlocklistClient.sol";
import "contracts/AoABT/allowlist/AllowlistClient.sol";
import "contracts/interfaces/IAoABTManager.sol";

contract AoABTManager is
  RWAHubOffChainRedemptions,
  AllowlistClient,
  BlocklistClient,
  IAoABTManager
{

  // The maximum deposit amount for all users in one epoch
  uint256 public totalMaximumDepositAmountInEpoch;
  // The maximum redemption amount for all users in one epoch
  uint256 public totalMaximumRedemptionAmountInEpoch;

  // The epoch start timestamp
  uint256 public epochStartTimestamp;
  // The time interval of epoch
  uint256 public epochInterval;

  UserOperator public totalDepositEpochOperator;
  UserOperator public totalRedemptionEpochOperator;

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
    uint256 _maximumRedemptionAmount,
    address allowlist,
    address blocklist
  )
    RWAHubOffChainRedemptions(
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
    AllowlistClient(allowlist)
    BlocklistClient(blocklist)
  {}

  /**
   * @notice Function to enforce blocklist restrictions to be
   *         implemented on calls to `requestSubscription` and
   *         `claimRedemption`
   *
   * @param account The account to check blocklist list status
   *                for
   */
  function _checkRestrictions(address account) internal view override {
    if (!isAllowed(account)) {
      revert NotAllowlistAccount();
    }
    if (_isBlocked(account)) {
      revert BlockedAccount();
    }
  }

  /**
   * @notice Update blocklist address
   *
   * @param blocklist The new blocklist address
   */
  function setBlocklist(
    address blocklist
  ) external override onlyRole(PRODUCT_ADMIN) {
    require(blocklist != address(0));
    _setBlocklist(blocklist);
  }

  function setTotalMaximumDepositAmountInEpoch(
    uint256 _totalMaximumDepositAmountInEpoch
  ) external onlyRole(LIMITATION_ADMIN) {
    uint256 oldAmount = totalMaximumDepositAmountInEpoch;
    totalMaximumDepositAmountInEpoch = _totalMaximumDepositAmountInEpoch;
    emit TotalMaximumDepositAmountInEpochSet(oldAmount, _totalMaximumDepositAmountInEpoch);
  }

  function setTotalMaximumRedemptionAmountInEpoch(
    uint256 _totalMaximumRedemptionAmountInEpoch
  ) external onlyRole(LIMITATION_ADMIN) {
    uint256 oldAmount = totalMaximumRedemptionAmountInEpoch;
    totalMaximumRedemptionAmountInEpoch = _totalMaximumRedemptionAmountInEpoch;
    emit TotalMaximumRedemptionAmountInEpochSet(oldAmount, _totalMaximumRedemptionAmountInEpoch);
  }


  function setEpochStartTime(
    uint256 _epochStartTime
  ) external onlyRole(LIMITATION_ADMIN) {
    if (_epochStartTime >= block.timestamp) {
      revert EpochStartTimestampNotPast();
    }

    uint256 oldtime = epochStartTimestamp;
    epochStartTimestamp = _epochStartTime;
    emit EpochStartTimestampSet(oldtime, _epochStartTime);
  }

  function setEpochInterval(
    uint256 _epochInterval
  ) external onlyRole(LIMITATION_ADMIN) {
    uint256 oldInterval = epochInterval;
    epochInterval = _epochInterval;
    emit EpochIntervalSet(oldInterval, _epochInterval);
  }

  function _updateEpoch() internal view returns (uint256) {
    uint256 currentEpochTimestamp = 0;
    if (epochInterval != 0 && epochStartTimestamp != 0) {
      currentEpochTimestamp = epochStartTimestamp + ((block.timestamp - epochStartTimestamp) / epochInterval * epochInterval);
    }

    return currentEpochTimestamp;
  }


  function _checkAndUpdateTotalDepositLimit(uint256 amount) internal {
    if (epochInterval == 0 || totalMaximumDepositAmountInEpoch == 0) return;

    uint256 currentEpochTimestamp = _updateEpoch();

    uint256 totalAmount = amount;
    if (currentEpochTimestamp <= totalDepositEpochOperator.epochTimestamp) {
      totalAmount += totalDepositEpochOperator.amount;
    }

    if (totalAmount > totalMaximumDepositAmountInEpoch) {
      revert DepositAmountExceedEpochTotalMaximum();
    }
    totalDepositEpochOperator.epochTimestamp = currentEpochTimestamp;
    totalDepositEpochOperator.amount = totalAmount;
  }

  function _checkAndUpdateTotalRedemptionLimit(uint256 amount) internal {
    if (epochInterval == 0 || totalMaximumRedemptionAmountInEpoch == 0) return;

    uint256 currentEpochTimestamp = _updateEpoch();

    uint256 totalAmount = amount;
    if (currentEpochTimestamp <= totalRedemptionEpochOperator.epochTimestamp) {
      totalAmount += totalRedemptionEpochOperator.amount;
    }

    if (totalAmount > totalMaximumRedemptionAmountInEpoch) {
      revert RedemptionAmountExceedEpochTotalMaximum();
    }
    totalRedemptionEpochOperator.epochTimestamp = currentEpochTimestamp;
    totalRedemptionEpochOperator.amount = totalAmount;
  }



  /*//////////////////////////////////////////////////////////////
            Override the Subscription/Redemption Functions
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Function used by users to request subscription to the fund
   *
   * @param amount The amount of collateral one wished to deposit
   */
  function requestSubscription(
    uint256 amount
  )
    public
    virtual
    override
  {
    _checkAndUpdateTotalDepositLimit(amount);
    super.requestSubscription(amount);
  }


  /**
   * @notice Function used by users to request a redemption from the fund
   *
   * @param amount The amount (in units of `rwa`) that a user wishes to redeem
   *               from the fund
   */
  function requestRedemption(
    uint256 amount
  )
    public
    virtual
    override
  {
    _checkAndUpdateTotalRedemptionLimit(amount);
    super.requestRedemption(amount);
  }

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
  )
    public
    virtual
    override
  {
    _checkAndUpdateTotalRedemptionLimit(amountRWATokenToRedeem);
    super.requestRedemptionServicedOffchain(amountRWATokenToRedeem, offChainDestination);
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
    override
  {
    _checkAndUpdateTotalDepositLimit(amount);
    super.requestSubscriptionServicedOffchain(user, amount, offChainDestination);
  }

  /**
   * @notice Update allowlist address
   *
   * @param allowlist The new allowlist address
   */
  function setAllowlist(
    address allowlist
  ) external override onlyRole(PRODUCT_ADMIN) {
    require(allowlist != address(0));
    _setAllowlist(allowlist);
  }
}
