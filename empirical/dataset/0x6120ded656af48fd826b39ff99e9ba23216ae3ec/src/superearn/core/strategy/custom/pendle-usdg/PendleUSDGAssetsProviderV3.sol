// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IExternalAssetsProvider } from "@superearn/v2/interfaces/IExternalAssetsProvider.sol";
import { IPendleOracle } from "@superearn/interface/IPendle.sol";
import { IMorphoBlue } from "@superearn/interface/IMorphoBlue.sol";

/**
 * @title PendleUSDGAssetsProviderV3
 * @notice Assets provider for CustomStrategy holding PT-USDG positions
 *         + Morpho Blue PT-USDG/USDC collateral/borrow leverage loop.
 *
 *         V3 adds ROLLOVER SUPPORT over V2: the Pendle config (PT / Pendle market / SY)
 *         and the Morpho market id are now mutable storage updatable by the strategy's
 *         governance via setPendleConfig() / setMorphoMarket(). Both setters require
 *         totalAssets to remain within INVARIANCE_TOLERANCE_BPS — a generalized check
 *         that implicitly enforces empty old positions (PT balance, SY balance, Morpho
 *         collateral and Morpho debt all zero) before a config change takes effect.
 *
 *         Pricing logic is unchanged from V2 (USDG ≈ USDC, both 6-decimal USD-pegged).
 *
 * @dev Calculates total assets as a USDC-denominated NET sum of:
 *      ASSETS:
 *      - Idle USDC balance (includes any borrowed USDC, even if forwarded to
 *        another strategy via the parent stack — the borrowed USDC sits in
 *        STRATEGY until it is moved out)
 *      - Idle USDG balance               (1:1 to USDC; both USD-pegged 6 decimals)
 *      - SY-USDG balance                 (1:1 to USDG → 1:1 to USDC)
 *      - PT-USDG balance                 × PendleOracle TWAP rate → USDG → USDC
 *      - Morpho collateral (PT-USDG)     × PendleOracle TWAP rate → USDG → USDC
 *      LIABILITIES (subtracted):
 *      - Morpho borrow debt (USDC, rounded up using Morpho Blue's
 *        share-to-asset formula)
 *
 *      Asset Chain:
 *        USDC ── Curve(USDG/USDC) ──> USDG ── Pendle ──> PT-USDG
 *                                              └─> Morpho.supplyCollateral
 *                                                   └─> Morpho.borrow USDC ──> [used by other strategy / loop]
 *
 *      Simplification: USDG ≈ USDC (both USD-pegged stablecoins, 6 decimals).
 *      For production with stricter pricing, integrate Curve get_dy or a
 *      Chainlink oracle for USDG/USDC.
 *
 *      Morpho borrow debt uses conservative (rounded up) calculation:
 *        borrowAssets = ceil(borrowShares * (totalBorrowAssets + 1) / (totalBorrowShares + 1e6))
 *
 *      Leverage rationale: USDC borrowed against PT-USDG collateral can be
 *      withdrawn from the strategy and redeployed into another strategy,
 *      effectively producing leverage on the PT-USDG yield while paying the
 *      Morpho borrow rate. The borrowed USDC that has been moved out of the
 *      strategy is NOT tracked here — it must be accounted for at the parent
 *      vault layer. The Morpho borrow debt remains tracked because the debt
 *      stays attached to STRATEGY's Morpho position regardless of where the
 *      borrowed USDC currently lives.
 *
 * ============================================================================
 * CustomStrategy Configuration Reference — PT-USDG via Pendle + Morpho Blue
 * ============================================================================
 *
 * The CustomStrategy paired with this provider was configured by:
 *
 *   1) Initial deployment + EIP-7702 batch (V1 base config — Pendle/Curve/USDG/USDC/YT/PT):
 *        script/upgrade-2026.04/ethereum/DeployPendleUSDGStrategy.s.sol
 *        script/upgrade-2026.04/ethereum/eip7702-batch-configure.sh
 *
 *   2) Safe multisig batch — added Morpho Blue support and swapped externalAssetsProvider
 *      from V1 to V2:
 *        script/upgrade-2026.04/ethereum/pendle-usdg-v2/DeployPendleUSDGProviderV2.s.sol
 *        script/upgrade-2026.04/ethereum/pendle-usdg-v2/safe-tx/governance-pendle-usdg-v2-batch.json
 *           - PT-USDG.setExternalAssetsProvider(PendleUSDGAssetsProviderV2)
 *           - PT-USDG.setAllowedTarget(MorphoBlue, true)
 *           - PT-USDG.setAllowedSelector(MorphoBlue, supplyCollateral, true)
 *           - PT-USDG.setAllowedSelector(MorphoBlue, withdrawCollateral, true)
 *           - PT-USDG.setAllowedSelector(MorphoBlue, borrow, true)
 *           - PT-USDG.setAllowedSelector(MorphoBlue, repay, true)
 *
 *   3) V3 swaps externalAssetsProvider from V2 to V3 (this contract) to enable rollover.
 *      No change to AllowedTargets/Selectors/ParamChecks is required — V3 only changes the
 *      off-chain valuation contract, not the strategy's execution permissions.
 *
 * Contract Addresses (Ethereum Mainnet):
 *   PENDLE_ROUTER       = 0x888888888889758F76e7103c6CbF23ABbF58F946
 *   PENDLE_ORACLE       = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2
 *   MARKET (PT-USDG-28MAY2026) = 0xC5b32dba5f29F8395fb9591E1a15f23A75214F33
 *   SY_USDG             = 0xc1799CaB1F201946f7CFaFBaF1BCC089b2F08927
 *   PT_USDG             = 0x9db38D74a0D29380899aD354121DfB521aDb0548
 *   YT_USDG             = 0x4a1294749A70bc32A998B49dd11Bf26E9379e3C1
 *   USDG                = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D  (6 decimals)
 *   USDC                = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  (6 decimals)
 *   CURVE_USDG_USDC     = 0xc061caa073f3d95F80f8e5428d32D2d76F5e1622  (coins[0]=USDG, coins[1]=USDC)
 *   MORPHO_BLUE         = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
 *   MORPHO_PT_USDG_MARKET_ID = <set per deployment — PT-USDG (collateral) / USDC (loan)>
 *
 *      (See PendleUSDGAssetsProviderV2 for the full AllowedTargets / AllowedSelectors /
 *       ParamChecks / Operation-Flows reference — V3 reuses the same strategy config.)
 *
 * ============================================================================
 */
contract PendleUSDGAssetsProviderV3 is IExternalAssetsProvider {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @dev Morpho Blue virtual shares/assets for share math
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    // ============================================
    // IMMUTABLE STORAGE
    // ============================================

    address public immutable STRATEGY;
    address public immutable USDC;
    address public immutable USDG;
    address public immutable ORACLE;
    address public immutable MORPHO;
    uint32 public immutable TWAP_DURATION;
    /// @notice Max allowed deviation of totalAssets across a config update (basis points)
    uint256 public immutable INVARIANCE_TOLERANCE_BPS;

    // ============================================
    // MUTABLE STORAGE (rollover support)
    // ============================================

    /// @notice SY-USDG token (updatable on rollover)
    address public sy;
    /// @notice PT-USDG token (updatable on rollover)
    address public pt;
    /// @notice Pendle market used for oracle TWAP (updatable on rollover)
    address public pendleMarket;
    /// @notice Morpho Blue market id (PT-USDG collateral / USDC loan; updatable on rollover)
    bytes32 public morphoMarketId;

    // ============================================
    // EVENTS
    // ============================================

    event PendleConfigUpdated(
        address oldPt, address newPt, address oldMarket, address newMarket, address oldSy, address newSy
    );
    event MorphoMarketUpdated(bytes32 oldMarketId, bytes32 newMarketId);

    // ============================================
    // ERRORS
    // ============================================

    error ZeroAddress();
    error InvalidMorphoMarket();
    error TotalAssetsChanged(uint256 beforeTotal, uint256 afterTotal);
    error NotStrategyGovernance();

    // ============================================
    // MODIFIERS
    // ============================================

    /// @notice Derive governance dynamically from the attached strategy (single source of truth).
    /// @dev The provider holds NO governance state of its own — see docs/ASSETS_PROVIDER_GUIDELINES.md.
    modifier onlyStrategyGovernance() {
        (bool success, bytes memory data) = STRATEGY.staticcall(abi.encodeWithSignature("governance()"));
        if (!success || data.length < 32) revert NotStrategyGovernance();
        address governance = abi.decode(data, (address));
        if (msg.sender != governance) revert NotStrategyGovernance();
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    struct ConstructorParams {
        address strategy;
        address usdc;
        address usdg;
        address sy;
        address pt;
        address pendleMarket;
        address oracle;
        address morpho;
        bytes32 morphoMarketId;
        uint32 twapDuration;
        uint256 invarianceToleranceBps;
    }

    /**
     * @notice Constructor
     * @param p Packed constructor params (see ConstructorParams)
     */
    constructor(ConstructorParams memory p) {
        if (p.strategy == address(0)) revert ZeroAddress();
        if (p.usdc == address(0)) revert ZeroAddress();
        if (p.morpho == address(0)) revert ZeroAddress();

        // Validate Morpho market exists (loanToken should be USDC; collateral should be PT-USDG).
        // The Morpho market is optional at deploy time — it may not exist yet, in which case
        // morphoMarketId is left as bytes32(0) and wired in later via setMorphoMarket().
        if (p.morphoMarketId != bytes32(0)) {
            (address loanToken,,,,) = IMorphoBlue(p.morpho).idToMarketParams(p.morphoMarketId);
            if (loanToken == address(0)) revert InvalidMorphoMarket();
        }

        STRATEGY = p.strategy;
        USDC = p.usdc;
        USDG = p.usdg;
        ORACLE = p.oracle;
        MORPHO = p.morpho;
        TWAP_DURATION = p.twapDuration;
        INVARIANCE_TOLERANCE_BPS = p.invarianceToleranceBps;

        sy = p.sy;
        pt = p.pt;
        pendleMarket = p.pendleMarket;
        morphoMarketId = p.morphoMarketId;
    }

    // ============================================
    // IExternalAssetsProvider
    // ============================================

    function denominationToken() external view override returns (address) {
        return USDC;
    }

    /**
     * @notice Returns NET total assets denominated in USDC
     * @dev Aggregates all USDG-equivalent positions (idle USDG, SY, PT, Morpho PT collateral)
     *      plus idle USDC, then subtracts Morpho borrow debt.
     *
     *      USDG ≈ USDC (both 6 decimals, USD-pegged) — same simplification as V1/V2.
     *
     *      grossAssets = idle USDC
     *                  + idle USDG
     *                  + SY balance
     *                  + (PT balance + Morpho PT collateral) × Pendle TWAP rate / 1e18
     *      netAssets   = grossAssets - Morpho borrow debt (USDC, rounded up)
     *
     *      If Morpho debt exceeds gross assets (underwater), returns 0.
     */
    function getTotalAssets() external view override returns (uint256) {
        return _getTotalAssets();
    }

    function _getTotalAssets() internal view returns (uint256) {
        // 1. Idle USDC (includes any borrowed USDC still sitting in the strategy)
        uint256 usdcBal = IERC20(USDC).balanceOf(STRATEGY);

        // 2. Idle USDG (≈ USDC, both 6 decimals)
        uint256 usdgBal = IERC20(USDG).balanceOf(STRATEGY);

        // 3. SY balance — SY wraps USDG ~1:1
        uint256 syBal = IERC20(sy).balanceOf(STRATEGY);

        // 4. Read Morpho position (collateral = PT-USDG, borrowShares = USDC debt).
        //    Skip entirely when no Morpho market is wired (morphoMarketId == 0).
        uint128 borrowShares;
        uint128 collateral;
        if (morphoMarketId != bytes32(0)) {
            (, borrowShares, collateral) = IMorphoBlue(MORPHO).position(morphoMarketId, STRATEGY);
        }

        // 5. PT-denominated total = idle PT + Morpho PT collateral
        uint256 totalPt = IERC20(pt).balanceOf(STRATEGY) + uint256(collateral);

        // 6. PT → USDG (≈ USDC) via Pendle Oracle TWAP (rate in 1e18, 1e18 = 1 PT = 1 underlying)
        uint256 ptValue = 0;
        if (totalPt > 0 && ORACLE != address(0)) {
            uint256 ptRate = IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION);
            ptValue = (totalPt * ptRate) / 1e18;
        }

        // 7. Gross assets in USDC units (USDG ≈ USDC, SY ≈ USDG ≈ USDC)
        uint256 grossAssets = usdcBal + usdgBal + syBal + ptValue;

        // 8. Subtract Morpho borrow debt (USDC, rounded up)
        uint256 borrowDebt = _borrowSharesToAssets(uint256(borrowShares));
        if (borrowDebt >= grossAssets) return 0; // underwater safety
        return grossAssets - borrowDebt;
    }

    // ============================================
    // GOVERNANCE: ROLLOVER + UPDATES
    // ============================================

    /**
     * @notice Update the Pendle config (PT / market / SY) on rollover.
     * @dev Requires totalAssets to remain within INVARIANCE_TOLERANCE_BPS across the swap,
     *      which implicitly enforces that the old PT/SY positions are empty before rollover.
     * @param newPt New PT-USDG token
     * @param newPendleMarket New Pendle market (for oracle TWAP)
     * @param newSy New SY-USDG token
     */
    function setPendleConfig(address newPt, address newPendleMarket, address newSy) external onlyStrategyGovernance {
        if (newPt == address(0) || newPendleMarket == address(0) || newSy == address(0)) revert ZeroAddress();

        uint256 beforeTotal = _getTotalAssets();

        address oldPt = pt;
        address oldMarket = pendleMarket;
        address oldSy = sy;

        pt = newPt;
        pendleMarket = newPendleMarket;
        sy = newSy;

        _checkInvariance(beforeTotal, _getTotalAssets());

        emit PendleConfigUpdated(oldPt, newPt, oldMarket, newPendleMarket, oldSy, newSy);
    }

    /**
     * @notice Update the Morpho Blue market id (PT-USDG collateral / USDC loan) on rollover.
     * @dev Requires totalAssets to remain within INVARIANCE_TOLERANCE_BPS across the swap,
     *      which implicitly enforces that the old Morpho collateral/debt are zero before rollover.
     * @param newMarketId New Morpho Blue market id
     */
    function setMorphoMarket(bytes32 newMarketId) external onlyStrategyGovernance {
        if (newMarketId != bytes32(0)) {
            (address loanToken,,,,) = IMorphoBlue(MORPHO).idToMarketParams(newMarketId);
            if (loanToken == address(0)) revert InvalidMorphoMarket();
        }

        uint256 beforeTotal = _getTotalAssets();

        bytes32 oldMarketId = morphoMarketId;
        morphoMarketId = newMarketId;

        _checkInvariance(beforeTotal, _getTotalAssets());

        emit MorphoMarketUpdated(oldMarketId, newMarketId);
    }

    /// @dev Reverts if afterTotal deviates from beforeTotal beyond INVARIANCE_TOLERANCE_BPS.
    function _checkInvariance(uint256 beforeTotal, uint256 afterTotal) internal view {
        if (beforeTotal == 0) {
            if (afterTotal != 0) revert TotalAssetsChanged(beforeTotal, afterTotal);
            return;
        }
        uint256 tolerance = (beforeTotal * INVARIANCE_TOLERANCE_BPS) / 10_000;
        if (afterTotal + tolerance < beforeTotal || afterTotal > beforeTotal + tolerance) {
            revert TotalAssetsChanged(beforeTotal, afterTotal);
        }
    }

    // ============================================
    // CONVENIENCE VIEW FUNCTIONS
    // ============================================

    /// @notice Get the current Pendle Oracle PT-to-asset rate (1e18 scale, USDG-denominated)
    function getPtToAssetRate() external view returns (uint256) {
        return IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION);
    }

    /**
     * @notice Get Morpho position summary
     * @return collateralPt PT-USDG amount supplied as Morpho collateral
     * @return borrowShares Raw Morpho borrow shares
     * @return borrowAssetsUsdc USDC borrow debt (rounded up)
     */
    function getMorphoPosition()
        external
        view
        returns (uint256 collateralPt, uint256 borrowShares, uint256 borrowAssetsUsdc)
    {
        if (morphoMarketId == bytes32(0)) return (0, 0, 0);
        (, uint128 _borrowShares, uint128 _collateral) = IMorphoBlue(MORPHO).position(morphoMarketId, STRATEGY);
        collateralPt = uint256(_collateral);
        borrowShares = uint256(_borrowShares);
        borrowAssetsUsdc = _borrowSharesToAssets(borrowShares);
    }

    /**
     * @notice Get full position breakdown
     * @return usdcBalance Raw USDC balance in strategy (6 decimals)
     * @return usdgBalance Raw USDG balance in strategy (6 decimals)
     * @return syBalance Raw SY-USDG balance in strategy
     * @return ptBalance Raw PT-USDG balance in strategy
     * @return morphoCollateralPt PT-USDG amount on Morpho as collateral
     * @return morphoBorrowUsdc USDC borrow debt on Morpho (rounded up, 6 decimals)
     * @return ptToAssetRate Current Pendle TWAP PT→USDG rate (1e18 scale)
     */
    function getPositionBreakdown()
        external
        view
        returns (
            uint256 usdcBalance,
            uint256 usdgBalance,
            uint256 syBalance,
            uint256 ptBalance,
            uint256 morphoCollateralPt,
            uint256 morphoBorrowUsdc,
            uint256 ptToAssetRate
        )
    {
        usdcBalance = IERC20(USDC).balanceOf(STRATEGY);
        usdgBalance = IERC20(USDG).balanceOf(STRATEGY);
        syBalance = IERC20(sy).balanceOf(STRATEGY);
        ptBalance = IERC20(pt).balanceOf(STRATEGY);

        if (morphoMarketId != bytes32(0)) {
            (, uint128 borrowShares, uint128 collateral) = IMorphoBlue(MORPHO).position(morphoMarketId, STRATEGY);
            morphoCollateralPt = uint256(collateral);
            morphoBorrowUsdc = _borrowSharesToAssets(uint256(borrowShares));
        }

        ptToAssetRate = ORACLE != address(0) ? IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION) : 0;
    }

    // ============================================
    // INTERNAL
    // ============================================

    /**
     * @notice Convert Morpho borrow shares to underlying assets (rounded up)
     * @dev Morpho Blue formula:
     *      borrowAssets = ceil(shares * (totalBorrowAssets + 1) / (totalBorrowShares + 1e6))
     *      Rounding up gives a conservative (overstating) debt estimate, which is the
     *      safe direction for net-asset reporting.
     */
    function _borrowSharesToAssets(uint256 shares) internal view returns (uint256) {
        if (shares == 0) return 0;
        (,, uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = IMorphoBlue(MORPHO).market(morphoMarketId);
        uint256 numerator = shares * (uint256(totalBorrowAssets) + VIRTUAL_ASSETS);
        uint256 denominator = uint256(totalBorrowShares) + VIRTUAL_SHARES;
        return (numerator + denominator - 1) / denominator;
    }
}
