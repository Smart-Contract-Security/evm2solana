// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "contracts/interfaces/IPricer.sol";

contract Pricer is AccessControlEnumerable, IPricer {
  // Struct representing information for a given priceId
  struct PriceInfo {
    uint256 price;
    uint256 timestamp;
  }
  // Mapping from priceId to PriceInfo
  mapping(uint256 => PriceInfo) public prices;

  // Array of priceIds
  /// @dev These priceIds are not ordered by timestamp
  uint256[] public priceIds;

  // Pointer to last set priceId
  /// @dev This price may not be the latest price since prices can be added
  /// out of order in relation to their timestamp
  uint256 public currentPriceId;

  // Pointer to priceId associated with the latest price
  uint256 public latestPriceId;

  // @dev Role based access control roles
  bytes32 public constant PRICE_ADMIN = keccak256("PRICE_ADMIN");

  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(PRICE_ADMIN, admin);
  }

  /**
   * @notice Gets the latest price of the asset
   *
   * @return uint256 The latest price of the asset
   */
  function getLatestPrice() external view override returns (uint256) {
    return prices[latestPriceId].price;
  }
  /**
   * @notice Gets the current priceId
   *
   * @return uint256 The current priceId
   */
  function getCurrentPriceId() external view override returns (uint256) {
    return currentPriceId;
  }

  /**
   * @notice Gets the price of the asset by priceId
   *
   * @param priceId The priceId to get price
   * @return uint256 The price of the asset
   */
  function getPrice(uint256 priceId) external view override returns (uint256) {
    return prices[priceId].price;
  }

  /**
   * @notice Adds a price to the pricer
   *
   * @param price     The price to add
   * @param timestamp The timestamp associated with the price
   */
  function addPrice(
    uint256 price,
    uint256 timestamp
  ) external virtual override onlyRole(PRICE_ADMIN) {
    if (price == 0) {
      revert InvalidPrice();
    }

    // Set price
    uint256 priceId = ++currentPriceId;
    prices[priceId] = PriceInfo(price, timestamp);
    priceIds.push(priceId);

    // Update latestPriceId
    if (timestamp > prices[latestPriceId].timestamp) {
      latestPriceId = priceId;
    }

    emit PriceAdded(priceId, price, timestamp);
  }

  /**
   * @notice Updates a price in the pricer
   *
   * @param priceId The priceId to update
   * @param price   The price to set
   */
  function updatePrice(
    uint256 priceId,
    uint256 price
  ) external override onlyRole(PRICE_ADMIN) {
    if (price == 0) {
      revert InvalidPrice();
    }
    if (prices[priceId].price == 0) {
      revert PriceIdDoesNotExist();
    }

    PriceInfo memory oldPriceInfo = prices[priceId];
    prices[priceId] = PriceInfo(price, oldPriceInfo.timestamp);

    emit PriceUpdated(priceId, oldPriceInfo.price, price);
  }
}
