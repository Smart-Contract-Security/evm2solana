// SPDX-License-Identifier: MIT

import 'solana';

/// @notice AgentRouter mint entry used by distribution vaults (`minXaueOut` slippage guard).
interface IRouter {
    @account(routerProgram)
    @account(routerData)
    @account(tokenMint)
    @account(userTokenAccount)
    @account(authority)
    @mutableSigner(authority)
    @account(splToken)
    function mint(uint64 xautAmount, uint64 minXaueOut) external returns (uint64 xaueAmount);
}