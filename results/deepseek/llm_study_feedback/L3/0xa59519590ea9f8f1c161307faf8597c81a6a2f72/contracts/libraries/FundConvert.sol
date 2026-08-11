// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Math {
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        if (denominator == 0) {
            revert("Math: division by zero");
        }
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 == 0) {
            return prod0 / denominator;
        }
        if (prod1 >= denominator) {
            revert("Math: overflow");
        }
        uint256 remainder;
        assembly {
            remainder := mulmod(x, y, denominator)
        }
        // Replace gt(remainder, prod0) with inline assembly comparison
        bool gtResult;
        assembly {
            gtResult := gt(remainder, prod0)
        }
        if (gtResult) {
            prod1 = prod1 - 1;
        }
        prod0 = prod0 - remainder;
        unchecked {
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            result = prod0 * inv;
        }
    }
}

library FundConvert {
    uint256 internal constant PRECISION = 1e18;

    function assetToShares(uint256 assetAmount, uint256 nav, uint8 assetDecimals, uint8 shareDecimals)
        internal
        pure
        returns (uint256 shareAmount)
    {
        uint256 assetScale = 10 ** uint256(assetDecimals);
        uint256 shareScale = 10 ** uint256(shareDecimals);
        shareAmount = Math.mulDiv(assetAmount * shareScale, PRECISION, nav * assetScale);
    }

    function sharesToAsset(uint256 shareAmount, uint256 nav, uint8 assetDecimals, uint8 shareDecimals)
        internal
        pure
        returns (uint256 assetAmount)
    {
        uint256 assetScale = 10 ** uint256(assetDecimals);
        uint256 shareScale = 10 ** uint256(shareDecimals);
        assetAmount = Math.mulDiv(shareAmount * nav, assetScale, shareScale * PRECISION);
    }
}