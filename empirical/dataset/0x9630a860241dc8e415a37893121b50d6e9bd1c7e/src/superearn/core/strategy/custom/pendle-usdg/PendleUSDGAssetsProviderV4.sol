// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IExternalAssetsProvider } from "@superearn/v2/interfaces/IExternalAssetsProvider.sol";
import { IPendleOracle } from "@superearn/interface/IPendle.sol";
import { IMorphoBlue } from "@superearn/interface/IMorphoBlue.sol";

/**
 * @title PendleUSDGAssetsProviderV4
 * @notice Assets provider for CustomStrategy holding PT-USDG positions
 *         + Morpho Blue PT-USDG/USDC leverage loop
 *         + Aave V3 USDG supply (NEW in V4).
 *
 *         V4 = V3 (rollover-enabled Pendle PT + optional Morpho market) PLUS tracking of USDG
 *         supplied to Aave V3. Supplied USDG is held by the strategy as the rebasing aToken
 *         (aEthUSDG); its `balanceOf` already returns the underlying USDG amount including accrued
 *         interest (6 decimals), so it is added to gross assets 1:1 (USDG ≈ USDC).
 *
 *         Pricing logic is otherwise unchanged from V2/V3 (USDG ≈ USDC, both 6-decimal USD-pegged).
 *
 * @dev Calculates total assets as a USDC-denominated NET sum of:
 *      ASSETS:
 *      - Idle USDC balance (includes any borrowed USDC still in the strategy)
 *      - Idle USDG balance               (1:1 to USDC; both USD-pegged 6 decimals)
 *      - aUSDG balance (Aave V3 supply)  (1:1 to USDG → 1:1 to USDC; rebasing, incl. interest)
 *      - SY-USDG balance                 (1:1 to USDG → 1:1 to USDC)
 *      - PT-USDG balance                 × PendleOracle TWAP rate → USDG → USDC
 *      - Morpho collateral (PT-USDG)     × PendleOracle TWAP rate → USDG → USDC
 *      LIABILITIES (subtracted):
 *      - Morpho borrow debt (USDC, rounded up using Morpho Blue's share-to-asset formula)
 *
 *      Aave note: supplying USDG moves it OUT of the idle USDG balance and INTO aUSDG, so there is
 *      no double counting. Aave is supply-only here (no borrow against the Aave position), so it
 *      contributes assets only — never a liability.
 *
 *      Asset Chain:
 *        USDC ── Curve(USDG/USDC) ──> USDG ──┬─ Pendle ──> PT-USDG ──> Morpho collateral/borrow
 *                                            └─ Aave V3 supply ──> aUSDG (yield-bearing)
 *
 * ============================================================================
 * Aave V3 Configuration Reference (Ethereum Mainnet) — read on-chain, DO NOT guess
 * ============================================================================
 *   AAVE_POOL  = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2  (Pool, revision 10)
 *   aUSDG      = 0x7c0477d085ECb607CF8429f3eC91Ae5E1e460F4F  (aEthUSDG, 6 dec, underlying = USDG)
 *
 *   Strategy execution permissions required for the Aave supply/withdraw loop
 *   (set by the governance Safe batch — see DeployPendleUSDGProviderV4.s.sol):
 *     setAllowedTarget(AAVE_POOL, true)
 *     setAllowedSelector(AAVE_POOL, supply(address,uint256,address,uint16)   = 0x617ba037, true)
 *     setAllowedSelector(AAVE_POOL, withdraw(address,uint256,address)        = 0x69328dec, true)
 *     USDG.approve destination += AAVE_POOL   (setAllowedDestination(USDG, approve, 0, AAVE_POOL))
 *     Pool.supply   — param 0 (asset) locked to USDG, param 2 (onBehalfOf) locked to strategy
 *     Pool.withdraw — param 0 (asset) locked to USDG, param 2 (to)         locked to strategy
 *
 *   Aave operation flows:
 *     Supply:   USDG.approve(AAVE_POOL, amt) ; AAVE_POOL.supply(USDG, amt, strategy, 0)
 *     Withdraw: AAVE_POOL.withdraw(USDG, amt OR type(uint256).max, strategy)
 *
 * ----------------------------------------------------------------------------
 * (Pendle / Curve / Morpho strategy config is identical to V2/V3 — see
 *  PendleUSDGAssetsProviderV2 for the full AllowedTargets/Selectors/ParamChecks reference.)
 *
 *   NEW PT-USDG-24SEP2026 market (this V4 is configured for it, same as V3):
 *     MARKET = 0xf80b67a32df07960c731794769309e3d30e9717f
 *     SY     = 0xc1799CaB1F201946f7CFaFBaF1BCC089b2F08927  (shared, unchanged)
 *     PT     = 0xc1906aeCf868749a2DeE203F59b904c0cf212140  (6 dec)
 *     YT     = 0xB4d8860895dFF6E30C6872075a7BdFfF53B5E772
 * ============================================================================
 */
contract PendleUSDGAssetsProviderV4 is IExternalAssetsProvider {
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
    /// @notice Aave V3 Pool (for convenience views; supply/withdraw are routed by the strategy)
    address public immutable AAVE_POOL;
    /// @notice Aave aToken for USDG (aEthUSDG); balanceOf == supplied USDG incl. accrued interest
    address public immutable A_USDG;
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
    /// @notice Morpho Blue market id (PT-USDG collateral / USDC loan; updatable on rollover; may be 0)
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
        address aavePool;
        address aUsdg;
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
        AAVE_POOL = p.aavePool;
        A_USDG = p.aUsdg;
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
     * @dev Aggregates all USDG-equivalent positions (idle USDG, aUSDG, SY, PT, Morpho PT collateral)
     *      plus idle USDC, then subtracts Morpho borrow debt.
     *
     *      USDG ≈ USDC (both 6 decimals, USD-pegged) — same simplification as V1/V2/V3.
     *
     *      grossAssets = idle USDC
     *                  + idle USDG
     *                  + aUSDG (Aave supply, incl. interest)
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

        // 3. Aave V3 supply: aUSDG balanceOf == underlying USDG incl. accrued interest (6 dec, ≈ USDC).
        //    Skipped if no aToken configured (A_USDG == 0).
        uint256 aUsdgBal = A_USDG != address(0) ? IERC20(A_USDG).balanceOf(STRATEGY) : 0;

        // 4. SY balance — SY wraps USDG ~1:1
        uint256 syBal = IERC20(sy).balanceOf(STRATEGY);

        // 5. Read Morpho position (collateral = PT-USDG, borrowShares = USDC debt).
        //    Skip entirely when no Morpho market is wired (morphoMarketId == 0).
        uint128 borrowShares;
        uint128 collateral;
        if (morphoMarketId != bytes32(0)) {
            (, borrowShares, collateral) = IMorphoBlue(MORPHO).position(morphoMarketId, STRATEGY);
        }

        // 6. PT-denominated total = idle PT + Morpho PT collateral
        uint256 totalPt = IERC20(pt).balanceOf(STRATEGY) + uint256(collateral);

        // 7. PT → USDG (≈ USDC) via Pendle Oracle TWAP (rate in 1e18, 1e18 = 1 PT = 1 underlying)
        uint256 ptValue = 0;
        if (totalPt > 0 && ORACLE != address(0)) {
            uint256 ptRate = IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION);
            ptValue = (totalPt * ptRate) / 1e18;
        }

        // 8. Gross assets in USDC units (USDG ≈ USDC, aUSDG ≈ USDG, SY ≈ USDG ≈ USDC)
        uint256 grossAssets = usdcBal + usdgBal + aUsdgBal + syBal + ptValue;

        // 9. Subtract Morpho borrow debt (USDC, rounded up)
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

    /// @notice USDG currently supplied to Aave V3 (aUSDG balance, incl. accrued interest, 6 dec)
    function getAaveSuppliedUsdg() external view returns (uint256) {
        return A_USDG != address(0) ? IERC20(A_USDG).balanceOf(STRATEGY) : 0;
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
     * @return aUsdgBalance aUSDG balance = USDG supplied to Aave incl. interest (6 decimals)
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
            uint256 aUsdgBalance,
            uint256 syBalance,
            uint256 ptBalance,
            uint256 morphoCollateralPt,
            uint256 morphoBorrowUsdc,
            uint256 ptToAssetRate
        )
    {
        usdcBalance = IERC20(USDC).balanceOf(STRATEGY);
        usdgBalance = IERC20(USDG).balanceOf(STRATEGY);
        aUsdgBalance = A_USDG != address(0) ? IERC20(A_USDG).balanceOf(STRATEGY) : 0;
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
