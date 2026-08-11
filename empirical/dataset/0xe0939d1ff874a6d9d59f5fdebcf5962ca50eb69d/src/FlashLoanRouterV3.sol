// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Aave V3
import {IPool} from "@aave/core-v3/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/interfaces/IPoolAddressesProvider.sol";

// Uniswap V3
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// OpenZeppelin
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Local
import {MainnetAddresses} from "./MainnetAddresses.sol";

/// @notice Minimal WETH9 interface — the canonical `IWETH9` in v3-periphery is
///         pinned to solc 0.7.6, so we redeclare here to stay on 0.8.20.
interface IWETH9Minimal {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/// @notice Balancer V2 Vault flash-loan surface used by v2/v3. Push-semantics
///         repayment: the recipient `transfer`s back `amounts[i] + feeAmounts[i]`
///         before returning from `receiveFlashLoan`; no approval required.
interface IBalancerVaultV2 {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

/// @title FlashLoanRouterV3 — V2 fork with immutable liquidator allowlist + PHY-127 length guards
/// @notice Phase 6 of docs/plans/multi_eoa_nonce_pool.md. A 1-for-1 fork of
///         FlashLoanRouterV2 with three load-bearing changes:
///
///           1. `executeLiquidation` is gated by `onlyLiquidator` instead of
///              `onlyOwner`. Auth checks 10 immutable EOAs (bytecode-embedded,
///              zero SLOAD) and finally an `extraLiquidator[s]` SLOAD only when
///              every immutable mismatches. Owner is NOT auto-whitelisted —
///              "right to execute" is decoupled from "right to admin".
///           2. New `setExtraLiquidator(eoa, authorized)` admin entrypoint
///              toggles the dynamic allowlist; emits `LiquidatorUpdated`.
///           3. PHY-127 length guards on BOTH swap legs: when `swapData` is
///              empty, skip the collateral→WETH leg entirely (no SLOAD on
///              `approvedSwapTargets[address(0)]`, no `.call(0x0)`). Symmetric
///              for the `bribeSwapData` leg. Restores the v1 invariant lost in
///              v2 that broke same-token (collateral==WETH or debt==WETH) paths.
///
///         All other admin functions (`setSwapTarget`, `batchApprove`,
///         `withdrawToken`, `withdrawETH`) remain `onlyOwner`-gated.
///
///         `receive()` MUST remain empty — WETH9.withdraw uses the 2300-gas
///         stipend; any SSTORE / non-trivial event here bricks the unwrap.
contract FlashLoanRouterV3 is IUniswapV3SwapCallback, Ownable {
    using SafeERC20 for IERC20;

    // ─── Immutables ──────────────────────────────────────────────────────

    IPool public immutable POOL;
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IUniswapV3Factory public immutable FACTORY;
    address public immutable WETH;
    /// @notice Balancer V2 Vault — flash-loan source.
    address public immutable VAULT;

    // 10 immutable liquidator slots — burned into bytecode, no SLOAD on the
    // happy path. Plan §3 Step 6.1 sets pool size = 10 (PHY-137 target).
    address public immutable liquidator0;
    address public immutable liquidator1;
    address public immutable liquidator2;
    address public immutable liquidator3;
    address public immutable liquidator4;
    address public immutable liquidator5;
    address public immutable liquidator6;
    address public immutable liquidator7;
    address public immutable liquidator8;
    address public immutable liquidator9;

    // ─── Self-imposed safety bounds ──────────────────────────────────────

    /// @notice Sanity cap on the flash-loan fee Balancer passes via feeAmounts.
    ///         Balancer's protocol-level max is 1e16 (100 bps); we enforce 5 bps
    ///         (5e14) to catch governance fee changes before they harm us.
    uint256 public constant MAX_FLASH_LOAN_FEE_BPS_SCALED_1E18 = 5e14;

    // ─── Transient-storage slots ─────────────────────────────────────────

    /// @dev Transient slot storing 1 while a router-initiated flash loan is in
    ///      flight; checked inside `receiveFlashLoan` to block attackers who
    ///      would point a Vault-initiated flash loan at this contract.
    uint256 private constant _FLIGHT_SLOT = 0;

    // ─── State ───────────────────────────────────────────────────────────

    mapping(address => bool) public approvedSwapTargets;

    /// @notice Optional dynamic liquidator allowlist. SLOAD-gated, so the
    ///         `onlyLiquidator` modifier checks it LAST — Solidity short-circuits
    ///         `&&`, so the SLOAD is paid only when every immutable mismatches.
    ///         Plan §3 Step 6.1.
    mapping(address => bool) public extraLiquidator;

    // ─── Events ──────────────────────────────────────────────────────────

    event SwapTargetUpdated(address indexed target, bool approved);
    event LiquidationExecuted(
        address indexed debtAsset,
        address indexed collateralAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 profitWETH
    );
    event LiquidatorUpdated(address indexed eoa, bool authorized);

    // ─── Errors ──────────────────────────────────────────────────────────

    error CallerNotVault();
    error InitiatorNotSelf();
    error UnapprovedSwapTarget(address target);
    error SwapFailed();
    error InsufficientProfit(uint256 actualWETH, uint256 minimumWETH);
    error BuilderTipFailed();
    error InvalidPool();
    error NativeTransferFailed();
    error ExcessiveFlashLoanFee(uint256 actual, uint256 cap);
    error UnauthorizedLiquidator(address caller);

    // ─── Constructor ─────────────────────────────────────────────────────

    constructor(address admin, address[10] memory pool_) Ownable(admin) {
        POOL = IPool(MainnetAddresses.AAVE_V3_POOL);
        ADDRESSES_PROVIDER = IPoolAddressesProvider(MainnetAddresses.AAVE_V3_ADDRESSES_PROVIDER);
        WETH = MainnetAddresses.WETH;
        FACTORY = IUniswapV3Factory(MainnetAddresses.UNISWAP_V3_FACTORY);
        VAULT = MainnetAddresses.BALANCER_V2_VAULT;

        liquidator0 = pool_[0];
        liquidator1 = pool_[1];
        liquidator2 = pool_[2];
        liquidator3 = pool_[3];
        liquidator4 = pool_[4];
        liquidator5 = pool_[5];
        liquidator6 = pool_[6];
        liquidator7 = pool_[7];
        liquidator8 = pool_[8];
        liquidator9 = pool_[9];
    }

    /// @notice MUST remain empty — WETH9.withdraw uses the 2300-gas stipend.
    ///         Any SSTORE / non-trivial event here bricks the bribe path.
    receive() external payable {}

    function renounceOwnership() public view override onlyOwner {
        revert("renounceOwnership disabled");
    }

    // ─── Modifiers ───────────────────────────────────────────────────────

    /// @dev Liquidator gate. Short-circuits on the 10 bytecode-embedded
    ///      immutable equality checks; only when every immutable mismatches
    ///      do we pay the SLOAD on `extraLiquidator[msg.sender]`. On the
    ///      happy path (caller is `liquidator0`) we pay only one PUSH+EQ
    ///      pair — strictly cheaper than V2's `Ownable._owner` SLOAD.
    modifier onlyLiquidator() {
        address s = msg.sender;
        if (
            s != liquidator0 &&
            s != liquidator1 &&
            s != liquidator2 &&
            s != liquidator3 &&
            s != liquidator4 &&
            s != liquidator5 &&
            s != liquidator6 &&
            s != liquidator7 &&
            s != liquidator8 &&
            s != liquidator9 &&
            !extraLiquidator[s]
        ) {
            revert UnauthorizedLiquidator(s);
        }
        _;
    }

    // ─── Entry Point (NON-payable) ────────────────────────────────────────

    /// @notice Execute a Balancer-flash-loan-funded Aave V3 liquidation with
    ///         WETH-denominated profit and a self-funded builder tip.
    /// @param debtAsset         Token Balancer lends us; used to repay the liquidation.
    /// @param collateralAsset   Collateral seized from the liquidated user.
    /// @param user              Address being liquidated.
    /// @param debtToCover       Debt amount to repay (Aave caps at close factor).
    /// @param swapData          Calldata for the collateral→WETH swap. When
    ///                          empty, the collateral→WETH leg is skipped
    ///                          (PHY-127 same-token shape — used when
    ///                          `collateralAsset == WETH`).
    /// @param swapTarget        Whitelisted DEX for collateral→WETH. Ignored
    ///                          when `swapData` is empty.
    /// @param bribeSwapData     Calldata for the WETH→debtAsset exactOutput swap,
    ///                          sized to produce EXACTLY `amounts[0] + feeAmounts[0]`
    ///                          debtAsset (the flash-loan repayment quantity).
    ///                          When empty, the WETH→debt leg is skipped
    ///                          (PHY-127 same-token shape — used when
    ///                          `debtAsset == WETH`).
    /// @param bribeSwapTarget   Whitelisted DEX for WETH→debtAsset. Ignored
    ///                          when `bribeSwapData` is empty.
    /// @param minProfitWETH     Floor on post-tip WETH balance; revert if below.
    /// @param builderTipWETH    WETH amount to unwrap and pay `block.coinbase`.
    function executeLiquidation(
        address debtAsset,
        address collateralAsset,
        address user,
        uint256 debtToCover,
        bytes calldata swapData,
        address swapTarget,
        bytes calldata bribeSwapData,
        address bribeSwapTarget,
        uint256 minProfitWETH,
        uint256 builderTipWETH
    ) external onlyLiquidator {
        _initiateFlashLoan(
            debtAsset,
            collateralAsset,
            user,
            debtToCover,
            swapData,
            swapTarget,
            bribeSwapData,
            bribeSwapTarget
        );

        // Post-flash-loan: collateral→WETH and WETH→debt-repay have run, and
        // the flash loan has been repaid to VAULT. Everything left on the
        // contract is WETH (profit + builder tip).
        _settleTipAndEmit(debtAsset, collateralAsset, user, debtToCover, minProfitWETH, builderTipWETH);
    }

    /// @dev Split out to contain stack pressure vs the 10-arg `executeLiquidation`.
    function _initiateFlashLoan(
        address debtAsset,
        address collateralAsset,
        address user,
        uint256 debtToCover,
        bytes calldata swapData,
        address swapTarget,
        bytes calldata bribeSwapData,
        address bribeSwapTarget
    ) private {
        bytes memory userData = abi.encode(
            collateralAsset,
            user,
            debtToCover,
            swapData,
            swapTarget,
            bribeSwapData,
            bribeSwapTarget
        );

        // Single-token flash-loan shape: v3 NEVER produces a multi-token loan.
        address[] memory tokens = new address[](1);
        tokens[0] = debtAsset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtToCover;

        // Mark flight: receiveFlashLoan asserts tload(_FLIGHT_SLOT) == 1, so
        // an attacker cannot point a Vault-initiated flash loan at this
        // contract to trigger the liquidation flow with attacker-chosen
        // userData. Transient storage auto-clears on tx end, but we also
        // clear explicitly post-call as a belt-and-suspenders invariant.
        assembly {
            tstore(_FLIGHT_SLOT, 1)
        }

        IBalancerVaultV2(VAULT).flashLoan(address(this), tokens, amounts, userData);

        assembly {
            tstore(_FLIGHT_SLOT, 0)
        }
    }

    /// @dev Profit floor, WETH→ETH unwrap, coinbase tip, event emit. Split
    ///      out to keep `executeLiquidation`'s stack frame small.
    function _settleTipAndEmit(
        address debtAsset,
        address collateralAsset,
        address user,
        uint256 debtToCover,
        uint256 minProfitWETH,
        uint256 builderTipWETH
    ) private {
        uint256 wethBal = IERC20(WETH).balanceOf(address(this));

        // Profit check BEFORE unwrap/tip. coinbase MUST NOT be tipped on this
        // revert path, AND no ETH may linger on the contract (so the withdraw
        // cannot have happened).
        uint256 requiredWETH = builderTipWETH + minProfitWETH;
        if (wethBal < requiredWETH) {
            revert InsufficientProfit(wethBal, requiredWETH);
        }

        // Unwrap only the tip slice — remaining WETH stays as profit.
        if (builderTipWETH > 0) {
            IWETH9Minimal(WETH).withdraw(builderTipWETH);
            // forge-lint: disable-next-line(avoid-low-level-calls)
            (bool ok,) = block.coinbase.call{value: builderTipWETH}("");
            if (!ok) revert BuilderTipFailed();
        }

        uint256 profitWETH;
        unchecked { profitWETH = wethBal - builderTipWETH; }
        emit LiquidationExecuted(debtAsset, collateralAsset, user, debtToCover, profitWETH);
    }

    // ─── Balancer V2 Flash-Loan Callback ─────────────────────────────────

    /// @dev Memory struct to hold the 7 fields decoded from userData inside
    ///      `receiveFlashLoan`. Using a struct pointer instead of 7 separate
    ///      locals cuts the live-variable count in that frame enough to avoid
    ///      the stack-too-deep error the legacy flat layout produced.
    struct LiquidationParams {
        address collateralAsset;
        address user;
        uint256 debtToCover;
        bytes   swapData;
        address swapTarget;
        bytes   bribeSwapData;
        address bribeSwapTarget;
    }

    /// @notice Balancer V2 Vault callback. MUST be invoked only by the Vault
    ///         and only while a flight initiated by `executeLiquidation` is
    ///         in progress (enforced via transient-storage flag).
    /// @dev    Order of checks is load-bearing:
    ///         1. auth (msg.sender == VAULT) — cheapest gate
    ///         2. fee cap — fee-cap test invokes this with empty userData,
    ///            so fee check MUST precede decode.
    ///         3. initiator guard — after fee check so the fee test still sees
    ///            ExcessiveFlashLoanFee, but before any state-changing work.
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        // (1) Auth
        if (msg.sender != VAULT) revert CallerNotVault();

        // (2) Fee cap — run before userData decode so the fee-cap test (which
        //     intentionally passes empty userData) sees this selector and not
        //     a decoder revert.
        uint256 tokenCount = amounts.length;
        for (uint256 i; i < tokenCount;) {
            uint256 cap = (amounts[i] * 5) / 10_000;
            if (feeAmounts[i] > cap) {
                revert ExcessiveFlashLoanFee(feeAmounts[i], cap);
            }
            unchecked { ++i; }
        }

        // (3) Initiator guard — only accept Vault calls triggered by our own
        //     `executeLiquidation`. An attacker calling the Vault directly
        //     with this contract as recipient would pass (1)+(2) but fail here.
        uint256 flight;
        assembly {
            flight := tload(_FLIGHT_SLOT)
        }
        if (flight != 1) revert InitiatorNotSelf();

        // (4) Decode the 7-tuple produced by executeLiquidation into a struct
        //     to keep this frame's live-variable count below the EVM limit.
        LiquidationParams memory p;
        (
            p.collateralAsset,
            p.user,
            p.debtToCover,
            p.swapData,
            p.swapTarget,
            p.bribeSwapData,
            p.bribeSwapTarget
        ) = abi.decode(
            userData,
            (address, address, uint256, bytes, address, bytes, address)
        );

        // (5)-(8) Delegate to helper; pass the struct pointer + the three
        //         flash-loan quantities (debt asset, borrowed amount, fee).
        _runLiquidationBody(address(tokens[0]), amounts[0], feeAmounts[0], p);
    }

    /// @dev Performs steps 5-8 of the flash-loan callback: liquidate, swap
    ///      collateral→WETH, swap WETH→debt, repay Balancer. Extracted from
    ///      `receiveFlashLoan` solely to reduce its stack depth.
    ///
    ///      PHY-127 fix: each swap leg is wrapped in `if (length > 0)` so a
    ///      same-token shape (`collateralAsset == WETH` or `debtAsset == WETH`)
    ///      can be expressed via empty bytes + `address(0)` target without
    ///      triggering the unwhitelisted-target revert or a `.call(0x0)`.
    function _runLiquidationBody(
        address debtAsset,
        uint256 flashAmount,
        uint256 flashFee,
        LiquidationParams memory p
    ) private {
        // (5) Liquidate on Aave V3. Debt-token approval to POOL was set at
        //     `batchApprove`; POOL pulls debt and sends collateral + bonus.
        POOL.liquidationCall(p.collateralAsset, debtAsset, p.user, p.debtToCover, false);

        // (6) Swap collateral → WETH (skip if same asset, i.e. collateral==WETH).
        if (p.swapData.length > 0) {
            if (!approvedSwapTargets[p.swapTarget]) revert UnapprovedSwapTarget(p.swapTarget);
            // forge-lint: disable-next-line(avoid-low-level-calls)
            (bool okSwap,) = p.swapTarget.call(p.swapData);
            if (!okSwap) revert SwapFailed();
        }

        // (7) Swap WETH → debt exactOutput (skip if same asset, i.e. debt==WETH).
        //     When the swap target is Balancer's Vault itself (reentrancy
        //     misconfig test), the Vault's nonReentrant guard rejects the
        //     nested call — no special handling needed here.
        if (p.bribeSwapData.length > 0) {
            if (!approvedSwapTargets[p.bribeSwapTarget]) revert UnapprovedSwapTarget(p.bribeSwapTarget);
            // forge-lint: disable-next-line(avoid-low-level-calls)
            (bool okBribe,) = p.bribeSwapTarget.call(p.bribeSwapData);
            if (!okBribe) revert SwapFailed();
        }

        // (8) Push-semantics repayment. Balancer checks its own balanceOf
        //     delta; no approval path exists.
        IERC20(debtAsset).safeTransfer(VAULT, flashAmount + flashFee);
    }

    // ─── Uniswap V3 Direct Pool Swap Callback (unchanged from v1) ────────

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        (address tokenIn, address tokenOut, uint24 fee) = abi.decode(
            data,
            (address, address, uint24)
        );

        address expectedPool = address(FACTORY.getPool(tokenIn, tokenOut, fee));
        if (expectedPool == address(0) || msg.sender != expectedPool) {
            revert InvalidPool();
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountToPay = amount0Delta > 0
            ? uint256(amount0Delta)
            // forge-lint: disable-next-line(unsafe-typecast)
            : uint256(amount1Delta);
        IERC20(tokenIn).safeTransfer(msg.sender, amountToPay);
    }

    // ─── Admin: Swap Target Whitelist ────────────────────────────────────

    function setSwapTarget(address target, bool approved) external onlyOwner {
        approvedSwapTargets[target] = approved;
        emit SwapTargetUpdated(target, approved);
    }

    // ─── Admin: Batch Token Approvals ────────────────────────────────────

    /// @notice Pre-approve tokens to the Aave Pool and each swap target.
    /// @dev Balancer V2 Vault uses push-semantics for flash-loan repayment
    ///      (recipient `transfer`s back), so NO approval to VAULT is required
    ///      for the repay path. Approvals to POOL are still needed for
    ///      `POOL.liquidationCall`.
    function batchApprove(
        address[] calldata tokens,
        address[] calldata targets
    ) external onlyOwner {
        uint256 tokenLen = tokens.length;
        uint256 targetLen = targets.length;

        for (uint256 i; i < tokenLen;) {
            IERC20 token = IERC20(tokens[i]);
            token.forceApprove(address(POOL), type(uint256).max);
            for (uint256 j; j < targetLen;) {
                token.forceApprove(targets[j], type(uint256).max);
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    // ─── Admin: Dynamic liquidator allowlist (Phase 6 NEW) ───────────────

    /// @notice Toggle an EOA's `extraLiquidator` flag. Owner-only — liquidator
    ///         status grants only the right to call `executeLiquidation`, never
    ///         the right to mutate the allowlist.
    /// @param eoa        Address whose dynamic liquidator status is being toggled.
    /// @param authorized True to grant `executeLiquidation` rights, false to revoke.
    function setExtraLiquidator(address eoa, bool authorized) external onlyOwner {
        extraLiquidator[eoa] = authorized;
        emit LiquidatorUpdated(eoa, authorized);
    }

    // ─── Emergency: Token & ETH Recovery ─────────────────────────────────

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert NativeTransferFailed();
    }
}
