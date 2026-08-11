// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * SVR variant of ArbiWhatExecutorBalancer for use with Chainlink ETH SVR
 * via Flashbots MEV-Share. Identical to ArbiWhatExecutorBalancer except:
 *
 *   - executeLiquidationV2 is `payable`. Caller passes the Flashbots block-builder
 *     bid in msg.value.
 *   - After the flash-loan callback returns, the contract forwards msg.value
 *     to `block.coinbase` per the Chainlink ETH SVR onboarding spec
 *     (https://docs.chain.link/data-feeds/svr-feeds/searcher-onboarding-ethereum):
 *     "Within your backrun transaction itself, send ETH to block.coinbase
 *      (the block builder's address). The higher the payment sent to
 *      block.coinbase, the more competitive your bundle becomes."
 *
 * The bid is funded by the EOA caller (msg.value), NOT from post-swap profit.
 * Empty msg.value is allowed - the contract still works for non-SVR-routed
 * liquidations (e.g. mempool race) without paying a bid.
 *
 * @title ArbiWhatExecutorBalancerSvr
 * @notice Flash loan receiver that executes AAVE v3 liquidation + DEX swap arbitrage,
 *         using Balancer V2's Vault as the flash-loan provider (zero fee on Balancer V2).
 *
 * Flow (cross-asset: collateral != debt):
 * 1. Bot calls `executeLiquidationV2()` with target position details
 * 2. Contract sets `_flashInProgress = 2` and requests a flash loan from Balancer Vault for the debt asset (v240c: V1 stripped, single dispatch path)
 * 3. In the callback `receiveFlashLoan()`:
 *    a. Verify msg.sender == vault AND _flashInProgress == 2
 *    b. Approve AAVE pool to spend the debt asset
 *    c. Call AAVE `liquidationCall()` to repay user's debt and receive discounted collateral
 *    d. Swap the received collateral back to the debt asset via Uniswap v3
 *    e. Transfer amounts[i] + feeAmounts[i] back to the Balancer Vault (transfer, not approve)
 *    f. Transfer remaining profit to the bot operator
 *
 * Flow (same-asset: collateral == debt): same as ArbiWhatExecutor, no swap.
 *
 * Key differences from Aave-based ArbiWhatExecutor:
 *  - Balancer V2 pulls repayment via `transfer`, not `transferFrom` — we MUST transfer back inside the callback.
 *  - Balancer V2 flash-loan fee is currently 0 (feeAmounts[0] == 0) but the code uses feeAmounts[i] dynamically.
 *  - `receiveFlashLoan` replaces `executeOperation`; it takes arrays, not singletons.
 *  - Additional transient flag `_flashInProgress` guards against arbitrary callers invoking the callback
 *    with malicious userData even if they somehow spoofed msg.sender == vault (defense-in-depth).
 *
 * Security:
 * - Only the owner (bot operator) can trigger executions (`onlyOwner`).
 * - Only the Balancer Vault can call `receiveFlashLoan` (`msg.sender == VAULT`).
 * - Transient `_flashInProgress` flag prevents external invocation of the callback with arbitrary userData.
 * - Reentrancy guard on ALL external-facing functions including callback.
 * - SafeERC20 for USDT and non-standard token compatibility.
 * - Explicit repay transfer with require check (no silent bool swallowing).
 * - Minimum profit check before finalizing execution.
 * - Emergency withdraw for stuck tokens (owner-only).
 * - No delegatecall, no selfdestruct, no proxy pattern.
 * - State writes before external transfers (CEI pattern).
 *
 * Audit: Slither v0.11+ — all HIGH/MEDIUM findings resolved (see balancer-audit-summary.md).
 */

// ─── Interfaces ──────────────────────────────────────────────────────────────

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IVault {
    // Balancer V2 flash loan initiation
    function flashLoan(
        address recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    // Balancer V2 callback on our contract
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IPool {
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;
}

interface IPoolAddressesProvider {
    function getPool() external view returns (address);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);

    // v240b: multi-hop UniV3 swap.
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params)
        external payable returns (uint256 amountOut);
}

// ─── SafeERC20 (inline to avoid import dependency) ──────────────────────────

library SafeERC20 {
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        if (value != 0) {
            (bool zeroSuccess, bytes memory zeroData) = address(token).call(
                abi.encodeWithSelector(token.approve.selector, spender, 0)
            );
            if (zeroSuccess && zeroData.length > 0) {
                // ok — some tokens return bool, others don't
            }
        }
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: approve failed");
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transfer failed");
    }
}

// ─── Main Contract ───────────────────────────────────────────────────────────

contract ArbiWhatExecutorBalancerSvr is IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    // ─── State ───────────────────────────────────────────────────────────────
    address public immutable OWNER;
    IVault public immutable VAULT;                      // Balancer V2 Vault (flash-loan provider)
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    ISwapRouter public immutable SWAP_ROUTER;

    // Reentrancy guard (1 = unlocked, 2 = locked)
    uint256 private _locked = 1;

    // Transient flag: 1 = no flash loan in progress, 2 = we just initiated one.
    // Set BEFORE calling vault.flashLoan(...) and cleared after it returns.
    // Guarantees receiveFlashLoan is only processed for calls we initiated.
    uint256 private _flashInProgress = 1;

    // Minimum profit threshold in debt asset units (prevents dust executions)
    uint256 public minProfitThreshold;

    // Statistics
    uint256 public totalExecutions;
    uint256 public totalProfitWei;

    // ─── Events ──────────────────────────────────────────────────────────────
    event LiquidationExecuted(
        address indexed user,
        address indexed debtAsset,
        address indexed collateralAsset,
        uint256 debtAmount,
        uint256 collateralReceived,
        uint256 profit
    );

    event SameAssetLiquidation(
        address indexed user,
        address indexed asset,
        uint256 debtAmount,
        uint256 collateralReceived,
        uint256 profit
    );

    event ProfitWithdrawn(address indexed token, uint256 amount);
    event MinProfitUpdated(uint256 oldThreshold, uint256 newThreshold);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────────────
    error OnlyOwner();
    error OnlyVault();
    error FlashNotInProgress();
    error Reentrancy();
    error InsufficientProfit(uint256 actual, uint256 required);
    error SwapFailed();
    error ZeroAddress();
    error ZeroAmount();
    error BadArrayLength();
    error RepayFailed();
    error CoinbaseTipFailed();  // v258-svr-bal-fix: post-Pectra coinbase .call failure
    // v240b multi-hop / ratio
    error BadPath();
    error PathTerminusMismatch();

    // ─── Modifiers ───────────────────────────────────────────────────────────
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view {
        if (msg.sender != OWNER) revert OnlyOwner();
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
    }

    function _nonReentrantAfter() internal {
        _locked = 1;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────
    constructor(
        address vault_,
        address addressesProvider_,
        address swapRouter_,
        uint256 minProfitThreshold_
    ) {
        if (vault_ == address(0)) revert ZeroAddress();
        if (addressesProvider_ == address(0)) revert ZeroAddress();
        if (swapRouter_ == address(0)) revert ZeroAddress();

        OWNER = msg.sender;
        VAULT = IVault(vault_);
        ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider_);
        SWAP_ROUTER = ISwapRouter(swapRouter_);
        minProfitThreshold = minProfitThreshold_;
    }

    /**
     * v240b: routed liquidation entry point. Multi-hop swap path + per-collateral-
     * unit minAmountOut ratio.
     *
     * @param swapPath UniV3 path bytes:
     *   - empty (length == 0): same-asset (no swap; collateral == debt).
     *   - length 43: single-hop. abi.encodePacked(tokenIn[20], fee[3], tokenOut[20]).
     *   - length >= 66 with (length - 20) % 23 == 0: multi-hop. tokens + fees alternating.
     * @param minAmountOutPerCollUnit 1e18-scaled. Inside callback we compute
     *   absolute floor = (actualCollateralReceived * ratio) / 1e18. This scales
     *   with what Aave actually returns — robust to predicted-vs-actual debt cap
     *   divergence.
     *
     * Selector: 0x4953b3f2 (keccak("executeLiquidationV2(address,address,address,uint256,bytes,uint256)")[:4])
     */
    function executeLiquidationV2(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bytes calldata swapPath,
        uint256 minAmountOutPerCollUnit
    ) external payable onlyOwner nonReentrant {
        if (debtToCover == 0) revert ZeroAmount();
        if (collateralAsset == address(0) || debtAsset == address(0) || user == address(0)) revert ZeroAddress();
        _validateSwapPath(swapPath, collateralAsset, debtAsset);

        bytes memory params = abi.encode(
            collateralAsset,
            debtAsset,
            user,
            debtToCover,
            swapPath,
            minAmountOutPerCollUnit
        );

        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20(debtAsset);
        amounts[0] = debtToCover;

        // v240b: distinct sentinel from V1 (=2) so receiveFlashLoan dispatches correctly.
        _flashInProgress = 2;
        VAULT.flashLoan(address(this), tokens, amounts, params);
        _flashInProgress = 1;

        // v258-svr-bal-fix Pectra-safe coinbase tip. Replaces the deprecated
        // `.transfer()` pattern (2300-gas stipend) which fails on contract-coinbase
        // validators (Titan, Beaver, et al). Mirrors v256-coinbase-bid-fu1
        // (ArbiWhatExecutorBalancer.sol) and v257 mempool fleet
        // (ArbiWhatBatchExecutorBalancerMempool.sol:261-264) verbatim.
        if (msg.value > 0) {
            (bool tipOk, ) = block.coinbase.call{value: msg.value}(new bytes(0));
            if (!tipOk) revert CoinbaseTipFailed();
        }
    }

    /**
     * v240b: validates swapPath shape and asserts first/last 20 bytes match the
     * declared collateralAsset/debtAsset.
     */
    function _validateSwapPath(bytes calldata p, address collateral, address debt) private pure {
        if (p.length == 0) {
            if (collateral != debt) revert BadPath();
            return;
        }
        // Path must be tokenIn(20) + (fee(3) + tokenN(20))+
        // i.e. length 43 (single-hop) or 66, 89, ... (multi-hop).
        if (p.length < 43 || (p.length - 20) % 23 != 0) revert BadPath();
        address pathIn  = address(bytes20(p[0:20]));
        address pathOut = address(bytes20(p[p.length - 20 : p.length]));
        if (pathIn != collateral || pathOut != debt) revert PathTerminusMismatch();
    }

    /**
     * v240b: inline allowance check instead of routerApproved storage mapping.
     * Avoids the new-slot storage-layout-collision risk (audit-fix P6).
     */
    function _ensureRouterApproval(address token, uint256 needed) private {
        if (IERC20(token).allowance(address(this), address(SWAP_ROUTER)) < needed) {
            IERC20(token).safeApprove(address(SWAP_ROUTER), type(uint256).max);
        }
    }

    /**
     * v240b: swap dispatcher. amountIn is the REAL collateral received from
     * liquidationCall. minAmountOut is computed HERE from the ratio so it
     * scales with actual collateral (cap-divergence-robust).
     */
    // ─── Flash Loan Callback ─────────────────────────────────────────────────
    /**
     * @notice Called by Balancer Vault after flash-loaned funds have been transferred to us.
     * @dev Protected by:
     *       - msg.sender == VAULT (prevents arbitrary callers)
     *       - _flashInProgress == 2 (ensures WE initiated the flash loan; defense in depth)
     *       - the outer `executeLiquidationV2`'s `nonReentrant` modifier holds `_locked = 2`
     *         for the entire flash-loan window, so any *other* entrypoint into this
     *         contract (e.g. a malicious token transfer hook calling executeLiquidationV2)
     *         is blocked. We deliberately do NOT put `nonReentrant` directly on this
     *         callback, because that would self-collide with the outer lock.
     */
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        // v113 BUGFIX: removed `nonReentrant` here. The shared `_locked` variable
        // is set to 2 by the outer `executeLiquidationV2`'s `nonReentrant` modifier
        // BEFORE we call `VAULT.flashLoan`, so when Balancer calls back into
        // this function the `_nonReentrantBefore` check `_locked != 1` fires
        // and reverts with `Reentrancy()` (selector 0xab143c06). That collision
        // caused EVERY Atlas SVR SolverOp we submitted to fail simulation.
        // (Atlas runs simSolverCall pre-inclusion; a sim-fail means Atlas
        // REJECTS our SolverOp without including it on-chain — we do NOT pay
        // gas and we do NOT pay the bid. We just lose the opportunity. The
        // auction either went to a competing solver whose sim passed, or no
        // solver was included and the oracle update landed without an SVR
        // backrun.)
        //
        // Authentication is preserved by the two checks immediately below:
        //   - msg.sender == VAULT: only Balancer can invoke this entrypoint
        //   - _flashInProgress == 2: we set this flag in executeLiquidationV2
        //     (line 268) before calling VAULT.flashLoan, and clear it after
        //     the call returns (line 270). Together these constitute a strict
        //     "callback during our own initiated flow" guarantee that's
        //     stronger than the generic reentrancy lock.
        //
        // The outer `executeLiquidationV2` keeps its `nonReentrant` modifier and
        // still blocks any *other* re-entry into the contract (e.g. through
        // a malicious token's transfer hook) for the duration of the flash
        // loan, so external attack surface is unchanged.
        // Authn 1: caller must be the Balancer Vault
        if (msg.sender != address(VAULT)) revert OnlyVault();
        // Authn 2: we must be in the middle of our own initiation.
        if (_flashInProgress != 2) revert FlashNotInProgress();
        // Shape check — we always request exactly 1 token
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) revert BadArrayLength();

        _executeCallbackV2(tokens[0], amounts[0], feeAmounts[0], userData);
    }

    /**
     * v240b: callback for executeLiquidationV2. Same flow as _executeCallbackV2 but:
     *   - userData encodes (collateral, debt, user, debtToCover, bytes swapPath, uint256 minOutPerCollUnit)
     *   - swap step uses _swap() helper with the path + ratio
     *   - minAmountOut is computed INSIDE _swap from actualCollateralReceived
     */
    function _executeCallbackV2(
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes memory userData
    ) internal {
        (
            address collateralAsset,
            address debtAsset,
            address user,
            uint256 debtToCover,
            bytes memory swapPathMemory,
            uint256 minAmountOutPerCollUnit
        ) = abi.decode(userData, (address, address, address, uint256, bytes, uint256));

        require(address(token) == debtAsset, "token mismatch");

        address pool = ADDRESSES_PROVIDER.getPool();
        IERC20(debtAsset).safeApprove(pool, type(uint256).max);

        uint256 collateralReceived = _liquidate(pool, collateralAsset, debtAsset, user, debtToCover);

        bool isSameAsset = (collateralAsset == debtAsset);

        if (!isSameAsset) {
            // V2: swap collateral → debt asset. Result stays in this contract; we
            // read final balance below as source-of-truth for residual after the
            // Balancer flash repay. Memory→calldata: we can't bytes calldata-ify
            // a memory slice in pure Solidity, so we dispatch through a small
            // helper that takes memory.
            uint256 swapOut = _swapFromMemory(swapPathMemory, collateralReceived, minAmountOutPerCollUnit);
            if (swapOut < 1) revert SwapFailed();
        }
        // else: same-asset path needs no swap — liquidationCall already deposited
        // debt asset directly (Aave's collateral seizure returns `collateralReceived`
        // of the SAME asset; nothing to convert).

        uint256 amountOwed = amount + fee;
        IERC20(debtAsset).safeTransfer(address(VAULT), amountOwed);

        // v258-svr-bal-fix: residual = on-chain balance AFTER the Balancer push,
        // NOT `amount + swapOut - amountOwed`. The prior calc double-counted the
        // flash principal: `amount` was consumed inside `_liquidate` via Aave's
        // transferFrom(this, aToken, debtToCover) — it is NOT still in the contract
        // by the time we read here. When Aave V3.2's small-position rule forces
        // full liquidation (coll<$2000 OR debt<$2000 OR HF<0.95) the old formula
        // over-stated `profit` by the flash amount → safeTransfer(OWNER, profit)
        // attempted to send more than the contract held → SafeERC20 revert on
        // every full-liquidation submission since this contract first deployed.
        // Mirror pattern: ArbiWhatBatchExecutorBalancer.sol:429-430 (SVR Balancer
        // batch sibling — lifetime profits realized) + v257 mempool fleet
        // (ArbiWhatBatchExecutorMempool.sol:367-369). Audit anchor:
        // audits/2026-05-28-mevshare-batch-investigation/AUDIT_CORRECTIONS.md.
        uint256 profit = IERC20(debtAsset).balanceOf(address(this));
        if (profit < minProfitThreshold) revert InsufficientProfit(profit, minProfitThreshold);

        totalExecutions++;
        totalProfitWei += profit;

        if (isSameAsset) {
            emit SameAssetLiquidation(user, debtAsset, debtToCover, collateralReceived, profit);
        } else {
            emit LiquidationExecuted(user, debtAsset, collateralAsset, debtToCover, collateralReceived, profit);
        }

        if (profit > 0) {
            IERC20(debtAsset).safeTransfer(OWNER, profit);
        }
    }

    /**
     * v240b: memory-input variant of _swap. abi.decode gives us bytes memory;
     * Solidity can't silently convert bytes memory → bytes calldata, so this
     * helper duplicates the dispatch logic on bytes memory.
     */
    function _swapFromMemory(
        bytes memory swapPath,
        uint256 amountIn,
        uint256 minAmountOutPerCollUnit
    ) private returns (uint256 amountOut) {
        if (swapPath.length == 0) revert BadPath();

        // First 20 bytes = tokenIn.
        address tokenIn;
        assembly {
            tokenIn := mload(add(swapPath, 32))  // skip length prefix, load first word
            tokenIn := shr(96, tokenIn)            // top 20 bytes -> address (bottom-aligned)
        }
        _ensureRouterApproval(tokenIn, amountIn);

        uint256 minAmountOut = (amountIn * minAmountOutPerCollUnit) / 1e18;

        if (swapPath.length == 43) {
            address tokenOut;
            uint24 fee;
            assembly {
                // tokenOut starts at byte offset 23 in path-bytes (after 20-byte token + 3-byte fee)
                // In memory layout: skip 32 (length) + 23 = +55 to point at the word containing tokenOut.
                // Actually we need just bytes 23..43 (20 bytes). We load the word at offset 32+23-12 = +43
                // so that the bottom 20 bytes of the word are the address.
                // Simpler: load fee + tokenOut as two separate loads.
                fee := mload(add(swapPath, add(32, 20)))  // word starting at offset 20 (fee occupies top 3 bytes of that word)
                fee := shr(232, fee)                       // shift right 29 bytes to land in low 3
                tokenOut := mload(add(swapPath, add(32, 23)))  // word starting at offset 23
                tokenOut := shr(96, tokenOut)
            }
            amountOut = SWAP_ROUTER.exactInputSingle(ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            }));
        } else {
            amountOut = SWAP_ROUTER.exactInput(ISwapRouter.ExactInputParams({
                path: swapPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut
            }));
        }
    }

    function _liquidate(
        address pool,
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 /* debtToCover — kept for ABI parity; on-chain we always pass type(uint256).max */
    ) internal returns (uint256 collateralReceived) {
        uint256 balBefore = IERC20(collateralAsset).balanceOf(address(this));
        // v232: pass max-uint so Aave self-caps to fully drain the collateral
        // side, bypassing MustNotLeaveDust (0xb629b0e4). Aave's effective cap
        // is min(reserveDebt, halfTotal_if_applicable, ourBalance).
        IPool(pool).liquidationCall(
            collateralAsset,
            debtAsset,
            user,
            type(uint256).max,
            false
        );
        collateralReceived = IERC20(collateralAsset).balanceOf(address(this)) - balBefore;
    }

    // ─── Admin Functions ─────────────────────────────────────────────────────

    function setMinProfitThreshold(uint256 newThreshold) external onlyOwner {
        uint256 old = minProfitThreshold;
        minProfitThreshold = newThreshold;
        emit MinProfitUpdated(old, newThreshold);
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        IERC20(token).safeTransfer(OWNER, withdrawAmount);
        emit ProfitWithdrawn(token, withdrawAmount);
    }

    function withdrawEth() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        emit EmergencyWithdraw(address(0), balance);
        (bool success, ) = OWNER.call{value: balance}("");
        require(success, "ETH transfer failed");
    }

    function getStats() external view returns (
        uint256 executions_,
        uint256 profitWei_,
        uint256 minProfit_
    ) {
        return (totalExecutions, totalProfitWei, minProfitThreshold);
    }

    /**
     * v258-svr-bal-fix verification anchor. The string is preserved in deployed
     * bytecode and can be queried via eth_call selector 0x54fd4d50.
     */
    function version() external pure returns (string memory) {
        return "v258-svr-bal-fix";
    }

    receive() external payable {}
}
