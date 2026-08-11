// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

/// @title Helper
/// @author Sivo
library Helper {
    error ExpInputOverflow();

    uint64 internal constant SecondsPerYear = 31_536_000; // 365 * 24 * 60 * 60
    uint64 internal constant FactorScale = 1e18;

    /// @dev Maximum input for exp() in UD60x18. Beyond this, e^x overflows uint256.
    uint256 private constant _EXP_MAX_INPUT = 133_084258667509499440;

    /// @notice Computes e^x for x in 18-decimal fixed-point (UD60x18) format.
    /// @dev Uses a (6,7)-term rational approximation after range reduction.
    function exp(uint256 x) internal pure returns (uint256 r) {
        if (x == 0) return 1e18;
        if (x > _EXP_MAX_INPUT) revert ExpInputOverflow();
        unchecked {
            // Convert x from 1e18 basis to 2^96 basis: x * 2^96 / 1e18 = x * 2^78 / 5^18.
            int256 x96 = int256((x << 78) / (5 ** 18));
            // Reduce range: k = round(x96 / ln(2)), x96' = x96 - k * ln(2).
            // ln(2) in 2^96 basis = 54916777467707473351141471128
            int256 k = ((x96 << 96) /
                54916777467707473351141471128 +
                int256(2 ** 95)) >> 96;
            x96 = x96 - k * 54916777467707473351141471128;
            // Evaluate using a (6, 7)-term rational approximation.
            int256 y = x96 + 1346386616545796478920950773328;
            y = ((y * x96) >> 96) + 57155421227552351082224309758442;
            int256 p = y + x96 - 94201549194550492254356042504812;
            p = ((p * y) >> 96) + 28719021644029726153956944680412240;
            p = p * x96 + (4385272521454847904659076985693276 << 96);
            int256 q = x96 - 2855989394907223263936484059900;
            q = ((q * x96) >> 96) + 50020603652535783019961831881945;
            q = ((q * x96) >> 96) - 533845033583426703283633433725380;
            q = ((q * x96) >> 96) + 3604857256930695427073651918091429;
            q = ((q * x96) >> 96) - 14423608567350463180887372962807573;
            q = ((q * x96) >> 96) + 26449188498355588339934803723976023;
            // Signed division in assembly (avoids zero-check overhead).
            int256 rInt;
            assembly {
                rInt := sdiv(p, q)
            }
            // Scale by 2^k and convert from 2^96 to 1e18 basis.
            r =
                (uint256(rInt) *
                    3822833074963236453042738258902158003155416615667) >>
                uint256(195 - k);
        }
    }
}
