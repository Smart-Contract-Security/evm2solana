// SPDX-License-Identifier: MIT

import 'solana';

/// @notice Surface RushClaim uses to read a wallet's burn-K multiplier.
interface IRushBurn {
    /// @return kScaled K_burn scaled to 1e4 (i.e. ×1.50 → 15_000). Floor = 10_000.
    function kBurnScaled(address user) external view returns (uint64 kScaled);
}