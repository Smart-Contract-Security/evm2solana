// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

/**
 * @title BatchExecutor
 * @notice Minimal stateless batch executor designed for EIP-7702 delegation, with
 *         built-in self-call access control so it is safe to delegate to from any EOA
 *         and leave the delegation active indefinitely without creating an attack surface.
 *
 * @dev Under EIP-7702, an EOA can delegate its "code" to this contract. When a tx with
 *      `to = EOA` is executed, the EVM runs this contract's bytecode in the EOA's
 *      storage context — which means `address(this) == EOA`.
 *
 *      The `executeBatch` function enforces `msg.sender == address(this)`:
 *        - EOA self-call (from == to == EOA): msg.sender == EOA == address(this) → PASS
 *        - Any external caller (from == attacker, to == EOA): msg.sender == attacker
 *          != address(this) (which is EOA) → REVERT
 *
 *      This makes the contract safe:
 *        1. Even if the EOA forgets (or fails) to revoke its EIP-7702 delegation,
 *           no one else can invoke the batched execution in the EOA's context.
 *        2. When called directly as a normal contract (no delegation), the check
 *           reverts because address(this) == BatchExecutor, not the caller.
 *
 *      Usage in forge script:
 *        BatchExecutor batcher = new BatchExecutor();
 *        vm.signAndAttachDelegation(address(batcher), eoaPrivateKey);
 *        vm.broadcast(eoaPrivateKey);
 *        BatchExecutor(eoa).executeBatch(targets, calldatas);
 *
 *      The transaction is a type-4 (set code) tx. Each call inside `executeBatch`
 *      sees msg.sender == eoa, so contracts gated by `onlyGovernance(eoa)` accept them.
 *
 *      This contract has NO storage and NO state. The self-call check makes it
 *      safe to delegate to from any EOA even if delegation is left active permanently.
 */
contract BatchExecutor {
    error CallFailed(uint256 index, bytes returnData);
    error LengthMismatch();
    error NotSelf(address caller, address self);

    /**
     * @notice Execute a batch of calls in sequence
     * @dev Only callable by the EOA itself (self-call under EIP-7702 delegation).
     *      See contract-level docs for why `msg.sender == address(this)` is the
     *      right check under EIP-7702 semantics.
     * @param targets Array of target addresses
     * @param calldatas Array of encoded function call data
     */
    function executeBatch(address[] calldata targets, bytes[] calldata calldatas) external {
        // Only the delegated EOA itself can invoke this batch.
        if (msg.sender != address(this)) revert NotSelf(msg.sender, address(this));
        if (targets.length != calldatas.length) revert LengthMismatch();
        for (uint256 i; i < targets.length; i++) {
            (bool success, bytes memory ret) = targets[i].call(calldatas[i]);
            if (!success) revert CallFailed(i, ret);
        }
    }
}
