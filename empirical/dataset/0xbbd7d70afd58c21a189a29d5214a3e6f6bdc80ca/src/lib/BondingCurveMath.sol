// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title BondingCurveMath
 * @notice Pure calculation library for a bounded square-root bonding curve.
 *
 * This library does NOT manage ERC20 transfers, balances, permissions, minting, burning,
 * treasury custody, pause logic, or sale lifecycle. It only calculates prices and quotes.
 *
 * Recommended external usage:
 * - A sale / market contract keeps `sold` or `circulatingShares` state.
 * - On buy: quote cost from [sold, sold + shares], then mint / transfer shares.
 * - On sell: quote proceeds from [sold - shares, sold], then burn / transfer shares back.
 *
 * Curve:
 *   P(S) = Pmin + (Pmax - Pmin)
 *        * (sqrt(S/T + lambda) - sqrt(lambda))
 *        / (sqrt(1 + lambda) - sqrt(lambda))
 *
 * Settlement:
 * - Buy exact shares uses interval integral from S to S + q.
 * - Sell exact shares uses interval integral from S - q to S.
 * - Spot price is only for display; production settlement should use interval price.
 *
 * Units:
 * - WAD = 1e18.
 * - totalShares and sold/shares use 18-decimal share units, e.g. 10_000_000 ether.
 * - priceMinWad / priceMaxWad are payment-token whole-unit prices per 1 whole share,
 *   scaled by 1e18. Example: 1e18 means 1 payment token per 1 share.
 * - lambdaWad is scaled by 1e18. Example: 0.02e18 = 2e16.
 * - paymentUnit should be 10 ** paymentTokenDecimals when raw token amounts are required.
 */
library BondingCurveMath {
    uint256 internal constant WAD = 1e18;

    struct CurveParams {
        uint256 totalShares;
        uint256 priceMinWad;
        uint256 priceMaxWad;
        uint256 lambdaWad;
        uint256 paymentUnit;
    }

    error InvalidCurveParams();
    error SoldExceedsTotal();
    error SoldOut();
    error InsufficientSoldShares();
    error ZeroAmount();

    // -------------------------------------------------------------------------
    // Public validation
    // -------------------------------------------------------------------------

    function validate(CurveParams memory p) internal pure {
        if (p.totalShares == 0) revert InvalidCurveParams();
        if (p.priceMinWad == 0 || p.priceMaxWad <= p.priceMinWad) revert InvalidCurveParams();
        if (p.lambdaWad == 0 || p.lambdaWad > WAD) revert InvalidCurveParams();
        if (p.paymentUnit == 0 || p.paymentUnit > WAD) revert InvalidCurveParams();
    }

    // -------------------------------------------------------------------------
    // Display price
    // -------------------------------------------------------------------------

    function priceAtWad(CurveParams memory p, uint256 sold) internal pure returns (uint256) {
        validate(p);
        if (sold > p.totalShares) revert SoldExceedsTotal();
        return _priceAtWadUnchecked(p, sold);
    }

    function buyAveragePriceWad(CurveParams memory p, uint256 soldBefore, uint256 sharesToBuy)
        internal
        pure
        returns (uint256)
    {
        if (sharesToBuy == 0) revert ZeroAmount();
        uint256 costWad = quoteBuyExactSharesWad(p, soldBefore, sharesToBuy);
        return Math.mulDiv(costWad, WAD, sharesToBuy);
    }

    function sellAveragePriceWad(CurveParams memory p, uint256 soldBefore, uint256 sharesToSell)
        internal
        pure
        returns (uint256)
    {
        if (sharesToSell == 0) revert ZeroAmount();
        uint256 proceedsWad = quoteSellExactSharesWad(p, soldBefore, sharesToSell);
        return Math.mulDiv(proceedsWad, WAD, sharesToSell);
    }

    // -------------------------------------------------------------------------
    // Buy quote
    // -------------------------------------------------------------------------

    /**
     * @notice Quote payment amount in WAD units for buying exact shares.
     * @dev Interval: [soldBefore, soldBefore + sharesToBuy].
     */
    function quoteBuyExactSharesWad(CurveParams memory p, uint256 soldBefore, uint256 sharesToBuy)
        internal
        pure
        returns (uint256 paymentWad)
    {
        validate(p);
        if (sharesToBuy == 0) revert ZeroAmount();
        if (soldBefore > p.totalShares) revert SoldExceedsTotal();
        if (soldBefore + sharesToBuy > p.totalShares) revert SoldOut();

        return _quoteIntervalWadUnchecked(p, soldBefore, soldBefore + sharesToBuy);
    }

    /**
     * @notice Quote raw payment-token amount for buying exact shares.
     * @dev Rounded up so the protocol never undercharges buyers.
     */
    function quoteBuyExactSharesRaw(CurveParams memory p, uint256 soldBefore, uint256 sharesToBuy)
        internal
        pure
        returns (uint256 rawPaymentAmount)
    {
        uint256 paymentWad = quoteBuyExactSharesWad(p, soldBefore, sharesToBuy);
        return _wadToRawUp(paymentWad, p.paymentUnit);
    }

    /**
     * @notice Quote max shares buyable with a raw payment amount.
     * @dev Uses binary search because the integral is monotonic but not conveniently invertible.
     */
    function quoteBuySharesForRawPayment(CurveParams memory p, uint256 soldBefore, uint256 rawPaymentAmount)
        internal
        pure
        returns (uint256 sharesOut, uint256 rawCost)
    {
        validate(p);
        if (rawPaymentAmount == 0) revert ZeroAmount();
        if (soldBefore > p.totalShares) revert SoldExceedsTotal();
        if (soldBefore == p.totalShares) revert SoldOut();

        uint256 remaining = p.totalShares - soldBefore;
        uint256 low = 0;
        uint256 high = remaining;

        for (uint256 i = 0; i < 96; i++) {
            uint256 mid = (low + high + 1) >> 1;
            uint256 cost = quoteBuyExactSharesRaw(p, soldBefore, mid);
            if (cost <= rawPaymentAmount) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        sharesOut = low;
        if (sharesOut == 0) return (0, 0);
        rawCost = quoteBuyExactSharesRaw(p, soldBefore, sharesOut);
    }

    // -------------------------------------------------------------------------
    // Sell quote
    // -------------------------------------------------------------------------

    /**
     * @notice Quote proceeds in WAD units for selling exact shares back into the curve.
     * @dev Interval: [soldBefore - sharesToSell, soldBefore].
     */
    function quoteSellExactSharesWad(CurveParams memory p, uint256 soldBefore, uint256 sharesToSell)
        internal
        pure
        returns (uint256 proceedsWad)
    {
        validate(p);
        if (sharesToSell == 0) revert ZeroAmount();
        if (soldBefore > p.totalShares) revert SoldExceedsTotal();
        if (sharesToSell > soldBefore) revert InsufficientSoldShares();

        return _quoteIntervalWadUnchecked(p, soldBefore - sharesToSell, soldBefore);
    }

    /**
     * @notice Quote raw payment-token proceeds for selling exact shares.
     * @dev Rounded down so the protocol never overpays sellers.
     */
    function quoteSellExactSharesRaw(CurveParams memory p, uint256 soldBefore, uint256 sharesToSell)
        internal
        pure
        returns (uint256 rawProceeds)
    {
        uint256 proceedsWad = quoteSellExactSharesWad(p, soldBefore, sharesToSell);
        return _wadToRawDown(proceedsWad, p.paymentUnit);
    }

    /**
     * @notice Quote shares required to sell for at least a target raw proceeds amount.
     * @dev Returns the minimum shares that produce targetRawProceeds or more, when possible.
     */
    function quoteSellSharesForTargetRawProceeds(CurveParams memory p, uint256 soldBefore, uint256 targetRawProceeds)
        internal
        pure
        returns (uint256 sharesToSell, uint256 rawProceeds)
    {
        validate(p);
        if (targetRawProceeds == 0) revert ZeroAmount();
        if (soldBefore > p.totalShares) revert SoldExceedsTotal();
        if (soldBefore == 0) revert InsufficientSoldShares();

        uint256 maxProceeds = quoteSellExactSharesRaw(p, soldBefore, soldBefore);
        if (targetRawProceeds > maxProceeds) revert InsufficientSoldShares();

        uint256 low = 1;
        uint256 high = soldBefore;

        for (uint256 i = 0; i < 96; i++) {
            uint256 mid = (low + high) >> 1;
            uint256 proceeds = quoteSellExactSharesRaw(p, soldBefore, mid);
            if (proceeds >= targetRawProceeds) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        sharesToSell = low;
        rawProceeds = quoteSellExactSharesRaw(p, soldBefore, sharesToSell);
    }

    // -------------------------------------------------------------------------
    // Internal curve math
    // -------------------------------------------------------------------------

    function _priceAtWadUnchecked(CurveParams memory p, uint256 sold) private pure returns (uint256) {
        if (sold == 0) return p.priceMinWad;
        if (sold == p.totalShares) return p.priceMaxWad;

        uint256 xWad = Math.mulDiv(sold, WAD, p.totalShares);
        uint256 sqrtLambdaWad = _sqrtWad(p.lambdaWad);
        uint256 denominatorWad = _sqrtWad(WAD + p.lambdaWad) - sqrtLambdaWad;
        uint256 numeratorWad = _sqrtWad(xWad + p.lambdaWad) - sqrtLambdaWad;
        uint256 ratioWad = Math.mulDiv(numeratorWad, WAD, denominatorWad);

        return p.priceMinWad + Math.mulDiv(p.priceMaxWad - p.priceMinWad, ratioWad, WAD);
    }

    /**
     * @dev Quote integral payment over [soldFrom, soldTo].
     */
    function _quoteIntervalWadUnchecked(CurveParams memory p, uint256 soldFrom, uint256 soldTo)
        private
        pure
        returns (uint256 paymentWad)
    {
        if (soldTo <= soldFrom) return 0;

        uint256 shares = soldTo - soldFrom;
        uint256 x0Wad = Math.mulDiv(soldFrom, WAD, p.totalShares);
        uint256 x1Wad = Math.mulDiv(soldTo, WAD, p.totalShares);

        uint256 basePaymentWad = Math.mulDiv(p.priceMinWad, shares, WAD);

        uint256 sqrtLambdaWad = _sqrtWad(p.lambdaWad);
        uint256 denominatorWad = _sqrtWad(WAD + p.lambdaWad) - sqrtLambdaWad;
        uint256 integralWad = _curveIntegralWad(p.lambdaWad, sqrtLambdaWad, x0Wad, x1Wad);

        uint256 ratioWad = Math.mulDiv(integralWad, WAD, denominatorWad);
        uint256 rangePaymentForFullSaleWad = Math.mulDiv(p.priceMaxWad - p.priceMinWad, p.totalShares, WAD);
        uint256 curvePaymentWad = Math.mulDiv(rangePaymentForFullSaleWad, ratioWad, WAD);

        return basePaymentWad + curvePaymentWad;
    }

    /**
     * @dev Integral of sqrt(x + lambda) - sqrt(lambda), from x0 to x1, scaled by WAD.
     *
     * Formula:
     *   integral = 2/3 * [(x1 + lambda)^(3/2) - (x0 + lambda)^(3/2)]
     *            - sqrt(lambda) * (x1 - x0)
     */
    function _curveIntegralWad(uint256 lambdaWad, uint256 sqrtLambdaWad, uint256 x0Wad, uint256 x1Wad)
        private
        pure
        returns (uint256)
    {
        if (x1Wad <= x0Wad) return 0;

        uint256 pow0Wad = _powThreeHalvesWad(x0Wad + lambdaWad);
        uint256 pow1Wad = _powThreeHalvesWad(x1Wad + lambdaWad);

        uint256 firstWad = Math.mulDiv(pow1Wad - pow0Wad, 2, 3);
        uint256 secondWad = Math.mulDiv(sqrtLambdaWad, x1Wad - x0Wad, WAD);

        if (firstWad <= secondWad) return 0;
        return firstWad - secondWad;
    }

    function _powThreeHalvesWad(uint256 xWad) private pure returns (uint256) {
        return Math.mulDiv(xWad, _sqrtWad(xWad), WAD);
    }

    function _sqrtWad(uint256 xWad) private pure returns (uint256) {
        return Math.sqrt(xWad * WAD);
    }

    function _wadToRawUp(uint256 amountWad, uint256 paymentUnit) private pure returns (uint256) {
        return _mulDivUp(amountWad, paymentUnit, WAD);
    }

    function _wadToRawDown(uint256 amountWad, uint256 paymentUnit) private pure returns (uint256) {
        return Math.mulDiv(amountWad, paymentUnit, WAD);
    }

    function _mulDivUp(uint256 x, uint256 y, uint256 denominator) private pure returns (uint256 result) {
        result = Math.mulDiv(x, y, denominator);
        if (mulmod(x, y, denominator) > 0) {
            unchecked {
                result += 1;
            }
        }
    }
}
