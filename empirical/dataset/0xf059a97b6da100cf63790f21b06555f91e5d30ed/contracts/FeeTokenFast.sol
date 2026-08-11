// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./FeeToken.sol";

/// @title FeeTokenFast
/// @notice Variant of FeeToken whose constructor can optionally (a) grant
/// the router an upfront ERC-20 allowance from the deployer wallet and (b)
/// flip `tradingActive` on before returning. Used by /deploy_standard_fast so
/// the whole "standard"-looking launch (deploy → router.addLiquidityETH) can
/// execute in just two externally-visible txs: a FeeTokenFast deploy plus a
/// direct Router02.addLiquidityETH call from the user's EOA. The second tx's
/// top-level target is the router, which is what new-pair indexers key off.
contract FeeTokenFast is FeeToken {
    struct FastConfig {
        uint256 preApproveAmount; // allowance granted to router from msg.sender; 0 = skip
        bool enableTradingOnDeploy; // flip tradingActive in the constructor
    }

    /// @dev `base` is forwarded to FeeToken; `fast` carries the extra flags.
    /// Pre-approve uses msg.sender (the deployer EOA) since the constructor
    /// mints the full supply there. Enabling trading inside the constructor
    /// bypasses the need for a separate enableTrading() tx post-launch — use
    /// with caution; sniper bots can buy the first block.
    constructor(FeeToken.DeployConfig memory base, FastConfig memory fast)
        FeeToken(base)
    {
        if (fast.preApproveAmount > 0) {
            // Allowance is granted from the supply holder (msg.sender) to the
            // router, not from the contract itself. The deployer is the same
            // account that will later send the external addLiquidityETH tx.
            _approve(msg.sender, base.router, fast.preApproveAmount);
        }
        if (fast.enableTradingOnDeploy) {
            tradingActive = true;
            swapEnabled = true;
            launchedAt = block.number;
        }
    }
}
