// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRouter} from "./interfaces/IRouter.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {Treasury} from "./Treasury.sol";
import {Errors} from "./libs/Errors.sol";

/// @notice Atomic swap router. Pulls input from user into the input vault,
///         pushes output from the output vault to the receiver, splits the
///         fee 80% to output-vault LPs (via RewardsDistributor) and 20% to
///         Treasury. Enforces coverage floor, max swap size, oracle freshness,
///         and depeg rules through FeeCalculator.
contract Router is IRouter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant LP_SHARE_BPS = 8_000;
    uint256 public constant TREASURY_SHARE_BPS = 2_000;
    uint256 public constant BPS_DENOM = 10_000;

    IAssetRegistry public immutable registry;
    IAccessController public immutable access;
    IFeeCalculator public immutable feeCalc;
    IRewardsDistributor public immutable rewards;
    Treasury public immutable treasury;

    constructor(
        address registry_,
        address access_,
        address feeCalc_,
        address rewards_,
        address payable treasury_
    ) {
        if (registry_ == address(0) || access_ == address(0) || feeCalc_ == address(0)
            || rewards_ == address(0) || treasury_ == address(0)) revert Errors.ZeroAddress();
        registry = IAssetRegistry(registry_);
        access = IAccessController(access_);
        feeCalc = IFeeCalculator(feeCalc_);
        rewards = IRewardsDistributor(rewards_);
        treasury = Treasury(treasury_);
    }

    /* ==================================================================
       QUOTE
    ================================================================== */

    function quoteExactInput(address assetIn, address assetOut, uint256 amountIn)
        external
        view
        returns (IFeeCalculator.FeeBreakdown memory)
    {
        return feeCalc.quote(assetIn, assetOut, amountIn);
    }

    struct SwapPreview {
        IFeeCalculator.FeeBreakdown quote;
        bool pairEnabled;
        bool globalPaused;
        bool inputSwapPaused;
        bool outputSwapPaused;
        bool pairManuallyPaused;
        bool exceedsMaxSize;
        bool coverageOk;
        uint256 coverageBpsAfter; // out-vault coverage * 10_000 after the swap
        uint256 minCoverageBps;   // configured floor for the output vault
        bool willRevert;          // composite: any of the above hard-fail conditions
    }

    /// @notice Full pre-flight check for a swap. Never reverts — every failure
    ///         reason is a boolean the frontend can render.
    function previewSwap(address assetIn, address assetOut, uint256 amountIn)
        external
        view
        returns (SwapPreview memory p)
    {
        // 1. Fee/route check (this DOES revert on stale oracle — that's actually
        //    informative, so callers should wrap in try/catch if they want pure
        //    soft-fail. Most frontends should just let it bubble.)
        p.quote = feeCalc.quote(assetIn, assetOut, amountIn);

        // 2. Pause + pair + size status
        p.globalPaused        = access.globalSwapsPaused();
        p.inputSwapPaused     = access.assetPaused(assetIn,  IAccessController.PauseScope.Swaps);
        p.outputSwapPaused    = access.assetPaused(assetOut, IAccessController.PauseScope.Swaps);
        p.pairManuallyPaused  = access.pairPaused(assetIn, assetOut);
        p.pairEnabled         = registry.isPairEnabled(assetIn, assetOut);

        IAssetRegistry.AssetConfig memory inCfg  = registry.getAsset(assetIn);
        IAssetRegistry.AssetConfig memory outCfg = registry.getAsset(assetOut);

        if (inCfg.maxSwapNotional != 0 && amountIn > inCfg.maxSwapNotional) p.exceedsMaxSize = true;

        // 3. Post-trade coverage on output vault
        IVault vOut = IVault(outCfg.vault);
        uint256 claims = vOut.totalLpClaims();
        if (claims == 0) {
            p.coverageOk = true;
            p.coverageBpsAfter = type(uint256).max; // infinite
        } else {
            uint256 balAfter = vOut.assetBalance() > p.quote.amountOut
                ? vOut.assetBalance() - p.quote.amountOut
                : 0;
            p.coverageBpsAfter = (balAfter * BPS_DENOM) / claims;
            p.coverageOk = p.coverageBpsAfter >= outCfg.minCoverageBps;
        }
        p.minCoverageBps = outCfg.minCoverageBps;

        p.willRevert =
            p.quote.routeDisabled ||
            p.globalPaused ||
            p.inputSwapPaused ||
            p.outputSwapPaused ||
            p.pairManuallyPaused ||
            !p.pairEnabled ||
            p.exceedsMaxSize ||
            !p.coverageOk;
    }

    /* ==================================================================
       SWAP
    ================================================================== */

    function swapExactInput(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external nonReentrant returns (uint256 amountOut, uint256 feeAmount) {
        if (assetIn == assetOut) revert Errors.SameAsset();
        if (amountIn == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (access.globalSwapsPaused()) revert Errors.GlobalPause();
        if (access.assetPaused(assetIn,  IAccessController.PauseScope.Swaps)) revert Errors.SwapsPaused();
        if (access.assetPaused(assetOut, IAccessController.PauseScope.Swaps)) revert Errors.SwapsPaused();
        if (access.pairPaused(assetIn, assetOut)) revert Errors.PairNotEnabled();
        if (!registry.isPairEnabled(assetIn, assetOut)) revert Errors.PairNotEnabled();

        IAssetRegistry.AssetConfig memory inCfg  = registry.getAsset(assetIn);
        IAssetRegistry.AssetConfig memory outCfg = registry.getAsset(assetOut);

        // Per-pair size cap (use input asset's cap as the input-denominated bound)
        if (inCfg.maxSwapNotional != 0 && amountIn > inCfg.maxSwapNotional) revert Errors.SwapSizeExceeded();

        // --- quote ---
        IFeeCalculator.FeeBreakdown memory q = feeCalc.quote(assetIn, assetOut, amountIn);
        if (q.routeDisabled) revert Errors.DepegRouteDisabled();
        if (q.amountOut < minAmountOut) revert Errors.InsufficientOutput();

        // --- coverage floor (post-trade) on the OUTPUT vault ---
        IVault vIn  = IVault(inCfg.vault);
        IVault vOut = IVault(outCfg.vault);

        // Pull input from user (gross) into router temporarily so we can split.
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 lpFee       = (q.feeAmount * LP_SHARE_BPS) / BPS_DENOM;
        uint256 treasuryFee = q.feeAmount - lpFee;

        // Net input goes into vault A (as protocol inventory — no shares minted)
        IERC20(assetIn).safeTransfer(address(vIn), q.netIn);

        // Treasury portion of input asset goes to treasury
        if (treasuryFee > 0) {
            IERC20(assetIn).approve(address(treasury), treasuryFee);
            treasury.receiveProtocolFee(assetIn, treasuryFee, address(this));
        }

        // LP fee portion: park in RewardsDistributor (so it can pay claims)
        // and accrue the index for output-vault LPs.
        uint256 outSupply = vOut.totalSharesX18();
        if (lpFee > 0) {
            if (outSupply == 0) {
                // No LPs to receive — forward to treasury too
                IERC20(assetIn).approve(address(treasury), lpFee);
                treasury.receiveProtocolFee(assetIn, lpFee, address(this));
            } else {
                IERC20(assetIn).safeTransfer(address(rewards), lpFee);
                rewards.accrueReward(address(vOut), assetIn, lpFee);
            }
        }

        // Pull output from vault B to receiver
        vOut.pullTo(receiver, q.amountOut);

        // --- coverage floor on the OUTPUT vault, post-trade ---
        uint256 outBal = vOut.assetBalance();
        uint256 claims = vOut.totalLpClaims();
        if (claims > 0) {
            // outBal * 10_000 >= claims * minCoverageBps
            if (outBal * BPS_DENOM < claims * outCfg.minCoverageBps) revert Errors.CoverageBelowFloor();
        }

        emit Swap(assetIn, assetOut, msg.sender, receiver, amountIn, q.amountOut, q.feeAmount);
        return (q.amountOut, q.feeAmount);
    }
}
