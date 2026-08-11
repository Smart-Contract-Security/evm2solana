// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Surface RushClaim uses to read a wallet's burn-K multiplier.
@program_id("11111111111111111111111111111111")
interface IRushBurn {
    /// @return kScaled K_burn scaled to 1e4 (i.e. ×1.50 → 15_000). Floor = 10_000.
    function kBurnScaled(address user) external view returns (uint256 kScaled);
}