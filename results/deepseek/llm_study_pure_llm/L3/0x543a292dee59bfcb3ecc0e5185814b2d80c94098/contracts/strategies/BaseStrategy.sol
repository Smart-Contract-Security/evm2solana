// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title BaseStrategy
/// @notice Abstract base for protocol-specific yield strategies (Aave, Compound, Morpho, ...).
/// @dev Concrete adapters override the internal `_deposit` / `_withdraw` / `_emergencyWithdraw` /
///      `balanceOf` / `currentAPY` / `harvestable` hooks. This base handles:
///        - access control (onlyVault on every fund-moving entrypoint)
///        - asset / vault immutables (cannot be reassigned post-deploy)
///        - SafeERC20 transfers between Vault and Strategy
///        - ReentrancyGuard on all state-changing externals
///        - zero-amount short-circuit
abstract contract BaseStrategy is IStrategy {
    /// @notice Generation identifier hash set at deploy time. Same convention as Vault.VERSION_HASH
    ///         but distinct name to avoid selector collision when read via same indexer/UI.
    /// @dev `keccak256(abi.encodePacked(versionString))` — immutable bytecode-embedded for
    ///      genuine bytecode separation between dev/prod (etherscan "Similar Match" elimination).
    bytes32 public immutable STRATEGY_VERSION_HASH;

    /// @notice Underlying token (must equal Vault.asset()).
    address public immutable underlyingAsset;

    /// @notice Vault that owns this strategy. Only this address can move funds.
    address public immutable override vault;

    /// @notice Reentrancy guard state variable
    bool private _locked;

    // ─────────────────────────────────────────────────────────────
    // Events (state-changing entrypoints)
    // ─────────────────────────────────────────────────────────────

    event Deposited(uint256 amount);
    event Withdrawn(uint256 requested, uint256 withdrawn);
    event EmergencyWithdrawn(uint256 withdrawn);

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.NotVault();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert("ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    // ─────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────

    /// @param vault_               Vault address that will own and route funds through this strategy.
    /// @param asset_               Underlying ERC-20 token (USDC). Must match the Vault's asset.
    /// @param strategyVersionHash_ Generation hash: keccak256("1.0.0") prod / keccak256("1.0.0-dev") dev.
    constructor(address vault_, address asset_, bytes32 strategyVersionHash_) {
        if (vault_ == address(0)) revert Errors.ZeroAddress();
        if (asset_ == address(0)) revert Errors.ZeroAddress();
        if (strategyVersionHash_ == bytes32(0)) revert Errors.ZeroAmount();
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
    function withdrawalDelay() external view virtual override returns (uint256) {
        return 0;
    }

    // ─────────────────────────────────────────────────────────────
    // IStrategy — view (must be implemented by concrete strategy)
    // ─────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    function balanceOf() external view virtual override returns (uint256);

    /// @inheritdoc IStrategy
    function currentAPY() external view virtual override returns (uint256);

    /// @inheritdoc IStrategy
    function harvestable() external view virtual override returns (uint256);

    // ─────────────────────────────────────────────────────────────
    // IStrategy — external (uniform guards + SafeERC20 + delegate to internal hooks)
    // ─────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    /// @dev Vault must have approved this strategy for `amount` of the underlying asset.
    function deposit(uint256 amount) external override onlyVault nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        _safeTransferFrom(underlyingAsset, vault, address(this), amount);
        _deposit(amount);
        emit Deposited(amount);
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 withdrawn)
    {
        if (amount == 0) revert Errors.ZeroAmount();
        withdrawn = _withdraw(amount);
        if (withdrawn > 0) {
            _safeTransfer(underlyingAsset, vault, withdrawn);
        }
        emit Withdrawn(amount, withdrawn);
    }

    /// @inheritdoc IStrategy
    /// @dev Pulls everything possible without reverting on partial liquidity. Vault auto-blacklists
    ///      this strategy after a successful emergency exit.
    function emergencyWithdraw()
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 withdrawn)
    {
        withdrawn = _emergencyWithdraw();
        if (withdrawn > 0) {
            _safeTransfer(underlyingAsset, vault, withdrawn);
        }
        emit EmergencyWithdrawn(withdrawn);
    }

    // ─────────────────────────────────────────────────────────────
    // Internal hooks (concrete strategy implements protocol-specific calls)
    // ─────────────────────────────────────────────────────────────

    /// @dev Move `amount` from this strategy's balance into the external protocol (e.g. Aave supply).
    ///      Asset has already been pulled from the Vault before this is called.
    function _deposit(uint256 amount) internal virtual;

    /// @dev Pull at most `amount` from the external protocol back to this strategy.
    ///      Returns the actual amount pulled (may be less due to rounding or available liquidity).
    ///      The base then forwards the funds to the Vault.
    function _withdraw(uint256 amount) internal virtual returns (uint256 withdrawn);

    /// @dev Pull as much as possible without reverting. Used during emergency exits.
    ///      Returns the actual amount pulled. Base forwards to Vault.
    function _emergencyWithdraw() internal virtual returns (uint256 withdrawn);

    // ─────────────────────────────────────────────────────────────
    // Internal SafeERC20 helpers (inline to avoid external imports)
    // ─────────────────────────────────────────────────────────────

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "SafeERC20: transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "SafeERC20: transferFrom failed");
    }
}