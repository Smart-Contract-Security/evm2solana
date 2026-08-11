// SPDX-License-Identifier: MIT

import {IAaveV3Pool} from "../interfaces/external/IAaveV3Pool.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title AaveV3Strategy
/// @notice Adapter that supplies `underlyingAsset` (USDC) to Aave V3 and earns yield via aToken
///         balance accrual. Fully reusable across chains: deploy once per (vault, asset, pool, aToken).
/// @dev Aave V3 auto-accrues interest into the aToken — no `harvest()` action required at the
///      strategy level. The Vault's `lastRecordedBalance` snapshot handles fee accounting.
@program_id("AaveV3Strategy11111111111111111111111111111111")
contract AaveV3Strategy {
    /// @notice Aave V3 Pool contract (per-chain).
    address public immutable aavePool;

    /// @notice aToken counterpart of the underlying (e.g. aEthUSDC). Balance grows with interest.
    address public immutable aToken;

    /// @notice Underlying asset (USDC).
    address public immutable underlyingAsset;

    /// @notice Vault address.
    address public immutable vault;

    /// @notice Strategy version hash.
    bytes32 public immutable strategyVersionHash;

    /// @dev RAY (1e27) → bps (1e4) conversion factor used in `currentAPY`.
    uint64 private constant RAY_TO_BPS_DIVISOR = 100000000000000000000000;

    /// @param vault_     Apyee Vault address (must equal Vault.asset() == asset_).
    /// @param asset_     Underlying token (USDC).
    /// @param aavePool_  Aave V3 Pool contract for the chain.
    /// @param aToken_    aToken matching `asset_` on `aavePool_`. Must be passed in (saves a lookup).
    @payer(payer)
    @space(1024)
    @seed("AaveV3Strategy")
    constructor(
        address vault_,
        address asset_,
        address aavePool_,
        address aToken_,
        bytes32 strategyVersionHash_
    ) {
        if (aavePool_ == address(0) || aToken_ == address(0)) revert("ZeroAddress");
        vault = vault_;
        underlyingAsset = asset_;
        aavePool = aavePool_;
        aToken = aToken_;
        strategyVersionHash = strategyVersionHash_;

        // One-shot infinite approval so each `_deposit` skips the per-call approve.
        // Safe for trusted protocol contracts; Aave V3 Pool is immutable and audited.
        IERC20(underlyingAsset).approve(aavePool_, type(uint64).max);
    }

    // ─────────────────────────────────────────────────────────────
    // Strategy hooks
    // ─────────────────────────────────────────────────────────────

    /// @dev Pre-condition: caller already pulled `amount` USDC from the Vault into this contract.
    function _deposit(uint64 amount) internal {
        IAaveV3Pool(aavePool).supply{accounts: [underlyingAsset, address(this)]}(underlyingAsset, amount, address(this), 0);
    }

    function _withdraw(uint64 amount) internal returns (uint64 withdrawn) {
        // Aave returns the actual amount withdrawn — may be less if the pool's available
        // liquidity (cash) is below `amount`. Caller forwards `withdrawn` to the Vault.
        withdrawn = IAaveV3Pool(aavePool).withdraw{accounts: [underlyingAsset, address(this)]}(underlyingAsset, amount, address(this));
    }

    function _emergencyWithdraw() internal returns (uint64 withdrawn) {
        // `type(uint64).max` is the Aave convention for "withdraw entire aToken balance".
        // If the pool is partially illiquid, this returns whatever could be withdrawn rather
        // than reverting — exactly the behavior emergencyWithdraw needs (best-effort exit).
        uint64 bal = tokenBalance(aToken);
        if (bal == 0) return 0;
        withdrawn = IAaveV3Pool(aavePool).withdraw{accounts: [underlyingAsset, address(this)]}(underlyingAsset, type(uint64).max, address(this));
    }

    // ─────────────────────────────────────────────────────────────
    // IStrategy view methods
    // ─────────────────────────────────────────────────────────────

    /// @notice Current underlying balance held in Aave (principal + accrued interest).
    function balanceOf() external view returns (uint64) {
        return tokenBalance(aToken);
    }

    /// @notice Current supply APR in basis points (linear, not compounded).
    /// @dev Aave's `currentLiquidityRate` is APR in RAY (1e27). We strip 1e23 to land in bps (1e4).
    ///      APY ≈ APR for small rates (5% APR → 5.13% APY); a one-line approximation is enough
    ///      for ranking strategies. Off-chain consumers can compound if they need precision.
    function currentAPY() external view returns (uint64) {
        (uint64 currentLiquidityRate, , , , , , , , , , , ) = IAaveV3Pool(aavePool).getReserveData{accounts: [underlyingAsset]}(underlyingAsset);
        return currentLiquidityRate / RAY_TO_BPS_DIVISOR;
    }

    /// @notice Aave aTokens auto-accrue, so per-strategy `harvestable` accounting is moot —
    ///         the Vault tracks unrealized P&L via `lastRecordedBalance` instead. Returns 0 to
    ///         signal "no on-strategy harvest action needed".
    function harvestable() external pure returns (uint64) {
        return 0;
    }

    /// @dev Helper to get token balance using AccountInfo
    function tokenBalance(address token) private view returns (uint64) {
        (bool success, bytes memory data) = token.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (success && data.length >= 32) {
            return abi.decode(data, (uint64));
        }
        return 0;
    }
}

interface IERC20 {
    function approve(address spender, uint64 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint64);
}

interface IAaveV3Pool {
    function supply(address asset, uint64 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint64 amount, address to) external returns (uint64);
    function getReserveData(address asset) external view returns (uint64, uint64, uint64, uint64, uint64, uint64, uint64, uint64, uint64, uint64, uint64, uint64);
}