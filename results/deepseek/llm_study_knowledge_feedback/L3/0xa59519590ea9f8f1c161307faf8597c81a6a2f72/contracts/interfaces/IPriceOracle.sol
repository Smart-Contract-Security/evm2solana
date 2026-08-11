// SPDX-License-Identifier: MIT

/// @notice Cobo-style NAV: **1e18 fixed-point** (see `ICoboFundOracle` in cobo-tokenization).
interface IPriceOracle {
    function getLatestPrice() external view returns (uint64 nav1e18);
}