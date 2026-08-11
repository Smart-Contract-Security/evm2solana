// SPDX-License-Identifier: BUSL-1.1

/// @title AllocationLib
/// @notice Shared token-allocation math used by LaunchFactory and PresaleManager. Liquidity always
///         equals presale; LP incentive is 20% of the remainder; issuer vesting is the rest.
library AllocationLib {
    uint64 internal constant BPS_DENOMINATOR = 10_000;
    uint64 internal constant LP_INCENTIVE_PERCENT = 20;

    function compute(
        uint64 totalSupply,
        uint64 presalePercent
    )
        internal
        pure
        returns (uint64 presaleTokens, uint64 liquidityTokens, uint64 lpIncentiveTokens, uint64 issuerVestingTokens)
    {
        presaleTokens = totalSupply * presalePercent / BPS_DENOMINATOR;
        liquidityTokens = presaleTokens;
        uint64 vestingTotal = totalSupply - presaleTokens - liquidityTokens;
        lpIncentiveTokens = vestingTotal * LP_INCENTIVE_PERCENT / 100;
        issuerVestingTokens = vestingTotal - lpIncentiveTokens;
    }

    /// @dev Last entry receives the remainder so BPS rounding never loses dust.
    function splitByBps(
        uint64 total,
        uint64[] memory bps
    ) internal pure returns (uint64[] memory amounts) {
        uint64 len = uint64(bps.length);
        amounts = new uint64[](len);
        if (len == 0) return amounts;
        uint64 distributed;
        for (uint64 i = 0; i < len - 1;) {
            amounts[i] = total * bps[i] / BPS_DENOMINATOR;
            distributed += amounts[i];
            unchecked {
                ++i;
            }
        }
        amounts[len - 1] = total - distributed;
    }
}