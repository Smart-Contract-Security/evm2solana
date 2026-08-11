// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

/**
 * @title IAssetHandler
 * @notice Minimal subset of dhedge-v2's `IAssetHandler` — only the methods
 *         `SimpleOracleModule` calls.
 * @dev Source: dhedge-v2 `contracts/interfaces/IAssetHandler.sol`.
 *      `getUSDPrice` returns an 18-decimal USD price (the handler promotes
 *      the aggregator's 8-decimal output by 1e10 internally) and reverts
 *      on staleness via `chainlinkTimeout` + per-aggregator `oracleHeartbeat`.
 */
interface IAssetHandler {
    /// @notice The dhedge-registered aggregator address for `asset` (0 = unregistered).
    function priceAggregators(address asset) external view returns (address aggregator);

    /// @notice Latest USD price for `asset`. Reverts if stale or unsupported.
    /// @return price 18-decimal USD price.
    function getUSDPrice(address asset) external view returns (uint256 price);
}
