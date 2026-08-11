// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultPriceFeed
 * @notice Interface for vault-specific price feeds
 * @dev Provides both view-based and state-changing price functions
 */
interface IVaultPriceFeed {
    /**
     * @notice Get current price from Chainlink oracles (view function)
     * @return price Price scaled appropriately for the collateral
     */
    function getPrice() external view returns (uint256 price);

    /**
     * @notice Fetch price with state updates (calls underlying priceFeed.fetchPrice)
     * @return price The fetched price
     * @return oracleDown True if an oracle failed during this call
     */
    function fetchPrice() external returns (uint256 price, bool oracleDown);
}
