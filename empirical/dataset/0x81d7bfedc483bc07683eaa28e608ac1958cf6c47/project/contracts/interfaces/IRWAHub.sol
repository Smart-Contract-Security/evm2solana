// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

/**
 * @title IRWAHub
 * @notice Interface for managing the operations related to Real World Assets (RWA).
 * @dev This interface defines functions and events related to subscription, redemption,
 *      price management, and error handling within the RWA hub.
 */
interface IRWAHub {
  // Struct to contain the deposit information for a given depositId
  struct Depositor {
    address user;
    uint256 amountDepositedMinusFees;
    uint256 priceId;
  }

  // Struc to contain withdrawal infromation for a given redemptionId
  struct Redeemer {
    address user;
    uint256 amountRwaTokenBurned;
    uint256 priceId;
  }

  /**
   * @notice Requests a subscription (deposit) of a specific amount from the user.
   *
   * @param amount The amount of collateral the user wants to deposit.
   */
  function requestSubscription(uint256 amount) external;

  /**
   * @notice Allows a user to claim the minting of assets corresponding to specific deposit IDs.
   *
   * @param depositIds An array of deposit IDs for which the user wants to claim the minted assets.
   */
  function claimMint(bytes32[] calldata depositIds) external;

  /**
   * @notice Requests the redemption of a specific amount of RWA tokens from the user.
   *
   * @param amount The amount of RWA tokens the user wants to redeem.
   */
  function requestRedemption(uint256 amount) external;

  /**
   * @notice Allows a user to claim the redemption of assets corresponding to specific redemption IDs.
   *
   * @param redemptionIds An array of redemption IDs for which the user wants to claim the redeemed assets.
   */
  function claimRedemption(bytes32[] calldata redemptionIds) external;

  /**
   * @notice Sets the price ID for a list of deposits, determining their value.
   *
   * @param depositIds An array of deposit IDs for which the price IDs are being set.
   * @param priceIds An array of price IDs corresponding to the deposit IDs.
   */
  function setPriceIdForDeposits(
    bytes32[] calldata depositIds,
    uint256[] calldata priceIds
  ) external;

  /**
   * @notice Sets the price ID for a list of redemptions, determining their value.
   *
   * @param redemptionIds An array of redemption IDs for which the price IDs are being set.
   * @param priceIds An array of price IDs corresponding to the redemption IDs.
   */
  function setPriceIdForRedemptions(
    bytes32[] calldata redemptionIds,
    uint256[] calldata priceIds
  ) external;

  /**
   * @notice Sets the address of a new pricer contract.
   *
   * @param newPricer The address of the new pricer contract.
   */
  function setPricer(address newPricer) external;

  /**
   * @notice Overwrites the depositor information for a specific deposit ID.
   *
   * @param depositIdToOverride The ID of the deposit to overwrite.
   * @param user The address of the new depositor.
   * @param depositAmountAfterFee The amount of the deposit after fees.
   * @param priceId The price ID associated with the new depositor's deposit.
   */
  function overwriteDepositor(
    bytes32 depositIdToOverride,
    address user,
    uint256 depositAmountAfterFee,
    uint256 priceId
  ) external;

  /**
   * @notice Overwrites the redeemer information for a specific redemption ID.
   *
   * @param redemptionIdToOverride The ID of the redemption to overwrite.
   * @param user The address of the new redeemer.
   * @param rwaTokenAmountBurned The amount of RWA tokens burned by the new redeemer.
   * @param priceId The price ID associated with the new redeemer's redemption.
   */
  function overwriteRedeemer(
    bytes32 redemptionIdToOverride,
    address user,
    uint256 rwaTokenAmountBurned,
    uint256 priceId
  ) external;

  /**
   * @notice Sets the recipient address for the assets.
   *
   * @param setAssetRecipient The address to set as the new asset recipient.
   */
  function setAssetRecipient(
    address setAssetRecipient
  ) external;

  /**
   * @notice Event emitted when fee recipient is set
   *
   * @param oldFeeRecipient Old fee recipient
   * @param newFeeRecipient New fee recipient
   */
  event FeeRecipientSet(address oldFeeRecipient, address newFeeRecipient);

  /**
   * @notice Event emitted when the assetSender is changed
   *
   * @param oldAssetSender The address of the old assetSender
   * @param newAssetSender The address of the new assetSender
   */
  event AssetSenderSet(address oldAssetSender, address newAssetSender);

  /**
   * @notice Event emitted when minimum deposit amount is set
   *
   * @param oldMinimum Old minimum
   * @param newMinimum New minimum
   *
   * @dev See inheriting contract for decimals representation
   */
  event MinimumDepositAmountSet(uint256 oldMinimum, uint256 newMinimum);

  /**
   * @notice Event emitted when a new redeem minimum is set.
   *         All units are in 1e18
   *
   * @param oldRedemptionMin The old redeem minimum value
   * @param newRedemptionMin The new redeem minimum value
   */
  event MinimumRedemptionAmountSet(
    uint256 oldRedemptionMin,
    uint256 newRedemptionMin
  );

  /**
   * @notice Event emitted when maximum deposit amount is set
   *
   * @param oldMaximum Old maximum
   * @param newMaximum New maximum
   *
   * @dev See inheriting contract for decimals representation
   */
  event MaximumDepositAmountSet(uint256 oldMaximum, uint256 newMaximum);

  /**
   * @notice Event emitted when a new redeem maximum is set.
   *         All units are in 1e18
   *
   * @param oldRedemptionMax The old redeem maximum value
   * @param newRedemptionMax The new redeem maximum value
   */
  event MaximumRedemptionAmountSet(
      uint256 oldRedemptionMax,
      uint256 newRedemptionMax
  );

  /**
   * @notice Event emitted when mint fee is set
   *
   * @param oldFee Old fee
   * @param newFee New fee
   *
   * @dev See inheriting contract for decimals representation
   */
  event MintFeeSet(uint256 oldFee, uint256 newFee);

  /**
   * @notice Event emitted when off chain mint fee is set
   *
   * @param oldFee Old fee
   * @param newFee New fee
   *
   * @dev See inheriting contract for decimals representation
   */
  event OffChainMintFeeSet(uint256 oldFee, uint256 newFee);

  /**
   * @notice Event emitted when redeem fee is set
   *
   * @param oldFee Old fee
   * @param newFee New fee
   *
   * @dev see inheriting contract for decimal representation
   */
  event RedemptionFeeSet(uint256 oldFee, uint256 newFee);

  /**
   * @notice Event emitted when redemption request is submitted
   *
   * @param user         The user submitting the redemption request
   * @param redemptionId The id corresponding to a given redemption
   * @param rwaAmountIn  The amount of cash being burned
   */
  event RedemptionRequested(
    address indexed user,
    bytes32 indexed redemptionId,
    uint256 rwaAmountIn
  );

  /**
   * @notice Event emitted when a mint request is submitted
   *
   * @param user                      The user requesting to mint
   * @param depositId                 The depositId of the request
   * @param collateralAmountDeposited The total amount deposited
   * @param depositAmountAfterFee     The value deposited - fee
   * @param feeAmount                 The fee amount taken
   *                                  (units of collateral)
   */
  event MintRequested(
    address indexed user,
    bytes32 indexed depositId,
    uint256 collateralAmountDeposited,
    uint256 depositAmountAfterFee,
    uint256 feeAmount
  );

  /**
   * @notice Event emitted when a redemption request is completed
   *
   * @param user                     The address of the user getting the funds
   * @param redemptionId             The id corresponding to a given redemption
   *                                 requested
   * @param rwaAmountRequested       Amount of RWA originally requested by the user
   * @param collateralAmountReturned Amount of collateral received by the user
   * @param price                    The price at which the redemption was
   *                                 serviced at
   * @param fee                      The fee amount taken
   */
  event RedemptionCompleted(
    address indexed user,
    bytes32 indexed redemptionId,
    uint256 rwaAmountRequested,
    uint256 collateralAmountReturned,
    uint256 price,
    uint256 fee
);

  /**
   * @notice Event emitted when a Mint request is completed
   *
   * @param user                      The address of the user getting the funds
   * @param depositId                 The depositId of the mint request
   * @param rwaAmountOut              The amount of RWA token minted to the
   *                                  user
   * @param collateralAmountDeposited The amount of collateral deposited
   * @param price                     The price set for the given
   *                                  deposit id
   * @param priceId                   The priceId used to determine price
   */
  event MintCompleted(
    address indexed user,
    bytes32 indexed depositId,
    uint256 rwaAmountOut,
    uint256 collateralAmountDeposited,
    uint256 price,
    uint256 priceId
  );

  /**
   * @notice Event emitted when a deposit has its corresponding priceId set
   *
   * @param depositIdSet The Deposit Id for which the price Id is being set
   * @param priceIdSet   The price Id being associate with a deposit Id
   */
  event PriceIdSetForDeposit(
    bytes32 indexed depositIdSet,
    uint256 indexed priceIdSet
  );

  /**
   * @notice Event Emitted when a redemption has its corresponding priceId set
   *
   * @param redemptionIdSet The Redemption Id for which the price Id is being
   *                        set
   * @param priceIdSet      The Price Id being associated with a redemption Id
   */
  event PriceIdSetForRedemption(
    bytes32 indexed redemptionIdSet,
    uint256 indexed priceIdSet
  );

  /**
   * @notice Event emitted when a new Pricer contract is set
   *
   * @param oldPricer The address of the old pricer contract
   * @param newPricer The address of the new pricer contract
   */
  event NewPricerSet(address oldPricer, address newPricer);

  /**
   * @notice Event emitted when request subscriptions are paused
   *
   * @param caller Address which initiated the pause
   */
  event SubscriptionPaused(address caller);

  /**
   * @notice Event emitted when claim subscriptions are paused
   *
   * @param caller Address which initiated the pause
   */
  event ClaimSubscriptionPaused(address caller);

  /**
   * @notice Event emitted when request redemptions are paused
   *
   * @param caller Address which initiated the pause
   */
  event RedemptionPaused(address caller);

  /**
   * @notice Event emitted when claim redemptions are paused
   *
   * @param caller Address which initiated the pause
   */
  event ClaimRedemptionPaused(address caller);

  /**
   * @notice Event emitted when request subscriptions are unpaused
   *
   * @param caller Address which initiated the unpause
   */
  event SubscriptionUnpaused(address caller);

  /**
   * @notice Event emitted when claim subscriptions are unpaused
   *
   * @param caller Address which initiated the unpause
   */
  event ClaimSubscriptionUnpaused(address caller);

  /**
   * @notice Event emitted when request redemptions are unpaused
   *
   * @param caller Address which initiated the unpause
   */
  event RedemptionUnpaused(address caller);

  /**
   * @notice Event emitted when claim redemptions are unpaused
   *
   * @param caller Address which initiated the unpause
   */
  event ClaimRedemptionUnpaused(address caller);


  /**
   * @notice Event emitted when the depositor information is overwritten for a specific deposit ID.
   *
   * @param depositId The ID of the deposit whose depositor information is being overwritten.
   * @param oldDepositor The address of the previous depositor.
   * @param newDepositor The address of the new depositor.
   * @param oldPriceId The previous price ID associated with the deposit.
   * @param newPriceId The new price ID associated with the deposit.
   * @param oldDepositAmount The amount of the deposit before overwriting.
   * @param newDepositAmount The amount of the deposit after overwriting.
   */
  event DepositorOverwritten(
    bytes32 indexed depositId,
    address oldDepositor,
    address newDepositor,
    uint256 oldPriceId,
    uint256 newPriceId,
    uint256 oldDepositAmount,
    uint256 newDepositAmount
  );

  /**
   * @notice Event emitted when the redeemer information is overwritten for a specific redemption ID.
   *
   * @param redemptionId The ID of the redemption whose redeemer information is being overwritten.
   * @param oldRedeemer The address of the previous redeemer.
   * @param newRedeemer The address of the new redeemer.
   * @param oldPriceId The previous price ID associated with the redemption.
   * @param newPriceId The new price ID associated with the redemption.
   * @param oldRWATokenAmountBurned The amount of RWA tokens burned before overwriting.
   * @param newRWATokenAmountBurned The amount of RWA tokens burned after overwriting.
   */
  event RedeemerOverwritten(
    bytes32 indexed redemptionId,
    address oldRedeemer,
    address newRedeemer,
    uint256 oldPriceId,
    uint256 newPriceId,
    uint256 oldRWATokenAmountBurned,
    uint256 newRWATokenAmountBurned
  );

  /**
   * @notice Event emitted when the assetRecipient is changed
   *
   * @param oldAssetRecipient The address of the old assetRecipient
   * @param newAssetRecipient The address of the new assetRecipient
   */
  event AssetRecipientSet(
    address oldAssetRecipient,
    address newAssetRecipient
  );

  /**
   * @notice Error indicating that the price ID was not set.
   */
  error PriceIdNotSet();

  /**
   * @notice Error indicating that there is a mismatch in the size of input arrays.
   */
  error ArraySizeMismatch();

  /**
   * @notice Error indicating that the deposit amount is too small.
   */
  error DepositTooSmall();

  /**
   * @notice Error indicating that the redemption amount is too small.
   */
  error RedemptionTooSmall();

  /**
   * @notice Error indicating that the deposit amount exceeds the allowed limit.
   */
  error DepositTooLarge();

  /**
   * @notice Error indicating that the redemption amount exceeds the allowed limit.
   */
  error RedemptionTooLarge();

  /**
   * @notice Error indicating that the collateral amount cannot be zero.
   */
  error CollateralCannotBeZero();

  /**
   * @notice Error indicating that the RWA token amount cannot be zero.
   */
  error RWACannotBeZero();

  /**
   * @notice Error indicating that the asset sender address cannot be zero.
   */
  error AssetSenderCannotBeZero();

  /**
   * @notice Error indicating that the fee recipient address cannot be zero.
   */
  error FeeRecipientCannotBeZero();

  /**
   * @notice Error indicating that the asset recipient address cannot be zero.
   */
  error AssetRecipientCannotBeZero();

  /**
   * @notice Error indicating that the fee amount is too large.
   */
  error FeeTooLarge();

  /**
   * @notice Error indicating that the amount is too small for the operation.
   */
  error AmountTooSmall();

  /**
   * @notice Error indicating that the depositor address is null.
   */
  error DepositorNull();

  /**
   * @notice Error indicating that the redeemer address is null.
   */
  error RedeemerNull();

  /**
   * @notice Error indicating that the feature is currently paused.
   */
  error FeaturePaused();

  /**
   * @notice Error indicating that the price ID has already been set.
   */
  error PriceIdAlreadySet();

  /**
   * @notice Error indicating that the manager_admin address cannot be zero.
   */
  error ManagerAdminCannotBeZero();

  /**
   * @notice Error thrown when an invalid price id is provided.
   */
  error InvalidPriceId();
}
