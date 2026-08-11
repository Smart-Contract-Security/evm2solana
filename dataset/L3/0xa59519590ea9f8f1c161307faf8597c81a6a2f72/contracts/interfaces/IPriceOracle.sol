// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Cobo-style NAV: **1e18 fixed-point** (see `ICoboFundOracle` in cobo-tokenization).
interface IPriceOracle {
    function getLatestPrice() external view returns (uint256 nav1e18);
}
