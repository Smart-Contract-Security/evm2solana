// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

/**
 * @title IPricerReader
 * @notice Interface for reading prices from a pricing oracle.
 * @dev This interface defines functions for retrieving the latest price and
 *      historical prices using a unique price identifier.
 */
interface IPricerReader {
  /**
   * @notice Gets the latest price of the asset
   *
   * @return uint256 The latest price of the asset
   */
  function getLatestPrice() external view returns (uint256);

  /**
   * @notice Gets the current price id of the asset.
   * @dev This function returns the current price id in the pricer.
   *
   * @return uint256 The current price id of the asset.
   */
  function getCurrentPriceId() external view returns (uint256);
  /**
   * @notice Gets the price of the asset at a specific priceId
   *
   * @param priceId The priceId at which to get the price
   *
   * @return uint256 The price of the asset with the given priceId
   */
  function getPrice(uint256 priceId) external view returns (uint256);
}
