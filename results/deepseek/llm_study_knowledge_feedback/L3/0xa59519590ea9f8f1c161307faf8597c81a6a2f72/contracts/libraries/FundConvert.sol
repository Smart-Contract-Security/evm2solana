// SPDX-License-Identifier: MIT

library Math {
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        if (denominator == 0) {
            return 0;
        }
        result = (x * y) / denominator;
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