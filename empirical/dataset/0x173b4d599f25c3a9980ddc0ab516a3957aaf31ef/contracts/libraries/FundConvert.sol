// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Decimal + NAV conversion (Cobo `CoboFundToken` / oracle 1e18 NAV)
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
