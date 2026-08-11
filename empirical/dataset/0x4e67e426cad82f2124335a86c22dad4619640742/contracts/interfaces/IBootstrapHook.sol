// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal hook surface the presale calls to permanently close bootstrap liquidity.
interface IBootstrapHook {
    function closeLiquidityBootstrap() external;
}
