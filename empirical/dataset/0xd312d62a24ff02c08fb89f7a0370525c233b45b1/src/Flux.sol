// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// https://www.fluxeth.com/
// https://x.com/FluxOnETH

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Flux
/// @notice ERC-20 whose total supply mutates on every swap routed through the FluxHook.
///         Minting and burning are restricted exclusively to the hook contract. The hook
///         address is set once via {setHook} and can never be changed afterward, so once
///         ownership is renounced the hook is the only address that can ever move supply.
///
///         Anti-whale limits: max transaction = 2% of supply, max wallet = 2% of supply.
///         Because ~100% of supply sits inside the V4 PoolManager, infrastructure (pool manager,
///         position manager, routers, Permit2, the hook, the deployer) must be exempt or swaps and
///         liquidity break. Limits are therefore enforced against whichever counterparty of a
///         transfer is NOT exempt — so buys (pool -> user) and sells (user -> pool) are still
///         capped, while infrastructure flows through untouched.
/// @dev    Initial supply is minted to the deployer at construction. Decimals = 18 (OZ default).
contract Flux is ERC20, Ownable {
    /// @notice The only address permitted to mint and burn FLUX.
    address public hook;

    /// @notice Max transaction size, in basis points of current total supply (2%).
    uint256 public constant MAX_TX_BPS = 200;
    /// @notice Max wallet balance, in basis points of current total supply (2%).
    uint256 public constant MAX_WALLET_BPS = 200;

    /// @notice When false, all anti-whale limits are bypassed. Owner-controlled.
    bool public limitsEnabled = true;
    /// @notice Trading gate. Until enabled, only exempt addresses (deployer, pool, routers, hook)
    ///         can move FLUX — this lets liquidity be seeded before the public can trade.
    ///         Flipped on permanently via {enableTrading}; it can never be turned back off.
    bool public tradingEnabled;
    /// @notice Addresses exempt from limits AND from the trading gate (infrastructure, deployer, hook).
    mapping(address => bool) public isExcludedFromLimits;

    event HookSet(address indexed hook);
    event LimitsEnabledSet(bool enabled);
    event TradingEnabled();
    event ExcludedFromLimits(address indexed account, bool excluded);

    error HookAlreadySet();
    error HookIsZeroAddress();
    error NotHook();
    error MaxTxExceeded();
    error MaxWalletExceeded();
    error TradingNotEnabled();

    /// @param initialSupply Amount (in wei, 18 decimals) minted to `msg.sender` at deploy.
    constructor(uint256 initialSupply) ERC20("Flux", "FLUX") Ownable(msg.sender) {
        // The deployer is exempt so it can hold 100% pre-LP and seed liquidity.
        isExcludedFromLimits[msg.sender] = true;
        emit ExcludedFromLimits(msg.sender, true);
        _mint(msg.sender, initialSupply);
    }

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    /// @notice One-shot binding of the mint/burn authority to the hook contract. The hook is also
    ///         exempted from limits (its supply buffer can exceed 2%).
    /// @dev    Reverts on any second call. Callable only by the owner (deployer), and only
    ///         while `hook` is still unset. After this, mint/burn authority is immutable.
    function setHook(address _hook) external onlyOwner {
        if (hook != address(0)) revert HookAlreadySet();
        if (_hook == address(0)) revert HookIsZeroAddress();
        hook = _hook;
        isExcludedFromLimits[_hook] = true;
        emit HookSet(_hook);
        emit ExcludedFromLimits(_hook, true);
    }

    /// @notice Exempt (or re-include) an address from anti-whale limits. Owner-only.
    /// @dev    Used at deploy to exempt the PoolManager, PositionManager, Universal Router, Permit2,
    ///         and any aggregator routers so swaps and liquidity provisioning are not blocked.
    function excludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
        emit ExcludedFromLimits(account, excluded);
    }

    /// @notice Toggle all anti-whale limits. Owner-only.
    function setLimitsEnabled(bool enabled) external onlyOwner {
        limitsEnabled = enabled;
        emit LimitsEnabledSet(enabled);
    }

    /// @notice Open trading to the public. One-way: once enabled it can never be disabled. Owner-only.
    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice Current max transaction size (2% of live supply).
    function maxTxAmount() public view returns (uint256) {
        return (totalSupply() * MAX_TX_BPS) / 10_000;
    }

    /// @notice Current max wallet balance (2% of live supply).
    function maxWalletAmount() public view returns (uint256) {
        return (totalSupply() * MAX_WALLET_BPS) / 10_000;
    }

    /// @notice Mint FLUX into `to`. Hook-only. Expands supply into the hook buffer on sells.
    function mint(address to, uint256 amount) external onlyHook {
        _mint(to, amount);
    }

    /// @notice Burn FLUX from `from`. Hook-only. Contracts supply from the hook buffer on buys.
    function burn(address from, uint256 amount) external onlyHook {
        _burn(from, amount);
    }

    /// @dev Enforces anti-whale limits on transfers. Mints (from == 0) and burns (to == 0) are
    ///      never limited. The cap applies whenever at least one party is non-exempt, measured
    ///      against the non-exempt party — keeping pool/router infrastructure flowing freely.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            // Trading gate: before launch, BOTH parties must be exempt. This allows liquidity
            // seeding among infrastructure (deployer, pool, position manager, routers, hook) while
            // blocking every public trade — including buys (pool -> buyer) and sells (seller ->
            // pool), since the buyer/seller is not exempt. Mints/burns (zero address) are exempt.
            if (!tradingEnabled && !(isExcludedFromLimits[from] && isExcludedFromLimits[to])) {
                revert TradingNotEnabled();
            }
        }
        if (limitsEnabled && from != address(0) && to != address(0)) {
            uint256 supply = totalSupply();
            // Max tx: applies unless BOTH parties are exempt (e.g. deployer -> position manager).
            if (!isExcludedFromLimits[from] || !isExcludedFromLimits[to]) {
                if (value > (supply * MAX_TX_BPS) / 10_000) revert MaxTxExceeded();
            }
            // Max wallet: caps the recipient unless the recipient is exempt.
            if (!isExcludedFromLimits[to]) {
                if (balanceOf(to) + value > (supply * MAX_WALLET_BPS) / 10_000) revert MaxWalletExceeded();
            }
        }
        super._update(from, to, value);
    }
}
