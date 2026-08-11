// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;




/* ----------------------------------------------------------------------------
 *                   		DAEMONSv4 (DAEMON)          
 * ----------------------------------------------------------------------------
 *          Uniswap V4 Hook-Centric Concentrated Liquidity AMM
 *
 *   // https://x.com/DAEMONSv4
 *   // https://daemons.life/
 *
 * A high-performance AMM built directly on Uniswap v4 PoolManager with
 * custom dynamic hooks for adaptive fees, volatility-adjusted spreads,
 * concentrated liquidity management, and on-chain limit order execution.
 *
 * Key Technical Integrations:
 *   • IHooks implementation (before/afterSwap, before/afterAddLiquidity,
 *     before/afterRemoveLiquidity, beforeInitialize, afterInitialize)
 *   • Custom PoolKey + dynamic fee + tick spacing hooks
 *   • BalanceDelta + CurrencyLib accounting
 *   • PositionManager + LiquidityPosition NFT integration
 *   • MEV-resistant hook architecture with flash accounting
 *
 * Core Hook Capabilities:
 *   - Real-time volatility & volume based fee adjustment
 *   - Dynamic tick spacing & liquidity concentration
 *   - Automated rebalancing & range order hooks
 *   - Protocol-owned liquidity (POL) vault callbacks
 *   - Custom swap routing & intent-based execution hooks
 *
 * DAEMON Token Role:
 *   - Governance + fee capture token (ERC20 + ERC20Permit)
 *   - veDAEMON staking & revenue share
 *   - Emissions controller linked to protocol TVL & volume
 *
 * @author DAEMON Core Contributors
 * @notice Canonical DAEMON token contract - Do not deploy forks
 * -------------------------------------------------------------------------- */


import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice DAEMONS — fixed-supply ERC20 backing the artifact layer.
/// Whole tokens map to onchain SVG artifacts that mutate with every swap
/// through the canonical ETH/DAEMON v4 pool (see DaemonsHook). Supply is
/// minted once at construction to the deployer, who seeds the pool and
/// distributes the rest. No mint, no admin, no transfer tax.
contract DAEMONSv4 is ERC20, ERC20Burnable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("DAEMONSv4", "DAEMONS") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
