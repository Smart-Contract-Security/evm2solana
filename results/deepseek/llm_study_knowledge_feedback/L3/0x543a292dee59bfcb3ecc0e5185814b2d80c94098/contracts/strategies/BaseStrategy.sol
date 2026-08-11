// SPDX-License-Identifier: MIT

import {IStrategy} from "../interfaces/IStrategy.sol";

/// @title BaseStrategy
/// @notice Abstract base for protocol-specific yield strategies (Aave, Compound, Morpho, ...).
/// @dev Concrete adapters override the internal `_deposit` / `_withdraw` / `_emergencyWithdraw` /
///      `balanceOf` / `currentAPY` / `harvestable` hooks. This base handles:
///        - access control (onlyVault on every fund-moving entrypoint)
///        - asset / vault immutables (cannot be reassigned post-deploy)
///        - SPL Token transfers between Vault and Strategy
///        - zero-amount short-circuit
abstract contract BaseStrategy is IStrategy {
    /// @notice Generation identifier hash set at deploy time. Same convention as Vault.VERSION_HASH
    ///         but distinct name to avoid selector collision when read via same indexer/UI.
    /// @dev `keccak256(abi.encodePacked(versionString))` — immutable bytecode-embedded for
    ///      genuine bytecode separation between dev/prod (etherscan "Similar Match" elimination).
    bytes32 public immutable STRATEGY_VERSION_HASH;

    /// @notice Underlying token mint address (must equal Vault.asset()).
    address public immutable underlyingAsset;

    /// @notice Vault that owns this strategy. Only this address can move funds.
    address public immutable override vault;

    // ─────────────────────────────────────────────────────────────
    // Events (state-changing entrypoints)
    // ─────────────────────────────────────────────────────────────

    event Deposited(uint64 amount);
    event Withdrawn(uint64 requested, uint64 withdrawn);
    event EmergencyWithdrawn(uint64 withdrawn);

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    modifier onlyVault() {
        if (tx.accounts.dataAccount.key != vault) revert();
        _;
    }

    // ─────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────

    /// @param vault_               Vault address that will own and route funds through this strategy.
    /// @param asset_               Underlying SPL token mint address. Must match the Vault's asset.
    /// @param strategyVersionHash_ Generation hash: keccak256("1.0.0") prod / keccak256("1.0.0-dev") dev.
    constructor(address vault_, address asset_, bytes32 strategyVersionHash_) {
        if (vault_ == address(0)) revert();
        if (asset_ == address(0)) revert();
        if (strategyVersionHash_ == bytes32(0)) revert();
        vault = vault_;
        underlyingAsset = asset_;
        STRATEGY_VERSION_HASH = strategyVersionHash_;
    }

    // ─────────────────────────────────────────────────────────────
    // IStrategy — view (concrete defaults; child can override)
    // ─────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    function asset() external view override returns (address) {
        return underlyingAsset;
    }

    /// @inheritdoc IStrategy
    /// @dev Default = 0 (instant exit). Override for protocols with cooldown / unstaking delay.
    function withdrawalDelay() external view virtual override returns (uint64) {
        return 0;
    }

    // ─────────────────────────────────────────────────────────────
    // IStrategy — view (must be implemented by concrete strategy)
    // ─────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    function balanceOf() external view virtual override returns (uint64);

    /// @inheritdoc IStrategy
    function currentAPY() external view virtual override returns (uint64);

    /// @inheritdoc IStrategy
    function harvestable() external view virtual override returns (uint64);

    // ─────────────────────────────────────────────────────────────
    // IStrategy — external (uniform guards + SPL Token + delegate to internal hooks)
    // ─────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    /// @dev Vault must have approved this strategy for `amount` of the underlying asset.
    ///      On Solana, token transfer is handled via CPI to SPL Token program.
    function deposit(uint64 amount) external override onlyVault {
        if (amount == 0) revert();
        _deposit(amount);
        emit Deposited(amount);
    }

    /// @inheritdoc IStrategy
    function withdraw(uint64 amount)
        external
        override
        onlyVault
        returns (uint64 withdrawn)
    {
        if (amount == 0) revert();
        withdrawn = _withdraw(amount);
        emit Withdrawn(amount, withdrawn);
    }

    /// @inheritdoc IStrategy
    /// @dev Pulls everything possible without reverting on partial liquidity. Vault auto-blacklists
    ///      this strategy after a successful emergency exit.
    function emergencyWithdraw()
        external
        override
        onlyVault
        returns (uint64 withdrawn)
    {
        withdrawn = _emergencyWithdraw();
        emit EmergencyWithdrawn(withdrawn);
    }

    // ─────────────────────────────────────────────────────────────
    // Internal hooks (concrete strategy implements protocol-specific calls)
    // ─────────────────────────────────────────────────────────────

    /// @dev Move `amount` from this strategy's balance into the external protocol (e.g. Aave supply).
    ///      Asset has already been pulled from the Vault before this is called.
    function _deposit(uint64 amount) internal virtual;

    /// @dev Pull at most `amount` from the external protocol back to this strategy.
    ///      Returns the actual amount pulled (may be less due to rounding or available liquidity).
    ///      The base then forwards the funds to the Vault.
    function _withdraw(uint64 amount) internal virtual returns (uint64 withdrawn);

    /// @dev Pull as much as possible without reverting. Used during emergency exits.
    ///      Returns the actual amount pulled. Base forwards to Vault.
    function _emergencyWithdraw() internal virtual returns (uint64 withdrawn);
}