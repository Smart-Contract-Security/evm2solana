// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title Forwarder
 * @notice One-shot constructor-only contract. On deployment, sweeps its
 *         entire ETH / USDT / USDC balance to the hardcoded treasury,
 *         then SELFDESTRUCTs in the same transaction.
 *
 *         Because the SELFDESTRUCT happens in the same tx as the CREATE2
 *         deploy, EIP-6780 (Cancun) cleanly deletes the account, allowing
 *         a future deploy at the same CREATE2 address if the customer
 *         sends more funds later. (Without selfdestruct, the contract
 *         would remain at that address forever and any subsequent funds
 *         sent there would be permanently stuck.)
 *
 * @dev    Deployed exclusively via {OrderForwarderFactory}. The
 *         (treasury, usdt, usdc) tuple is passed by the factory at
 *         construction time, so each Forwarder instance is bound to
 *         one specific routing. The factory uses immutable storage
 *         for those three addresses so the factory owner can NEVER
 *         redirect funds to a different treasury — the worst they can
 *         do with the owner key is spam sweeps.
 *
 *         No reentrancy guards: the only external calls are `call`
 *         (ETH) and `transfer` (ERC20) targeting addresses we control.
 *         Reentry would have nothing to do — there's no mutable state
 *         and no further balance to drain after the sweep.
 *
 *         USDT's `transfer` does NOT return a bool (it returns void on
 *         success and reverts on failure — non-standard ERC20). We
 *         handle that with a low-level call + selective decode that
 *         accepts both "no return data" and "true". USDC is standard.
 */
contract Forwarder {
    error EthSweepFailed();
    error TokenSweepFailed(address token);

    /**
     * @param treasury  Destination for any swept funds.
     * @param usdt      USDT token contract (or zero to skip).
     * @param usdc      USDC token contract (or zero to skip).
     *
     * Marked `payable` so the deployment tx may carry ETH (which is
     * pointless in normal flow — the customer pre-funds the predicted
     * address before deploy — but cheaper than non-payable on the
     * compiled bytecode level).
     */
    constructor(address treasury, address usdt, address usdc) payable {
        // Sweep ERC20 balances first while the contract still has code.
        if (usdt != address(0)) {
            _sweepToken(usdt, treasury);
        }
        if (usdc != address(0)) {
            _sweepToken(usdc, treasury);
        }
        // ETH last — selfdestruct sends any remaining ETH to treasury
        // and (per EIP-6780, same-tx as create) deletes the account.
        // Forwards everything including pre-funded ETH from before
        // deployment + any ETH from the construction tx + leftover gas.
        selfdestruct(payable(treasury));
    }

    /**
     * Pull the full balance of `token` to `to`. Handles USDT's
     * non-standard `transfer` (returns void on success, reverts on
     * failure) via a low-level call that accepts:
     *   - call returns true AND no return data (USDT, BUSD, others)
     *   - call returns true AND return data decodes to `true` (USDC, DAI, standard)
     * Anything else reverts.
     */
    function _sweepToken(address token, address to) internal {
        // ERC20.balanceOf(this) — standard, always returns a uint256.
        (bool okBal, bytes memory balData) = token.staticcall(
            abi.encodeWithSelector(
                bytes4(keccak256("balanceOf(address)")),
                address(this)
            )
        );
        if (!okBal || balData.length < 32) {
            revert TokenSweepFailed(token);
        }
        uint256 bal = abi.decode(balData, (uint256));
        if (bal == 0) return;

        // ERC20.transfer(to, amount) — call without trusting the return.
        (bool okTx, bytes memory txData) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transfer(address,uint256)")),
                to,
                bal
            )
        );
        if (!okTx) {
            revert TokenSweepFailed(token);
        }
        // Accept either no return data (USDT-style) or `true` (standard).
        if (txData.length > 0) {
            bool returned = abi.decode(txData, (bool));
            if (!returned) {
                revert TokenSweepFailed(token);
            }
        }
    }
}
