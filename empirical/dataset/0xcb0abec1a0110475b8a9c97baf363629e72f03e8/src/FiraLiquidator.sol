// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Uses nested calldata structs (FixedPlan → SwapPlan/ApproxParams) in external
// functions; relies on the abicoder v2 layout that solc 0.8.x enables by default.

import {IERC20} from "./interfaces/IERC20.sol";
import {IFlashLoanCallback} from "./interfaces/IFlashLoanCallback.sol";
import {IBalancerVault, IFlashLoanRecipient} from "./interfaces/IBalancerVault.sol";
import {ILendingMarket, MarketParams} from "./interfaces/ILendingMarket.sol";
import {IFiraRouterV4, IFiraMarketTokens, ApproxParams, TokenInput, LimitOrderData} from "./interfaces/IFiraRouterV4.sol";

/// @notice Helper contract for atomically flash-loan + liquidate + swap on Fira
/// lending markets. The signing EOA is the sole `owner` and is the only address
/// that can invoke the liquidation entry points or rescue funds.
///
/// Architecture per `docs/liquidator.md`. v1 collapses the owner/operator split
/// into a single key — see `liquidator_plan_remaining.md` §0 (D3).
///
/// Implemented entry points so far:
///   - `liquidateVariable` (M2.3a) — Fira-self flash path only. Balancer fallback
///     deferred to M2.3c; fixed-rate entry points deferred to M2.4 / M2.5.
contract FiraLiquidator is IFlashLoanCallback, IFlashLoanRecipient {
    /// @dev Source of the active flash loan, used to gate callbacks.
    enum InFlightKind {
        None,
        FiraFlash,
        BalancerFlash
    }

    /// @dev Which flash provider the caller wants to use for a given liquidation.
    enum FlashSource {
        FiraSelf,
        Balancer
    }

    /// @dev Which entry point initiated the active flash loan. Callbacks read
    /// this to dispatch to the matching internal handler. Cleared at the end
    /// of the entry point.
    enum InFlightOp {
        None,
        Variable,
        FixedPre,
        FixedPost
    }

    /// @dev Generic swap calldata bundle for a router call (0x, Pendle, etc.).
    struct SwapPlan {
        address router;
        bytes callData;
        uint256 minOut;
    }

    /// @dev Fixed-rate execution plan, encodes flash source + swap calldata.
    /// `ApproxParams` / `TokenInput` / `LimitOrderData` are imported from
    /// `IFiraRouterV4` so the typed `swapExactTokenForBt` call encodes exactly
    /// like the live Fira router.
    struct FixedPlan {
        FlashSource flashSource;
        address ammMarket; // Fira AMM market for the BT/USDC pair
        uint256 usdcFlashAmount; // Balancer path only; 0 for FIRA_SELF
        uint256 repaidAssets; // BT to flash (FIRA_SELF) == BT we must repay
        SwapPlan ptToUsdc; // seized PT -> USDC, generic router call (Pendle)
        ApproxParams btApprox; // Fira AMM approximation params for USDC -> BT
        TokenInput btInput; // Fira AMM USDC input (tokenIn = USDC, netTokenIn = USDC to spend)
        LimitOrderData btLimit; // Fira AMM limit orders (empty for liquidation)
    }

    // --- immutables (set at deploy) ---

    address public immutable VARIABLE_MARKET;
    address public immutable FIXED_MARKET;
    address public immutable FIRA_ROUTER;
    address public immutable PENDLE_ROUTER;
    address public immutable BALANCER_VAULT;
    address public immutable USDC;

    // --- mutable state ---

    // Storage layout is hand-packed:
    //   slot 0: `owner`                                              (20 bytes, 12 free)
    //   slot 1: `_inFlightKind` + `_inFlightOp` + `_inFlightMarket`  (22 bytes packed, 10 free)
    //   slot 2: `_reentryStatus`                                     (full slot)
    // Reorder cautiously — changing the order forces a redeploy.

    address public owner;

    /// @dev Set by an entry point before triggering a flash loan; checked by the
    /// matching callback. Cleared at the end of the entry point.
    InFlightKind private _inFlightKind;

    /// @dev Which entry point initiated the in-flight flash loan. Read by the
    /// shared callbacks to dispatch to the right internal handler.
    /// Packed with `_inFlightKind` + `_inFlightMarket` in the same slot.
    InFlightOp private _inFlightOp;

    /// @dev When `_inFlightKind == FiraFlash`, the specific Fira market we asked
    /// for a flash from (variable or fixed). For BalancerFlash, the expected
    /// caller is always BALANCER_VAULT and this field is unused.
    address private _inFlightMarket;

    // --- events ---

    event OwnerSet(address indexed previousOwner, address indexed newOwner);
    event Liquidated(
        uint8 indexed kind, // 0 = variable, 1 = fixed-pre, 2 = fixed-post
        address indexed market, // VARIABLE_MARKET or FIXED_MARKET
        address indexed borrower,
        uint256 seizedAssets,
        uint256 repaidAssets,
        uint256 profitUsdc
    );
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event Rescued(address indexed target, uint256 value, bytes data);

    // --- errors ---

    error NotOwner();
    error ZeroAddress();
    error MarketsSame();
    error Reentrancy();
    error NotImplemented();
    error RescueFailed();
    error UnexpectedCallback();
    error ProfitShortfall(uint256 actual, uint256 minimum);
    error UnprofitableLiquidation(uint256 owed, uint256 currentBalance);
    error SwapFailed();
    error SwapShortfall(uint256 actual, uint256 minimum);
    error TransferFailed();

    // --- modifiers ---

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @dev Reentrancy guard storage. Slot is initialised to `1` (unlocked) in
    /// the constructor and toggles between 1↔2 thereafter, so post-deploy
    /// SSTOREs are always warm/dirty (~100 gas) instead of paying the
    /// zero-to-non-zero penalty (~20k gas). Same trick OZ's ReentrancyGuard uses.
    uint256 private _reentryStatus;

    uint256 private constant _UNLOCKED = 1;
    uint256 private constant _LOCKED = 2;

    modifier nonReentrant() {
        if (_reentryStatus != _UNLOCKED) revert Reentrancy();
        _reentryStatus = _LOCKED;
        _;
        _reentryStatus = _UNLOCKED;
    }

    // --- constructor ---

    constructor(
        address variableMarket,
        address fixedMarket,
        address firaRouter,
        address pendleRouter,
        address balancerVault,
        address usdc,
        address initialOwner
    ) {
        if (
            variableMarket == address(0) || fixedMarket == address(0) || firaRouter == address(0)
                || pendleRouter == address(0) || balancerVault == address(0) || usdc == address(0)
                || initialOwner == address(0)
        ) {
            revert ZeroAddress();
        }
        if (variableMarket == fixedMarket) revert MarketsSame();
        VARIABLE_MARKET = variableMarket;
        FIXED_MARKET = fixedMarket;
        FIRA_ROUTER = firaRouter;
        PENDLE_ROUTER = pendleRouter;
        BALANCER_VAULT = balancerVault;
        USDC = usdc;
        owner = initialOwner;
        _reentryStatus = _UNLOCKED;
        emit OwnerSet(address(0), initialOwner);
    }

    // --- liquidation entry points (onlyOwner, nonReentrant) ---

    /// @notice Atomically flash USDC, liquidate `borrower` on the variable-rate
    /// market, swap the seized collateral back to USDC, repay the flash, and
    /// forward profit to `owner`.
    /// @dev Departs from `docs/liquidator.md` §5 in one way: the caller passes
    /// `flashAmount` explicitly rather than the helper computing it from
    /// `seizedAssets + oracle + LIF` on-chain. The single-EOA-owner trust model
    /// makes this safe — if the off-chain math is wrong, the tx reverts (either
    /// liquidate fails for insufficient USDC, or the `minProfit` check fails)
    /// and no funds are lost.
    /// @param p             Market parameters for the position being liquidated.
    /// @param borrower      Borrower whose position is being seized.
    /// @param seizedAssets  Amount of collateral to seize (Morpho derives the
    ///                      repay amount from this + oracle + LIF).
    /// @param flashAmount   USDC to flash; must be ≥ the eventual `repaidAssets`.
    ///                      Off-chain bot computes this via the same LIF formula
    ///                      Fira uses internally.
    /// @param flashSource   `FiraSelf` for v1; `Balancer` deferred to M2.3c.
    /// @param collateralToUsdc 0x (or other) router calldata to swap the seized
    ///                      collateral back to USDC.
    /// @param minProfit     Minimum USDC profit (final-balance − snapshot) the
    ///                      caller will accept. Helper reverts otherwise.
    function liquidateVariable(
        MarketParams calldata p,
        address borrower,
        uint256 seizedAssets,
        uint256 flashAmount,
        FlashSource flashSource,
        SwapPlan calldata collateralToUsdc,
        uint256 minProfit
    ) external onlyOwner nonReentrant {
        uint256 snapshot = IERC20(USDC).balanceOf(address(this));
        // Pass `market` in the payload so the callback doesn't depend on
        // `_inFlightMarket` (unused on the Balancer path).
        bytes memory cbData =
            abi.encode(VARIABLE_MARKET, p, borrower, seizedAssets, collateralToUsdc, snapshot);

        _inFlightOp = InFlightOp.Variable;
        if (flashSource == FlashSource.FiraSelf) {
            // Primary: flash USDC from Fira's own variable market (0% fee).
            _inFlightKind = InFlightKind.FiraFlash;
            _inFlightMarket = VARIABLE_MARKET;
            ILendingMarket(VARIABLE_MARKET).flashLoan(USDC, flashAmount, cbData);
            _inFlightMarket = address(0);
        } else {
            // Fallback: flash USDC from Balancer V2 (used when Fira supply is thin).
            _inFlightKind = InFlightKind.BalancerFlash;
            _balancerFlashUsdc(flashAmount, cbData);
        }

        // Revert inside the flash callback automatically unwinds these SSTOREs
        // along with the rest of the tx state; `nonReentrant` is for nested-
        // call protection, not state-machine cleanup.
        _inFlightKind = InFlightKind.None;
        _inFlightOp = InFlightOp.None;

        uint256 finalBalance = IERC20(USDC).balanceOf(address(this));
        uint256 profit = finalBalance - snapshot; // reverts if final < snapshot
        if (profit < minProfit) revert ProfitShortfall(profit, minProfit);
        if (profit > 0) {
            bool ok = IERC20(USDC).transfer(owner, profit);
            if (!ok) revert TransferFailed();
        }
    }

    /// @notice Atomically flash BT, liquidate `borrower` on the fixed-rate
    /// market (seizing PT collateral), swap PT → USDC (Pendle), buy back BT on
    /// the Fira AMM to repay the flash, and forward USDC profit to `owner`.
    /// @dev FIRA_SELF flashes BT from `FIXED_MARKET`; Balancer flashes
    /// `plan.usdcFlashAmount` USDC, then buys BT on the AMM *before* liquidating.
    /// @param p           Market params; `p.loanToken` is BT, `p.collateralToken` is PT.
    /// @param borrower    Borrower whose position is seized.
    /// @param seizedAssets PT collateral to seize (market derives the BT repay).
    /// @param plan        Flash source + swap plan; `plan.repaidAssets` is the BT
    ///                    amount to flash (FIRA_SELF) / buy (BALANCER).
    /// @param minProfit   Minimum USDC profit the caller will accept.
    function liquidateFixedPreMaturity(
        MarketParams calldata p,
        address borrower,
        uint256 seizedAssets,
        FixedPlan calldata plan,
        uint256 minProfit
    ) external onlyOwner nonReentrant {
        uint256 snapshot = IERC20(USDC).balanceOf(address(this));
        bytes memory cbData = abi.encode(p, borrower, seizedAssets, plan, snapshot);

        _inFlightOp = InFlightOp.FixedPre;
        if (plan.flashSource == FlashSource.FiraSelf) {
            // Flash the BT (loan token) from the fixed market; pulled back after callback.
            _inFlightKind = InFlightKind.FiraFlash;
            _inFlightMarket = FIXED_MARKET;
            ILendingMarket(FIXED_MARKET).flashLoan(p.loanToken, plan.repaidAssets, cbData);
            _inFlightMarket = address(0);
        } else {
            // Flash USDC from Balancer; buy BT on the AMM inside the callback.
            _inFlightKind = InFlightKind.BalancerFlash;
            _balancerFlashUsdc(plan.usdcFlashAmount, cbData);
        }

        _inFlightKind = InFlightKind.None;
        _inFlightOp = InFlightOp.None;

        uint256 finalBalance = IERC20(USDC).balanceOf(address(this));
        uint256 profit = finalBalance - snapshot; // reverts if final < snapshot
        if (profit < minProfit) revert ProfitShortfall(profit, minProfit);
        if (profit > 0) {
            if (!IERC20(USDC).transfer(owner, profit)) revert TransferFailed();
        }
    }

    /// @notice Atomically flash BT, liquidate `borrower`'s expired position via
    /// `liquidateExpiredBt` (seizing all/required collateral), swap PT → USDC,
    /// buy back BT to repay the flash, and forward USDC profit to `owner`.
    /// @dev FIRA_SELF flashes BT from `FIXED_MARKET`; Balancer flashes
    /// `plan.usdcFlashAmount` USDC and MINTS BT (post-maturity the AMM is
    /// expired). No `seizedAssets` — the market seizes collateral and computes
    /// the repaid BT internally from oracle price × `marketConstants.liquidationIncentive`.
    /// For FIRA_SELF the off-chain bot sizes `plan.repaidAssets` (BT to flash) ≥
    /// the on-chain `repaidAssetsPaid`. Bad-debt positions still liquidate — the
    /// market simply pulls less BT.
    /// @param p          Market params; `p.loanToken` is BT, `p.collateralToken` is PT.
    /// @param borrower   Borrower whose expired position is seized.
    /// @param plan       Flash source + swap plan; `plan.repaidAssets` is the BT to flash.
    /// @param minProfit  Minimum USDC profit the caller will accept.
    function liquidateFixedPostMaturity(
        MarketParams calldata p,
        address borrower,
        FixedPlan calldata plan,
        uint256 minProfit
    ) external onlyOwner nonReentrant {
        uint256 snapshot = IERC20(USDC).balanceOf(address(this));
        bytes memory cbData = abi.encode(p, borrower, plan, snapshot);

        _inFlightOp = InFlightOp.FixedPost;
        if (plan.flashSource == FlashSource.FiraSelf) {
            _inFlightKind = InFlightKind.FiraFlash;
            _inFlightMarket = FIXED_MARKET;
            ILendingMarket(FIXED_MARKET).flashLoan(p.loanToken, plan.repaidAssets, cbData);
            _inFlightMarket = address(0);
        } else {
            _inFlightKind = InFlightKind.BalancerFlash;
            _balancerFlashUsdc(plan.usdcFlashAmount, cbData);
        }

        _inFlightKind = InFlightKind.None;
        _inFlightOp = InFlightOp.None;

        uint256 finalBalance = IERC20(USDC).balanceOf(address(this));
        uint256 profit = finalBalance - snapshot; // reverts if final < snapshot
        if (profit < minProfit) revert ProfitShortfall(profit, minProfit);
        if (profit > 0) {
            if (!IERC20(USDC).transfer(owner, profit)) revert TransferFailed();
        }
    }

    // --- flash-loan callbacks ---

    /// @inheritdoc IFlashLoanCallback
    /// @dev Fira flash-loan callback.  Gated by `_inFlightKind = FiraFlash` and
    /// `msg.sender == _inFlightMarket` so an attacker can't trigger this
    /// out-of-band by calling a `flashLoan` themselves.  Dispatches by
    /// `_inFlightOp` to the matching internal handler.
    function onFlashLoan(uint256 flashAmount, bytes calldata data) external override {
        if (_inFlightKind != InFlightKind.FiraFlash) revert UnexpectedCallback();
        if (msg.sender != _inFlightMarket) revert UnexpectedCallback();

        InFlightOp op = _inFlightOp;
        if (op == InFlightOp.Variable) {
            _executeVariable(flashAmount, data);
        } else if (op == InFlightOp.FixedPre) {
            _executeFixedPre(flashAmount, data);
        } else if (op == InFlightOp.FixedPost) {
            _executeFixedPost(flashAmount, data);
        } else {
            revert UnexpectedCallback();
        }
    }

    /// @inheritdoc IFlashLoanRecipient
    /// @dev Balancer flash-loan callback.  Gated by `_inFlightKind = BalancerFlash`
    /// and `msg.sender == BALANCER_VAULT`.  Balancer has already transferred the
    /// flashed token(s) to this contract; the handler must transfer
    /// `amount + fee` back before returning.  Dispatches by `_inFlightOp`.
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external override {
        if (_inFlightKind != InFlightKind.BalancerFlash) revert UnexpectedCallback();
        if (msg.sender != BALANCER_VAULT) revert UnexpectedCallback();

        InFlightOp op = _inFlightOp;
        if (op == InFlightOp.Variable) {
            _executeVariableBalancer(address(tokens[0]), amounts[0], feeAmounts[0], userData);
        } else if (op == InFlightOp.FixedPre) {
            _executeFixedPreBalancer(amounts[0], feeAmounts[0], userData);
        } else if (op == InFlightOp.FixedPost) {
            _executeFixedPostBalancer(amounts[0], feeAmounts[0], userData);
        } else {
            revert UnexpectedCallback();
        }
    }

    /// @dev Trigger a single-token USDC flash loan from the Balancer V2 vault.
    /// Caller sets `_inFlightKind = BalancerFlash` and `_inFlightOp` beforehand.
    function _balancerFlashUsdc(uint256 amount, bytes memory cbData) private {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20(USDC);
        amounts[0] = amount;
        IBalancerVault(BALANCER_VAULT).flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, cbData);
    }

    // --- admin (onlyOwner) ---

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnerSet(previous, newOwner);
    }

    /// @notice Evacuate `amount` of `token` to the current `owner`. Intended for
    /// dust cleanup or emergency recovery; normal liquidation flow forwards
    /// profit inline and leaves zero balance.
    /// @dev v1 token set is USDC / BT-USDC-<maturity> / PT-* — all standard-
    /// returning ERC-20s. MUST NOT add USDT or any non-conforming token without
    /// switching to a SafeERC20-style wrapper, since a token that returns no
    /// data (USDT) would cause the implicit `abi.decode(returndata, (bool))`
    /// to revert with a decoding error rather than `RescueFailed`.
    function withdraw(address token, uint256 amount) external onlyOwner nonReentrant {
        bool ok = IERC20(token).transfer(owner, amount);
        if (!ok) revert RescueFailed();
        emit Withdrawn(token, owner, amount);
    }

    /// @notice Arbitrary-call escape hatch. Trust model: owner is fully
    /// trusted, so this can move *any* balance held by the contract, including
    /// ERC-20s that would otherwise go via `withdraw`. Log analysis must decode
    /// `data` to attribute movements — there is no per-token event from
    /// `rescue`. Use sparingly.
    /// @dev `value` must come from the contract's existing ETH balance. There
    /// is no `receive`/`fallback`, so ETH only arrives via (a) selfdestruct
    /// from another contract — much less common post EIP-6780 — or (b) a
    /// pre-existing balance at the deploy address from a CREATE2 front-run.
    function rescue(address target, uint256 value, bytes calldata data) external onlyOwner nonReentrant {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert RescueFailed();
        }
        emit Rescued(target, value, data);
    }

    // --- internal: variable-rate execution body (M2.3a) ---

    /// @dev Runs inside `onFlashLoan` for `InFlightOp.Variable`.  Caller-side
    /// gating already verified `msg.sender` and inFlight state, so this body
    /// trusts the state machine.
    ///
    /// Flow per `docs/liquidator.md` §4a:
    ///   1. Approve the market for the flashed USDC (it pulls `repaidActual`).
    ///   2. Call liquidate with empty `data` so the inner onLiquidate callback
    ///      is NOT invoked — we're only using the flash-loan callback.
    ///   3. Swap seized collateral → USDC via the supplied SwapPlan; check minOut.
    ///   4. Re-approve market for the full flash repay (Fira is 0%-fee, so
    ///      it pulls exactly `flashAmount`).
    ///   5. Compute expected profit (post-repay balance projection) and emit
    ///      Liquidated.  The entry-point's final `minProfit` check is the
    ///      authoritative safety gate.
    function _executeVariable(uint256 flashAmount, bytes calldata payload) internal {
        (
            address market,
            MarketParams memory p,
            address borrower,
            uint256 seizedAssets,
            SwapPlan memory swap,
            uint256 snapshot
        ) = abi.decode(payload, (address, MarketParams, address, uint256, SwapPlan, uint256));

        // 1. Approve market to pull repaidActual (capped by flashAmount).
        _safeApprove(USDC, market, flashAmount);

        // 2. Liquidate. Empty `data` ⇒ no onLiquidate callback (we don't need it).
        (uint256 seizedActual, uint256 repaidActual) =
            ILendingMarket(market).liquidate(p, borrower, seizedAssets, 0, "");

        // Reset USDC approval to 0 to drop any leftover allowance from over-
        // approve.  Re-approved below for the flash repay.
        _safeApprove(USDC, market, 0);

        // 3. Swap seized collateral → USDC.  Approve exact-in amount; reset
        // approval afterward.  v1 swap targets (0x AllowanceHolder, Pendle V4)
        // both consume exactly the approved amount and leave allowance at zero,
        // but the explicit reset is defence-in-depth for future router additions.
        uint256 usdcBeforeSwap = IERC20(USDC).balanceOf(address(this));
        _safeApprove(p.collateralToken, swap.router, seizedActual);
        (bool ok, bytes memory ret) = swap.router.call(swap.callData);
        if (!ok) {
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert SwapFailed();
        }
        _safeApprove(p.collateralToken, swap.router, 0);

        uint256 swapOut = IERC20(USDC).balanceOf(address(this)) - usdcBeforeSwap;
        if (swapOut < swap.minOut) revert SwapShortfall(swapOut, swap.minOut);

        // 4. Approve market for flash repay (Fira pulls via transferFrom after
        // this callback returns).
        _safeApprove(USDC, market, flashAmount);

        // 5. Compute expected post-repay balance and emit.  Current balance =
        // snapshot + flashAmount - repaidActual + swapOut.  After Fira pulls
        // flashAmount, balance = snapshot + swapOut - repaidActual, so
        // expectedProfit = currentBalance - snapshot - flashAmount.  For Fira's
        // zero-fee flashLoan this equals the entry-point's final profit exactly;
        // when M2.3c adds Balancer (potentially non-zero fee in future) this
        // event will need to subtract the fee for `expectedProfit` to stay
        // accurate.  The entry-point's `minProfit` check is the authoritative
        // gate regardless.
        uint256 currentBalance = IERC20(USDC).balanceOf(address(this));
        uint256 owedForFlash = snapshot + flashAmount;
        if (currentBalance < owedForFlash) {
            revert UnprofitableLiquidation(owedForFlash, currentBalance);
        }
        uint256 expectedProfit = currentBalance - owedForFlash;
        emit Liquidated(0, market, borrower, seizedActual, repaidActual, expectedProfit);
    }

    /// @dev Variable-rate body for the Balancer flash path. Identical liquidate +
    /// collateral→USDC swap as `_executeVariable`, but repays the flash by
    /// transferring `amount + fee` USDC back to the Balancer vault (Balancer
    /// pushed the loan to us up-front), rather than approving the Fira market to
    /// pull it. `token` is always USDC for the variable markets.
    function _executeVariableBalancer(address token, uint256 amount, uint256 fee, bytes calldata payload) internal {
        (
            address market,
            MarketParams memory p,
            address borrower,
            uint256 seizedAssets,
            SwapPlan memory swap,
            uint256 snapshot
        ) = abi.decode(payload, (address, MarketParams, address, uint256, SwapPlan, uint256));

        // 1. Liquidate (token == USDC).
        _safeApprove(token, market, amount);
        (uint256 seizedActual, uint256 repaidActual) =
            ILendingMarket(market).liquidate(p, borrower, seizedAssets, 0, "");
        _safeApprove(token, market, 0);

        // 2. Swap seized collateral → USDC.
        uint256 usdcBeforeSwap = IERC20(token).balanceOf(address(this));
        _safeApprove(p.collateralToken, swap.router, seizedActual);
        (bool ok, bytes memory ret) = swap.router.call(swap.callData);
        if (!ok) {
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert SwapFailed();
        }
        _safeApprove(p.collateralToken, swap.router, 0);
        uint256 swapOut = IERC20(token).balanceOf(address(this)) - usdcBeforeSwap;
        if (swapOut < swap.minOut) revert SwapShortfall(swapOut, swap.minOut);

        // 3. Repay the Balancer flash: push amount + fee back to the vault.
        uint256 owed = amount + fee;
        if (!IERC20(token).transfer(BALANCER_VAULT, owed)) revert TransferFailed();

        // 4. Emit. Profit is the post-repay balance over the snapshot.
        uint256 currentBalance = IERC20(token).balanceOf(address(this));
        if (currentBalance < snapshot) revert UnprofitableLiquidation(snapshot, currentBalance);
        emit Liquidated(0, market, borrower, seizedActual, repaidActual, currentBalance - snapshot);
    }

    // --- internal: fixed-rate pre-maturity execution body (M2.4) ---

    /// @dev Runs inside `onFlashLoan` for `InFlightOp.FixedPre`. Flash token is
    /// BT (the loan token), not USDC. Caller-side gating already verified
    /// `msg.sender == FIXED_MARKET` and the inFlight state.
    ///
    /// Flow per `docs/liquidator.md` §4b (FIRA_SELF path):
    ///   1. Approve the fixed market for the flashed BT (it pulls the repay).
    ///   2. liquidate with empty `data` ⇒ no onLiquidate callback. Pulls BT,
    ///      sends seized PT collateral here.
    ///   3. Swap PT → USDC via the generic Pendle SwapPlan; check minOut.
    ///   4. Buy back the BT still owed for the flash on the Fira AMM, paying
    ///      USDC (typed `swapExactTokenForBt`, exact-in). `minBtOut` is derived
    ///      at runtime from the BT balance so over/under-flash is handled.
    ///   5. Re-approve BT for the flash repay (market pulls `flashAmount`).
    ///   6. Emit. Profit is USDC = Pendle proceeds − USDC spent buying BT; the
    ///      entry point's `minProfit` check is the authoritative gate.
    function _executeFixedPre(uint256 flashAmount, bytes calldata payload) internal {
        (
            MarketParams memory p,
            address borrower,
            uint256 seizedAssets,
            FixedPlan memory plan,
            uint256 snapshot
        ) = abi.decode(payload, (MarketParams, address, uint256, FixedPlan, uint256));

        address bt = p.loanToken;

        // 1. Approve fixed market to pull BT for the liquidation repay (≤ flashAmount).
        _safeApprove(bt, FIXED_MARKET, flashAmount);

        // 2. Liquidate: pulls BT, seizes PT. Empty `data` ⇒ no onLiquidate callback.
        (uint256 seizedActual, uint256 repaidActual) =
            ILendingMarket(FIXED_MARKET).liquidate(p, borrower, seizedAssets, 0, "");
        _safeApprove(bt, FIXED_MARKET, 0);

        // 3. Swap seized PT → USDC via the generic Pendle SwapPlan.
        uint256 usdcBeforePt = IERC20(USDC).balanceOf(address(this));
        _safeApprove(p.collateralToken, plan.ptToUsdc.router, seizedActual);
        (bool ok, bytes memory ret) = plan.ptToUsdc.router.call(plan.ptToUsdc.callData);
        if (!ok) {
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert SwapFailed();
        }
        _safeApprove(p.collateralToken, plan.ptToUsdc.router, 0);
        uint256 ptUsdcOut = IERC20(USDC).balanceOf(address(this)) - usdcBeforePt;
        if (ptUsdcOut < plan.ptToUsdc.minOut) revert SwapShortfall(ptUsdcOut, plan.ptToUsdc.minOut);

        // 4. Buy back the BT still owed for the flash, paying USDC on the Fira AMM.
        // After liquidate we hold `flashAmount - repaidActual` BT; we need
        // `flashAmount` total to repay, so we must acquire `repaidActual` more.
        uint256 btHeld = IERC20(bt).balanceOf(address(this));
        uint256 btNeeded = flashAmount > btHeld ? flashAmount - btHeld : 0;
        if (btNeeded > 0) {
            _safeApprove(USDC, FIRA_ROUTER, plan.btInput.netTokenIn);
            IFiraRouterV4(FIRA_ROUTER).swapExactTokenForBt(
                address(this), plan.ammMarket, btNeeded, plan.btApprox, plan.btInput, plan.btLimit
            );
            _safeApprove(USDC, FIRA_ROUTER, 0);
            uint256 btBought = IERC20(bt).balanceOf(address(this)) - btHeld;
            if (btBought < btNeeded) revert SwapShortfall(btBought, btNeeded);
        }

        // 5. Approve BT for the flash repay (market pulls flashAmount after return).
        _safeApprove(bt, FIXED_MARKET, flashAmount);

        // 6. Profit is in USDC: the BT flash repay doesn't touch the USDC balance.
        // currentBalance = snapshot + ptUsdcOut − usdcSpentBuyingBt.
        uint256 currentBalance = IERC20(USDC).balanceOf(address(this));
        if (currentBalance < snapshot) revert UnprofitableLiquidation(snapshot, currentBalance);
        uint256 expectedProfit = currentBalance - snapshot;
        emit Liquidated(1, FIXED_MARKET, borrower, seizedActual, repaidActual, expectedProfit);
    }

    // --- internal: fixed-rate post-maturity execution body (M2.5) ---

    /// @dev Runs inside `onFlashLoan` for `InFlightOp.FixedPost`. Flash token is
    /// BT; liquidation uses `liquidateExpiredBt` (market seizes collateral and
    /// computes the repaid BT internally — no `seizedAssets` input).
    ///
    /// CRITICAL difference from `_executeFixedPre`: post-maturity the Fira AMM is
    /// expired, so BT CANNOT be re-acquired via `swapExactTokenForBt` (it reverts
    /// `MarketExpired`). Instead we MINT BT from USDC via `mintBcFromToken`
    /// (USDC → FW → BT + CT), which is permitted post-maturity. The minted CT is
    /// a by-product left in the contract (evacuate via `withdraw`). `plan.btApprox`
    /// is unused on this path.
    function _executeFixedPost(uint256 flashAmount, bytes calldata payload) internal {
        (MarketParams memory p, address borrower, FixedPlan memory plan, uint256 snapshot) =
            abi.decode(payload, (MarketParams, address, FixedPlan, uint256));

        address bt = p.loanToken;

        // 1. Approve fixed market to pull BT for the post-maturity repay.
        _safeApprove(bt, FIXED_MARKET, flashAmount);

        // 2. liquidateExpiredBt: seizes collateral, pulls the internally-computed
        // repaidAssetsPaid BT. Empty `data` ⇒ no onLiquidate callback.
        (uint256 seizedActual, uint256 repaidActual) =
            ILendingMarket(FIXED_MARKET).liquidateExpiredBt(p, borrower, "");
        _safeApprove(bt, FIXED_MARKET, 0);

        // 3. Swap seized PT → USDC via the generic Pendle SwapPlan.
        uint256 usdcBeforePt = IERC20(USDC).balanceOf(address(this));
        _safeApprove(p.collateralToken, plan.ptToUsdc.router, seizedActual);
        (bool ok, bytes memory ret) = plan.ptToUsdc.router.call(plan.ptToUsdc.callData);
        if (!ok) {
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert SwapFailed();
        }
        _safeApprove(p.collateralToken, plan.ptToUsdc.router, 0);
        uint256 ptUsdcOut = IERC20(USDC).balanceOf(address(this)) - usdcBeforePt;
        if (ptUsdcOut < plan.ptToUsdc.minOut) revert SwapShortfall(ptUsdcOut, plan.ptToUsdc.minOut);

        // 4. MINT the BT still owed for the flash from USDC (post-maturity: the
        // AMM is expired, so we tokenize instead of swapping). Resolve the CT for
        // this market from the AMM, then mint BC (BT + CT) into this contract.
        uint256 btHeld = IERC20(bt).balanceOf(address(this));
        uint256 btNeeded = flashAmount > btHeld ? flashAmount - btHeld : 0;
        if (btNeeded > 0) {
            (,, address ct) = IFiraMarketTokens(plan.ammMarket).readTokens();
            _safeApprove(USDC, FIRA_ROUTER, plan.btInput.netTokenIn);
            IFiraRouterV4(FIRA_ROUTER).mintBcFromToken(address(this), ct, btNeeded, plan.btInput);
            _safeApprove(USDC, FIRA_ROUTER, 0);
            uint256 btMinted = IERC20(bt).balanceOf(address(this)) - btHeld;
            if (btMinted < btNeeded) revert SwapShortfall(btMinted, btNeeded);
        }

        // 5. Approve BT for the flash repay (market pulls flashAmount after return).
        _safeApprove(bt, FIXED_MARKET, flashAmount);

        // 6. Profit is in USDC (the BT flash repay doesn't touch the USDC balance).
        uint256 currentBalance = IERC20(USDC).balanceOf(address(this));
        if (currentBalance < snapshot) revert UnprofitableLiquidation(snapshot, currentBalance);
        emit Liquidated(2, FIXED_MARKET, borrower, seizedActual, repaidActual, currentBalance - snapshot);
    }

    /// @dev Fixed pre-maturity body for the Balancer flash path. Balancer pushed
    /// `amount` USDC up-front; we buy BT on the (still-live) AMM, liquidate, sell
    /// the seized PT → USDC, then repay `amount + fee` USDC to the vault.
    function _executeFixedPreBalancer(uint256 amount, uint256 fee, bytes calldata payload) internal {
        (MarketParams memory p, address borrower, uint256 seizedAssets, FixedPlan memory plan, uint256 snapshot) =
            abi.decode(payload, (MarketParams, address, uint256, FixedPlan, uint256));
        address bt = p.loanToken;

        // 1. Buy BT on the Fira AMM with the flashed USDC (pre-maturity: AMM live).
        uint256 btBefore = IERC20(bt).balanceOf(address(this));
        _safeApprove(USDC, FIRA_ROUTER, plan.btInput.netTokenIn);
        IFiraRouterV4(FIRA_ROUTER).swapExactTokenForBt(
            address(this), plan.ammMarket, plan.repaidAssets, plan.btApprox, plan.btInput, plan.btLimit
        );
        _safeApprove(USDC, FIRA_ROUTER, 0);
        uint256 btBought = IERC20(bt).balanceOf(address(this)) - btBefore;

        // 2. Liquidate with the BT we just bought; seize PT.
        _safeApprove(bt, FIXED_MARKET, btBought);
        (uint256 seizedActual, uint256 repaidActual) =
            ILendingMarket(FIXED_MARKET).liquidate(p, borrower, seizedAssets, 0, "");
        _safeApprove(bt, FIXED_MARKET, 0);

        // 3. Sell seized PT → USDC and repay the flash.
        uint256 currentBalance = _sellPtRepayBalancerAndAccount(p, plan, seizedActual, amount, fee, snapshot);
        emit Liquidated(1, FIXED_MARKET, borrower, seizedActual, repaidActual, currentBalance - snapshot);
    }

    /// @dev Fixed post-maturity body for the Balancer flash path. Same as
    /// `_executeFixedPreBalancer` but BT is MINTED from the flashed USDC
    /// (post-maturity the AMM is expired) and liquidation uses `liquidateExpiredBt`.
    function _executeFixedPostBalancer(uint256 amount, uint256 fee, bytes calldata payload) internal {
        (MarketParams memory p, address borrower, FixedPlan memory plan, uint256 snapshot) =
            abi.decode(payload, (MarketParams, address, FixedPlan, uint256));
        address bt = p.loanToken;

        // 1. Mint BT from the flashed USDC (post-maturity: AMM expired).
        (,, address ct) = IFiraMarketTokens(plan.ammMarket).readTokens();
        uint256 btBefore = IERC20(bt).balanceOf(address(this));
        _safeApprove(USDC, FIRA_ROUTER, plan.btInput.netTokenIn);
        IFiraRouterV4(FIRA_ROUTER).mintBcFromToken(address(this), ct, plan.repaidAssets, plan.btInput);
        _safeApprove(USDC, FIRA_ROUTER, 0);
        uint256 btMinted = IERC20(bt).balanceOf(address(this)) - btBefore;

        // 2. liquidateExpiredBt with the minted BT; seize PT.
        _safeApprove(bt, FIXED_MARKET, btMinted);
        (uint256 seizedActual, uint256 repaidActual) =
            ILendingMarket(FIXED_MARKET).liquidateExpiredBt(p, borrower, "");
        _safeApprove(bt, FIXED_MARKET, 0);

        // 3. Sell seized PT → USDC and repay the flash.
        uint256 currentBalance = _sellPtRepayBalancerAndAccount(p, plan, seizedActual, amount, fee, snapshot);
        emit Liquidated(2, FIXED_MARKET, borrower, seizedActual, repaidActual, currentBalance - snapshot);
    }

    /// @dev Shared tail for the fixed-rate Balancer paths: sell `ptAmount` of
    /// seized PT → USDC via the Pendle SwapPlan, repay `amount + fee` USDC to the
    /// Balancer vault, and return the post-repay USDC balance (asserting ≥ snapshot).
    function _sellPtRepayBalancerAndAccount(
        MarketParams memory p,
        FixedPlan memory plan,
        uint256 ptAmount,
        uint256 amount,
        uint256 fee,
        uint256 snapshot
    ) internal returns (uint256 currentBalance) {
        uint256 usdcBeforePt = IERC20(USDC).balanceOf(address(this));
        _safeApprove(p.collateralToken, plan.ptToUsdc.router, ptAmount);
        (bool ok, bytes memory ret) = plan.ptToUsdc.router.call(plan.ptToUsdc.callData);
        if (!ok) {
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert SwapFailed();
        }
        _safeApprove(p.collateralToken, plan.ptToUsdc.router, 0);
        uint256 ptUsdcOut = IERC20(USDC).balanceOf(address(this)) - usdcBeforePt;
        if (ptUsdcOut < plan.ptToUsdc.minOut) revert SwapShortfall(ptUsdcOut, plan.ptToUsdc.minOut);

        if (!IERC20(USDC).transfer(BALANCER_VAULT, amount + fee)) revert TransferFailed();

        currentBalance = IERC20(USDC).balanceOf(address(this));
        if (currentBalance < snapshot) revert UnprofitableLiquidation(snapshot, currentBalance);
    }

    /// @dev Wraps `IERC20.approve` to revert on `false` return.  v1 token set
    /// (USDC, BT, PT) all conform to the standard-`returns (bool)` ERC-20
    /// shape; adding USDT-style return-no-data tokens would require a different
    /// helper (the implicit `abi.decode(returndata, (bool))` would revert with
    /// a decoding error).
    function _safeApprove(address token, address spender, uint256 amount) internal {
        if (!IERC20(token).approve(spender, amount)) revert TransferFailed();
    }
}
