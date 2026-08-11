// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Math {
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            {
                uint256 mm = mulmod(x, y, type(uint256).max);
                prod0 = x * y;
                prod1 = mm - prod0;
                if (mm < prod0) {
                    prod1 -= 1;
                }
            }

            if (prod1 == 0) {
                require(denominator > 0, "Math: div0");
                return prod0 / denominator;
            }

            require(denominator > prod1, "Math: overflow");

            uint256 remainder;
            {
                remainder = mulmod(x, y, denominator);
                if (remainder > prod0) {
                    prod1 -= 1;
                }
                prod0 -= remainder;
            }

            uint256 twos = denominator & (0 - denominator);
            {
                denominator /= twos;
                prod0 /= twos;
                twos = ((0 - twos) / twos) + 1;
            }
            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            return result;
        }
    }
}