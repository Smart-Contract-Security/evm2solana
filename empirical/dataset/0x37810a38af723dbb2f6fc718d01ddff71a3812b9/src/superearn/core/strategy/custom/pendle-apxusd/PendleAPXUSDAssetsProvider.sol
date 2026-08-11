// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IExternalAssetsProvider } from "@superearn/v2/interfaces/IExternalAssetsProvider.sol";
import { IPendleOracle } from "@superearn/interface/IPendle.sol";
import { IMorphoBlue } from "@superearn/interface/IMorphoBlue.sol";
import { ICurveStablePool } from "@superearn/core/strategy/custom/snusd/ICurveStablePool.sol";

/**
 * @title PendleAPXUSDAssetsProvider
 * @notice Assets provider for a CustomStrategy holding PT-apxUSD (Apyx Protocol) positions
 *         and looping via Morpho Blue with USDC as the borrow currency.
 *
 *         Tracked positions:
 *           - Idle USDC (denomination)
 *           - Idle apxUSD (priced via Curve probe → USDC)
 *           - Idle PT-apxUSD (priced via Pendle TWAP → apxUSD → USDC)
 *           - Morpho collateral (apxUSD or PT-apxUSD per slot)
 *           - Morpho USDC borrow debt (subtracted)
 *
 * @dev DENOMINATION: USDC (6 decimals). The strategy receives user-facing USDC, swaps
 *      USDC → apxUSD via DEX (Curve direct, Uniswap V4 via Universal Router, or any
 *      DEX aggregator), wraps apxUSD into PT-apxUSD via Pendle, then loops via Morpho
 *      to amplify yield. The provider is execution-venue agnostic — it only values
 *      whatever positions the strategy ends up holding.
 *
 *      Asset chain executed by the strategy:
 *
 *        USDC ── Curve(apxUSD/USDC)  ─────────────────> apxUSD
 *                  └─ or Uniswap V4 (Universal Router) ─────> apxUSD
 *                  └─ or Li.Fi / 0x / 1inch aggregator (off-chain quote)
 *
 *        apxUSD ── Pendle.swapExactTokenForPt (via SY) ─> PT-apxUSD
 *        apxUSD ── Morpho.supplyCollateral (slot 0)    ─> Morpho.borrow USDC
 *        PT-apxUSD ── Morpho.supplyCollateral (slot 1) ─> Morpho.borrow USDC
 *
 * @dev PRICING — NO 1:1 SIMPLIFICATIONS FOR apxUSD.
 *
 *      apxUSD has NO independent on-chain oracle on Ethereum mainnet at the time of
 *      writing — no Chainlink / Redstone / Pyth / Chronicle feed exists, and Apyx
 *      itself only publishes a hardcoded-to-1.0 "Collateralization Cap Ratio" stub
 *      (which Morpho's existing apxUSD oracles depend on). The only manipulation-
 *      resistant on-chain price source is the EMA oracle built into the Curve
 *      StableSwap-NG pool at 0xE1B96555BbecA40E583BbB41a11C68Ca4706A414 itself
 *      (coin[0] = apxUSD, coin[1] = USDC).
 *
 *      Curve StableSwap-NG's `price_oracle(i)`:
 *        - Returns the exchange ratio of coins[i+1] in terms of coins[0], scaled to
 *          1e18 in decimal-normalised units.
 *        - Lazily updated on every state-changing pool call (`exchange`,
 *          `add_liquidity`, `remove_liquidity_imbalance`); the view function applies
 *          time-decay to the stored EMA + `last_prices` to return "EMA as of now"
 *          without a state write.
 *        - Manipulation: a single block's swap can move the EMA by at most
 *          ~(blockTime / ma_exp_time). For the apxUSD/USDC pool, ma_exp_time = 866s
 *          (~14.4 min), so single-block manipulation moves the EMA by less than 2%
 *          AND would require sustained capital loss to keep the pool imbalanced.
 *
 *      The strategy reads `price_oracle(0)` and uses it as the USDC-per-apxUSD rate
 *      (already 1e18-normalised across decimal differences). Math:
 *
 *        apxUsdRaw (18 dec) × price_oracle (1e18) / 1e30 → usdcRaw (6 dec)
 *
 *      Bounds check: the EMA result is required to lie within `[MIN_PRICE_BOUND_WAD,
 *      MAX_PRICE_BOUND_WAD]` (0.90×1e18 to 1.10×1e18). Out of bounds reverts with
 *      `PriceOutOfBounds`. This protects against:
 *        - Sustained pool manipulation drifting the EMA outside reasonable bounds.
 *        - Genuine catastrophic depeg, where reading any price for accounting is
 *          unsafe and totalAssets should not be reported until governance intervenes.
 *        - Silent over-statement (NAV-inflation): bounds force an honest revert
 *          rather than letting an out-of-band EMA flow into reported totalAssets.
 *
 *      A small depeg (e.g., apxUSD trading at $0.98) IS still reflected in
 *      `getTotalAssets()` — the bounds permit normal fluctuation, and totalAssets
 *      decreases linearly with the EMA.
 *
 *      PT-apxUSD → apxUSD via Pendle TWAP `getPtToAssetRate(market, duration)`.
 *      The PT-apxUSD SY wraps apxUSD 1:1 — `SY.assetInfo()` returns apxUSD as the
 *      underlying — so the returned rate maps PT (18 dec) → apxUSD (18 dec). The
 *      apxUSD-equivalent value is then routed through the same Curve EMA to USDC.
 *
 * @dev SLOT MAPPING — USDC-LOAN ONLY (2 slots):
 *
 *        slot 0 (apxUSD/USDC)    → collateral = apxUSD,    loan = USDC
 *        slot 1 (PT-apxUSD/USDC) → collateral = PT-apxUSD, loan = USDC
 *
 *      As of the time this contract was written, the live PT-apxUSD Morpho market
 *      borrows apxUSD (not USDC). If only an apxUSD-loan market is available at
 *      deployment, deploy with the corresponding slot left as bytes32(0) and
 *      populate it once a permissionless USDC-loan market is created. Future
 *      apxUSD-loan support would require a different (3- or 4-slot) provider
 *      variant; this provider is deliberately scoped to USDC loans only.
 *
 * @dev ROLLOVER + MUTABLE CONFIG:
 *
 *      PT / SY / Pendle market and per-slot Morpho market id are mutable, gated
 *      by `onlyStrategyGovernance`. Every change runs through a totalAssets
 *      invariance check (`INVARIANCE_TOLERANCE_BPS`, 10 bps) — implicitly enforces
 *      that the old position is empty (PT balance, SY balance, Morpho collateral,
 *      Morpho debt all zero) before rollover.
 *
 *      Morpho borrow debt uses the conservative rounded-up calculation:
 *        borrowAssets = ceil(borrowShares * (totalBorrowAssets + 1) / (totalBorrowShares + 1e6))
 *
 * @dev OFF-CHAIN DATA REQUIREMENTS (READ THIS):
 *
 *      THIS PROVIDER IS PURE ON-CHAIN. `getTotalAssets()` reads ONLY:
 *        - Pendle Oracle TWAP (`getPtToAssetRate`)
 *        - Curve StableSwap-NG `price_oracle(0)` (EMA, view-safe, no state write)
 *        - Morpho Blue `position` / `market`
 *        - ERC20 balances on the strategy
 *      No off-chain feed, no signed message, no Chainlink Functions call.
 *
 *      The companion CustomStrategy is what actually performs swaps. The accompanying
 *      production deployment script wires TWO execution venues:
 *
 *      Route 1 — Curve apxUSD/USDC pool direct (NO off-chain quote required):
 *        Allowlist `0xE1B9...A414` and `exchange(int128,int128,uint256,uint256)`.
 *        The keeper computes `min_dy` off-chain (typically via the same pool's
 *        `get_dy` view from a recent block) and submits the tx.
 *
 *      Route 2 — Uniswap V4 via Universal Router (NO off-chain quote required):
 *        Allowlist the V4-capable Universal Router and `execute(bytes,bytes[],uint256)`.
 *        Universal Router commands are bytes-encoded — the receiver of the swap
 *        proceeds is encoded inside the `inputs` blob rather than a top-level
 *        param-checkable word, so the swap recipient cannot be word-pinned. The
 *        strategy must instead rely on:
 *          - Strategist authority (a multisig-governed role) to construct calldata,
 *          - Pre-flight slippage assertion (V4_SWAP commands include `amountOutMin`),
 *          - Permit2 approval gating: the strategy approves Permit2 once for USDC
 *            and apxUSD, and Permit2 in turn approves the Universal Router for a
 *            bounded amount.
 *        The keeper builds the V4 swap commands locally; no off-chain HTTP API.
 *
 *      Route 3 — DEX aggregator (Li.Fi / 0x / 1inch, OFF-CHAIN QUOTE REQUIRED):
 *        Optional. Same flow as Route 2 but uses an aggregator router instead of
 *        Universal Router; calldata is fetched from the aggregator's HTTP API.
 *        Not enabled by default in the production deployment script.
 *
 *      Either way, `getTotalAssets()` is unaffected — it values whatever positions
 *      the strategy currently holds in USDC terms via Curve EMA + Pendle TWAP.
 *
 * ============================================================================
 * Contract Addresses (Ethereum Mainnet, captured at the time of writing):
 *   USDC               = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  (6 decimals)
 *   apxUSD             = 0x98A878b1Cd98131B271883B390f68D2c90674665  (18 decimals)
 *   PENDLE_ORACLE      = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2
 *   MARKET_PT_APXUSD   = 0x50dCE085AF29CABa28F7308beA57C4043757b491  (matures 2026-06-18)
 *   SY_APXUSD          = 0x4F116ee5BCd227d1A1C4f57918d694a4abE7B3Fc  (SY.assetInfo = apxUSD)
 *   PT_APXUSD          = 0x92A6A01b07984de46c24E8EbA248449beB8B1Dcb
 *   YT_APXUSD          = 0x7807c638383b95Ac5d58dE10D3079e2140d47C22
 *   CURVE_APXUSD_USDC  = 0xE1B96555BbecA40E583BbB41a11C68Ca4706A414  (coin[0]=apxUSD, coin[1]=USDC)
 *   MORPHO_BLUE        = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
 *
 *   NOTE: as of writing, the existing live PT-apxUSD Morpho market borrows apxUSD,
 *   not USDC. Deploy with slot 1 = bytes32(0) and populate via setMorphoMarket()
 *   once a permissionless USDC-loan PT-apxUSD market is created on Morpho.
 * ============================================================================
 */
contract PendleAPXUSDAssetsProvider is IExternalAssetsProvider {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Curve pool coin index for apxUSD (coins[0]). The `i` arg to `price_oracle(i)`
    ///         returns the EMA price of coins[i+1] relative to coins[0]; we pass 0 to get
    ///         the USDC-per-apxUSD rate.
    uint256 public constant CURVE_PRICE_ORACLE_INDEX = 0;

    /// @notice Curve pool coin index for apxUSD (coins[0]) — for off-chain monitoring use.
    int128 public constant CURVE_APXUSD_INDEX = 0;

    /// @notice Curve pool coin index for USDC (coins[1]) — for off-chain monitoring use.
    int128 public constant CURVE_USDC_INDEX = 1;

    /// @dev Morpho Blue virtual shares/assets for share math
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @notice Slot indices for Morpho markets
    uint8 public constant SLOT_APXUSD_USDC = 0;
    uint8 public constant SLOT_PT_APXUSD_USDC = 1;
    uint8 public constant NUM_SLOTS = 2;

    /// @notice Tolerance for rollover totalAssets invariance check (10 bps = 0.1%)
    uint256 public constant INVARIANCE_TOLERANCE_BPS = 10;

    /// @notice Lower bound for the Curve EMA price (USDC per apxUSD, 1e18-normalised).
    /// @dev `price_oracle(0) < MIN_PRICE_BOUND_WAD` reverts. Set to 0.90×1e18: anything
    ///      lower means either sustained pool manipulation or a catastrophic depeg —
    ///      either way, halting `getTotalAssets()` is safer than letting an out-of-band
    ///      value flow into reported NAV. Governance can intervene (e.g., rollover or
    ///      provider replacement) without the strategy silently mis-pricing in between.
    uint256 public constant MIN_PRICE_BOUND_WAD = 0.90e18;

    /// @notice Upper bound for the Curve EMA price (USDC per apxUSD, 1e18-normalised).
    /// @dev `price_oracle(0) > MAX_PRICE_BOUND_WAD` reverts. Set to 1.10×1e18: any
    ///      apxUSD price above 1.10 USDC is anomalous (apxUSD has no intrinsic premium
    ///      basis) and most likely reflects pool manipulation aimed at over-stating NAV.
    uint256 public constant MAX_PRICE_BOUND_WAD = 1.10e18;

    // ============================================
    // IMMUTABLE STORAGE
    // ============================================

    address public immutable STRATEGY;
    address public immutable USDC;
    address public immutable APXUSD;
    address public immutable ORACLE;
    address public immutable CURVE_POOL;
    address public immutable MORPHO;

    uint32 public immutable TWAP_DURATION;

    // ============================================
    // MUTABLE STORAGE
    // ============================================

    /// @notice Pendle PT-apxUSD token (mutable: changes on rollover to a new maturity)
    address public pt;
    /// @notice Pendle PT-apxUSD market (mutable: changes on rollover)
    address public pendleMarket;
    /// @notice SY-apxUSD token (mutable: changes on rollover; SY underlying must remain apxUSD)
    address public sy;

    /// @notice Per-slot Morpho market id; bytes32(0) means slot is disabled
    bytes32[NUM_SLOTS] public morphoMarkets;

    // ============================================
    // EVENTS
    // ============================================

    event PendleConfigUpdated(
        address oldPt, address newPt, address oldMarket, address newMarket, address oldSy, address newSy
    );
    event MorphoMarketUpdated(uint8 indexed slot, bytes32 oldMarketId, bytes32 newMarketId);

    // ============================================
    // ERRORS
    // ============================================

    error ZeroAddress();
    error InvalidSlot();
    error InvalidMorphoMarket();
    error TotalAssetsChanged(uint256 beforeTotal, uint256 afterTotal);
    error NotStrategyGovernance();
    /// @notice Curve EMA `price_oracle(0)` fell outside [MIN_PRICE_BOUND_WAD, MAX_PRICE_BOUND_WAD].
    /// @dev See header documentation for the rationale on aborting rather than reporting an
    ///      out-of-band NAV. Recovery: governance assesses cause (manipulation vs depeg)
    ///      and either waits for the EMA to return to range or swaps the provider out.
    error PriceOutOfBounds(uint256 emaWad);

    // ============================================
    // MODIFIERS
    // ============================================

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
        address apxUsd;
        address sy;
        address pt;
        address pendleMarket;
        address pendleOracle;
        address curvePool;
        address morpho;
        uint32 twapDuration;
        bytes32 morphoApxusdUsdc;
        bytes32 morphoPtApxusdUsdc;
    }

    constructor(ConstructorParams memory p) {
        if (
            p.strategy == address(0) || p.usdc == address(0) || p.apxUsd == address(0) || p.sy == address(0)
                || p.pt == address(0) || p.pendleMarket == address(0) || p.pendleOracle == address(0)
                || p.curvePool == address(0) || p.morpho == address(0)
        ) revert ZeroAddress();

        // Validate any non-empty Morpho markets actually exist on the supplied Morpho Blue
        if (p.morphoApxusdUsdc != bytes32(0)) _validateMorphoMarket(p.morpho, p.morphoApxusdUsdc);
        if (p.morphoPtApxusdUsdc != bytes32(0)) _validateMorphoMarket(p.morpho, p.morphoPtApxusdUsdc);

        STRATEGY = p.strategy;
        USDC = p.usdc;
        APXUSD = p.apxUsd;
        ORACLE = p.pendleOracle;
        CURVE_POOL = p.curvePool;
        MORPHO = p.morpho;
        TWAP_DURATION = p.twapDuration;

        sy = p.sy;
        pt = p.pt;
        pendleMarket = p.pendleMarket;

        morphoMarkets[SLOT_APXUSD_USDC] = p.morphoApxusdUsdc;
        morphoMarkets[SLOT_PT_APXUSD_USDC] = p.morphoPtApxusdUsdc;
    }

    function _validateMorphoMarket(address morpho, bytes32 marketId) internal view {
        (address loanToken,,,,) = IMorphoBlue(morpho).idToMarketParams(marketId);
        if (loanToken == address(0)) revert InvalidMorphoMarket();
    }

    // ============================================
    // IExternalAssetsProvider
    // ============================================

    function denominationToken() external view override returns (address) {
        return USDC;
    }

    function getTotalAssets() external view override returns (uint256) {
        return _getTotalAssets();
    }

    /**
     * @dev Net total assets denominated in USDC.
     *      grossAssets = idle USDC
     *                  + (idle apxUSD + SY balance + Morpho slot-0 collateral) priced via Curve EMA
     *                  + (idle PT + Morpho slot-1 collateral) priced via Pendle TWAP → Curve EMA
     *      netAssets   = grossAssets - USDC debt
     *
     *      Pure on-chain; no off-chain data consumed.
     */
    function _getTotalAssets() internal view returns (uint256) {
        // 1. Idle USDC (denomination, includes any borrowed USDC)
        uint256 usdcBal = IERC20(USDC).balanceOf(STRATEGY);

        // 2. Aggregate apxUSD-equivalent positions (idle + SY 1:1 + Morpho slot-0 collateral)
        //    SY-apxUSD wraps apxUSD 1:1 (its `assetInfo()` returns apxUSD).
        uint256 totalApxUsd = IERC20(APXUSD).balanceOf(STRATEGY) + IERC20(sy).balanceOf(STRATEGY);

        // 3. Aggregate raw PT positions (idle + Morpho slot-1 collateral)
        uint256 totalPt = IERC20(pt).balanceOf(STRATEGY);

        // 4. Walk Morpho markets — accumulate collateral by type, sum USDC debt.
        uint256 usdcDebt;
        for (uint256 i; i < NUM_SLOTS; i++) {
            bytes32 marketId = morphoMarkets[i];
            if (marketId == bytes32(0)) continue;

            (, uint128 borrowShares, uint128 collateral) = IMorphoBlue(MORPHO).position(marketId, STRATEGY);

            if (i == SLOT_APXUSD_USDC) {
                totalApxUsd += uint256(collateral);
            } else {
                // SLOT_PT_APXUSD_USDC
                totalPt += uint256(collateral);
            }

            usdcDebt += _borrowSharesToAssets(marketId, uint256(borrowShares));
        }

        // 5. PT (idle + Morpho slot 1) → apxUSD via Pendle Oracle TWAP.
        //    SY-apxUSD's underlying asset is apxUSD (both 18 dec), so
        //    apxUsdRaw = ptRaw * ptRate / 1e18.
        if (totalPt > 0) {
            uint256 ptRate = IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION);
            totalApxUsd += Math.mulDiv(totalPt, ptRate, 1e18);
        }

        // 6. Convert aggregated apxUSD → USDC via Curve EMA `price_oracle(0)`.
        //    See `_apxUsdToUsdcViaCurveEma` for the math + bounds rationale.
        uint256 apxUsdAsUsdc = _apxUsdToUsdcViaCurveEma(totalApxUsd);

        // 7. Net = gross - debt; underwater clamp
        uint256 grossAssets = usdcBal + apxUsdAsUsdc;
        if (usdcDebt >= grossAssets) return 0;
        return grossAssets - usdcDebt;
    }

    // ============================================
    // PRICING HELPERS
    // ============================================

    /**
     * @notice Convert an apxUSD amount (18 dec) to USDC (6 dec) using the Curve pool's
     *         EMA price oracle.
     * @dev `price_oracle(0)` returns the USDC-per-apxUSD exchange rate in 1e18-normalised
     *      units, regardless of raw token decimals (the pool internally rate-normalises
     *      every coin to 1e18). To get a 6-dec USDC raw amount from an 18-dec apxUSD raw
     *      amount, divide by 1e30 = 1e18 (rate scale) × 1e12 (apxUSD→USDC dec gap).
     *
     *      Bounds: the returned EMA MUST satisfy
     *        MIN_PRICE_BOUND_WAD <= price_oracle(0) <= MAX_PRICE_BOUND_WAD
     *      otherwise reverts with `PriceOutOfBounds`. See header docs for rationale.
     *
     *      Returns 0 when `apxUsdAmount == 0` to short-circuit empty-position calls;
     *      bounds check is still applied for any non-zero amount, even if it would
     *      round to zero in USDC (so a degenerate dust read still surfaces an out-of-
     *      band EMA via revert rather than silent zero).
     */
    function _apxUsdToUsdcViaCurveEma(uint256 apxUsdAmount) internal view returns (uint256) {
        if (apxUsdAmount == 0) return 0;
        uint256 priceWad = ICurveStablePool(CURVE_POOL).price_oracle(CURVE_PRICE_ORACLE_INDEX);
        if (priceWad < MIN_PRICE_BOUND_WAD || priceWad > MAX_PRICE_BOUND_WAD) {
            revert PriceOutOfBounds(priceWad);
        }
        // apxUsdAmount (18 dec) × priceWad (1e18) / 1e30 = usdcRaw (6 dec)
        return Math.mulDiv(apxUsdAmount, priceWad, 1e30);
    }

    /// @dev borrowAssets = ceil(shares × (totalBorrowAssets + 1) / (totalBorrowShares + 1e6))
    function _borrowSharesToAssets(bytes32 marketId, uint256 shares) internal view returns (uint256) {
        if (shares == 0) return 0;
        (,, uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = IMorphoBlue(MORPHO).market(marketId);
        uint256 numerator = shares * (uint256(totalBorrowAssets) + VIRTUAL_ASSETS);
        uint256 denominator = uint256(totalBorrowShares) + VIRTUAL_SHARES;
        return (numerator + denominator - 1) / denominator;
    }

    // ============================================
    // GOVERNANCE: ROLLOVER + UPDATES
    // ============================================

    /**
     * @notice Update Pendle config (PT, market, SY) for rollover to a new maturity.
     * @dev Reverts unless totalAssets stays within INVARIANCE_TOLERANCE_BPS — this
     *      implicitly requires the old PT/SY balances and the PT-collateral Morpho
     *      slot to be empty before the rollover, otherwise switching addresses would
     *      change the reported totalAssets.
     *
     *      The new SY underlying asset MUST still be apxUSD; otherwise the Pendle
     *      TWAP unit would no longer match the apxUSD accumulator and the invariance
     *      check would catch the mismatch only by coincidence.
     */
    function setPendleConfig(address newPt, address newPendleMarket, address newSy)
        external
        onlyStrategyGovernance
    {
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
     * @notice Update a Morpho market id for a given slot (or set to bytes32(0) to disable).
     * @dev Reverts unless totalAssets stays within INVARIANCE_TOLERANCE_BPS — implicitly
     *      requires the old slot's collateral and debt to be zero before swapping.
     */
    function setMorphoMarket(uint8 slot, bytes32 newMarketId) external onlyStrategyGovernance {
        if (slot >= NUM_SLOTS) revert InvalidSlot();
        if (newMarketId != bytes32(0)) {
            _validateMorphoMarket(MORPHO, newMarketId);
        }

        uint256 beforeTotal = _getTotalAssets();

        bytes32 oldMarketId = morphoMarkets[slot];
        morphoMarkets[slot] = newMarketId;

        _checkInvariance(beforeTotal, _getTotalAssets());

        emit MorphoMarketUpdated(slot, oldMarketId, newMarketId);
    }

    function _checkInvariance(uint256 beforeTotal, uint256 afterTotal) internal pure {
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
    // CONVENIENCE VIEWS
    // ============================================

    /// @notice The Curve EMA `price_oracle(0)` value used by valuation (USDC-per-apxUSD,
    ///         1e18-normalised, decimal-agnostic).
    /// @dev This is the canonical rate used by `_getTotalAssets()`. Bounds are NOT applied
    ///      here so off-chain monitors can observe an out-of-band EMA before it would
    ///      revert valuation.
    function getApxUsdToUsdcEmaWad() external view returns (uint256) {
        return ICurveStablePool(CURVE_POOL).price_oracle(CURVE_PRICE_ORACLE_INDEX);
    }

    /// @notice The on-the-fly Curve quote for swapping 1e18 apxUSD → USDC right now,
    ///         in 6-decimal USDC raw units.
    /// @dev NOT used by valuation. Returned for off-chain monitoring and for keepers
    ///      that want to compute `min_dy` for actual swaps via `exchange(...)`.
    function getApxUsdToUsdcDexQuote() external view returns (uint256) {
        return ICurveStablePool(CURVE_POOL).get_dy(CURVE_APXUSD_INDEX, CURVE_USDC_INDEX, 1e18);
    }

    /// @notice Get the current Pendle Oracle PT→apxUSD rate (1e18 scale, apxUSD-denominated)
    function getPtToAssetRate() external view returns (uint256) {
        return IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION);
    }

    function getMorphoMarket(uint8 slot) external view returns (bytes32) {
        if (slot >= NUM_SLOTS) revert InvalidSlot();
        return morphoMarkets[slot];
    }

    /// @notice Get Morpho position for a single slot
    /// @dev `collateral` decimals: slot 0 = apxUSD (18 dec), slot 1 = PT (18 dec).
    ///      `borrowAssets` decimals: USDC (6 dec) for all slots.
    function getMorphoPosition(uint8 slot)
        external
        view
        returns (uint256 collateral, uint256 borrowShares, uint256 borrowAssets)
    {
        if (slot >= NUM_SLOTS) revert InvalidSlot();
        bytes32 marketId = morphoMarkets[slot];
        if (marketId == bytes32(0)) return (0, 0, 0);
        (, uint128 _borrowShares, uint128 _collateral) = IMorphoBlue(MORPHO).position(marketId, STRATEGY);
        collateral = uint256(_collateral);
        borrowShares = uint256(_borrowShares);
        borrowAssets = _borrowSharesToAssets(marketId, borrowShares);
    }

    /**
     * @notice Get full position breakdown.
     * @return usdcBalance         Raw USDC balance in strategy (6 decimals)
     * @return apxUsdBalance       Raw apxUSD balance in strategy (18 decimals)
     * @return syBalance           Raw SY-apxUSD balance in strategy (18 decimals)
     * @return ptBalance           Raw PT-apxUSD balance in strategy (18 decimals)
     * @return morphoCollaterals   Per-slot collateral (slot 0: apxUSD; slot 1: PT)
     * @return morphoBorrowDebts   Per-slot USDC borrow debt (6 decimals)
     * @return ptToAssetRate       Current Pendle TWAP PT→apxUSD rate (1e18 scale)
     * @return apxUsdToUsdcEmaWad  Current Curve EMA price_oracle(0) — 1e18-normalised,
     *                             USDC-per-apxUSD; this is what valuation uses
     * @return apxUsdToUsdcDexQuote Current Curve get_dy(0,1,1e18) — for off-chain
     *                             monitoring and keeper `min_dy` reference (6 decimals)
     */
    function getPositionBreakdown()
        external
        view
        returns (
            uint256 usdcBalance,
            uint256 apxUsdBalance,
            uint256 syBalance,
            uint256 ptBalance,
            uint256[NUM_SLOTS] memory morphoCollaterals,
            uint256[NUM_SLOTS] memory morphoBorrowDebts,
            uint256 ptToAssetRate,
            uint256 apxUsdToUsdcEmaWad,
            uint256 apxUsdToUsdcDexQuote
        )
    {
        usdcBalance = IERC20(USDC).balanceOf(STRATEGY);
        apxUsdBalance = IERC20(APXUSD).balanceOf(STRATEGY);
        syBalance = IERC20(sy).balanceOf(STRATEGY);
        ptBalance = IERC20(pt).balanceOf(STRATEGY);

        for (uint256 i; i < NUM_SLOTS; i++) {
            bytes32 marketId = morphoMarkets[i];
            if (marketId == bytes32(0)) continue;
            (, uint128 borrowShares, uint128 collateral) = IMorphoBlue(MORPHO).position(marketId, STRATEGY);
            morphoCollaterals[i] = uint256(collateral);
            morphoBorrowDebts[i] = _borrowSharesToAssets(marketId, uint256(borrowShares));
        }

        ptToAssetRate = IPendleOracle(ORACLE).getPtToAssetRate(pendleMarket, TWAP_DURATION);
        apxUsdToUsdcEmaWad = ICurveStablePool(CURVE_POOL).price_oracle(CURVE_PRICE_ORACLE_INDEX);
        apxUsdToUsdcDexQuote = ICurveStablePool(CURVE_POOL).get_dy(CURVE_APXUSD_INDEX, CURVE_USDC_INDEX, 1e18);
    }
}
