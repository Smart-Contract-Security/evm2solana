// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @dev Minimal surface of the delegate.xyz v2 registry used for delegated Phase 1 claims.
///      Full registry: https://github.com/delegatexyz/delegate-registry (v2).
interface IDelegateRegistry {
    /// @notice Returns true if `to` is delegated to act on `from`'s behalf for `contract_`.
    /// @param to        The hot wallet acting on behalf of the vault.
    /// @param from      The vault (cold wallet) that granted the delegation.
    /// @param contract_ The contract the delegation is scoped to.
    /// @param rights    Rights identifier; `bytes32(0)` matches both an "all" delegation and a
    ///                  contract-scoped delegation to `contract_`.
    function checkDelegateForContract(address to, address from, address contract_, bytes32 rights)
        external
        view
        returns (bool);
}
