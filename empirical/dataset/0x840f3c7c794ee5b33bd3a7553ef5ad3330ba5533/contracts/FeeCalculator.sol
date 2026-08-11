// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {Errors} from "./libs/Errors.sol";

/// @notice Stablehouse fee engine.
///
/// All fee bps in this contract are SCALED by FEE_BPS_SCALE (10_000), so
/// the natural unit `1 bp` is represented by the integer `10_000`. This
/// lets us express fractional bps (e.g. 0.2 bp = 2_000) without losing
/// precision while staying inside uint256.
///
/// The final fee amount on an input `amountIn` (in native token decimals) is
///   feeAmount = amountIn * scaledBps / (10_000 * 10_000) = amountIn * scaledBps / 1e8.
contract FeeCalculator is IFeeCalculator {
    uint256 public constant override FEE_BPS_SCALE = 10_000;          // 1 bp == 10_000 scaled
    uint256 public constant BPS_DENOM            = 10_000;            // bps / 10_000 = fraction
    uint256 public constant ONE_WAD              = 1e18;
    uint256 public constant HALF_WAD             = 5e17;
    uint256 public constant HARD_BLOCK_WAD       = 5e16; // outShare < 0.05 -> hard block

    IAssetRegistry public immutable registry;
    IAccessController public immutable access;

    // V1 defaults: 0.2 bp / 1.0 bp / 20 bp (scaled)
    uint256 public minFeeScaled  = 2_000;
    uint256 public baseFeeScaled = 10_000;
    uint256 public scaleFeeScaled = 200_000;

    // Pairwise depeg disable threshold in (whole) bps
    uint16 public pairwiseDepegDisableBps = 50;
    uint16 public depegSurchargeStartBps   = 5;
    uint16 public depegMidThresholdBps     = 20;

    event FeeParamsUpdated(uint256 minFeeScaled, uint256 baseFeeScaled, uint256 scaleFeeScaled);
    event DepegParamsUpdated(uint16 pairwise, uint16 start, uint16 mid);

    modifier onlyParam() {
        if (!access.hasRole(access.PARAM_MANAGER_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    constructor(address registry_, address access_) {
        if (registry_ == address(0) || access_ == address(0)) revert Errors.ZeroAddress();
        registry = IAssetRegistry(registry_);
        access = IAccessController(access_);
    }

    function setInventoryParams(uint256 minF, uint256 baseF, uint256 scaleF) external onlyParam {
        if (minF > baseF) revert Errors.InvalidParam();
        minFeeScaled = minF;
        baseFeeScaled = baseF;
        scaleFeeScaled = scaleF;
        emit FeeParamsUpdated(minF, baseF, scaleF);
    }

    function setDepegParams(uint16 pairwise, uint16 start, uint16 mid) external onlyParam {
        if (start > mid || mid > pairwise || pairwise > 10_000) revert Errors.InvalidParam();
        pairwiseDepegDisableBps = pairwise;
        depegSurchargeStartBps = start;
        depegMidThresholdBps = mid;
        emit DepegParamsUpdated(pairwise, start, mid);
    }

    /* ==================================================================
       QUOTE
    ================================================================== */

    function quote(address assetIn, address assetOut, uint256 amountIn)
        external
        view
        returns (FeeBreakdown memory r)
    {
        IAssetRegistry.AssetConfig memory inCfg  = registry.getAsset(assetIn);
        IAssetRegistry.AssetConfig memory outCfg = registry.getAsset(assetOut);

        // --- oracle prices (revert on stale) ---
        uint256 pIn  = _getPriceWad(inCfg);
        uint256 pOut = _getPriceWad(outCfg);

        // --- per-asset depeg check: input cannot be used if too weak ---
        uint256 inDeviation = _absDeviationBps(pIn);
        if (pIn < ONE_WAD && inDeviation > inCfg.depegDisableBps) {
            r.routeDisabled = true;
            return r;
        }

        // --- depeg fee (only when input weaker than output) ---
        uint256 depegFeeScaled;
        if (pIn < pOut) {
            uint256 gapBps = ((pOut - pIn) * BPS_DENOM) / pOut;
            if (gapBps > pairwiseDepegDisableBps) {
                r.routeDisabled = true;
                return r;
            }
            if (gapBps > depegSurchargeStartBps) {
                uint256 surchargeBps = gapBps <= depegMidThresholdBps ? (gapBps + 2) : (gapBps + 5);
                depegFeeScaled = surchargeBps * FEE_BPS_SCALE;
            }
        }

        // --- post-trade vault balances (assume no oracle adjustment of par value) ---
        IVault vIn  = IVault(inCfg.vault);
        IVault vOut = IVault(outCfg.vault);

        // Use a temporary fee estimate to compute inventory state.
        // For the inventory signal we don't need the exact fee: net-in into vault A,
        // exact-amount-out from vault B. We iterate the inventory fee fixed-point in
        // closed form because outShare depends on fee which depends on outShare. To
        // keep math tractable we approximate using the gross amounts which is what
        // the PRD worked examples use as well.
        uint256 balInAfter  = vIn.assetBalance() + amountIn; // gross-in approximation
        // amountOut estimate: net of fee at base; for inventory signal this is fine.
        // We compute output later using the final feeBps.
        // For outShare we need balOutAfter = balOut - amountOut. Use amountIn-decimal-adjusted as approximation.
        uint256 amountOutGross = _convertDecimals(amountIn, inCfg.decimals, outCfg.decimals);
        uint256 balOutBefore = vOut.assetBalance();
        uint256 balOutAfter  = balOutBefore > amountOutGross ? (balOutBefore - amountOutGross) : 0;

        uint256 inventoryFeeScaled = _inventoryFee(balInAfter, inCfg.decimals, balOutAfter, outCfg.decimals);
        if (inventoryFeeScaled == type(uint256).max) {
            r.routeDisabled = true;
            return r;
        }

        uint256 totalScaled = inventoryFeeScaled + depegFeeScaled;

        // fee amount in input-token native decimals
        uint256 feeAmt = (amountIn * totalScaled) / (FEE_BPS_SCALE * BPS_DENOM);
        uint256 netIn = amountIn - feeAmt;
        uint256 amountOut = _convertDecimals(netIn, inCfg.decimals, outCfg.decimals);

        r.inventoryFeeBps = inventoryFeeScaled;
        r.depegFeeBps     = depegFeeScaled;
        r.totalFeeBps     = totalScaled;
        r.feeAmount       = feeAmt;
        r.netIn           = netIn;
        r.amountOut       = amountOut;
        r.routeDisabled   = false;
    }

    /* ==================================================================
       INTERNAL MATH
    ================================================================== */

    /// @notice Inventory fee in scaled bps. Returns type(uint256).max if the
    ///         hard-block threshold is hit (outShare < 5%).
    function _inventoryFee(
        uint256 balIn,
        uint8 decIn,
        uint256 balOut,
        uint8 decOut
    ) internal view returns (uint256) {
        // normalize both balances to WAD using their decimals
        uint256 balInWad  = (balIn  * ONE_WAD) / (10 ** decIn);
        uint256 balOutWad = (balOut * ONE_WAD) / (10 ** decOut);
        uint256 sum = balInWad + balOutWad;
        if (sum == 0) return baseFeeScaled;

        uint256 outShareWad = (balOutWad * ONE_WAD) / sum;
        if (outShareWad < HARD_BLOCK_WAD) return type(uint256).max;

        if (outShareWad >= HALF_WAD) {
            // rebalancing: fee drops linearly toward minFee
            // factor = (1 - outShare) / 0.5  in [0, 1]
            uint256 diff = ONE_WAD - outShareWad;                // [0, 5e17]
            uint256 normalized = (diff * ONE_WAD) / HALF_WAD;    // [0, 1e18]
            uint256 spread = baseFeeScaled - minFeeScaled;
            return minFeeScaled + (spread * normalized) / ONE_WAD;
        } else {
            // imbalancing: fee rises quadratically from baseFee
            uint256 diff = HALF_WAD - outShareWad;               // [0, 5e17]
            uint256 normalized = (diff * ONE_WAD) / HALF_WAD;    // [0, 1e18]
            uint256 squared = (normalized * normalized) / ONE_WAD; // [0, 1e18]
            return baseFeeScaled + (scaleFeeScaled * squared) / ONE_WAD;
        }
    }

    function _convertDecimals(uint256 amount, uint8 decIn, uint8 decOut) internal pure returns (uint256) {
        if (decIn == decOut) return amount;
        if (decOut > decIn) return amount * (10 ** (decOut - decIn));
        return amount / (10 ** (decIn - decOut));
    }

    function _absDeviationBps(uint256 priceWad) internal pure returns (uint256) {
        uint256 diff = priceWad >= ONE_WAD ? (priceWad - ONE_WAD) : (ONE_WAD - priceWad);
        return (diff * BPS_DENOM) / ONE_WAD;
    }

    function _getPriceWad(IAssetRegistry.AssetConfig memory cfg) internal view returns (uint256) {
        IAggregatorV3 oracle = IAggregatorV3(cfg.oracle);
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        if (answer <= 0) revert Errors.InvalidOraclePrice();
        if (updatedAt == 0) revert Errors.StaleOracle();                       // round not complete
        if (answeredInRound < roundId) revert Errors.StaleOracle();            // answer from older round
        if (block.timestamp > updatedAt + cfg.oracleHeartbeat) revert Errors.StaleOracle();
        // Sanity ceiling: a stablecoin price reporting > $10 is almost certainly broken.
        // Reject before we apply it to fee math.
        uint8 d = oracle.decimals();
        uint256 priceWad;
        if (d == 18) priceWad = uint256(answer);
        else if (d < 18) priceWad = uint256(answer) * (10 ** (18 - d));
        else priceWad = uint256(answer) / (10 ** (d - 18));
        if (priceWad > 10e18) revert Errors.InvalidOraclePrice();
        return priceWad;
    }
}
