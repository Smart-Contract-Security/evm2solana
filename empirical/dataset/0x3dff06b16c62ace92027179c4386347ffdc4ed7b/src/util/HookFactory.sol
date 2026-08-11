// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title HookFactory
/// @notice CREATE2 factory for V4 hooks. We deploy from our own factory
/// rather than a shared public CREATE2 deployer (Arachnid's) — see the
/// [[no-public-create2-deployer]] memory rule.
///
/// Typical use:
///   - Off-chain, mine a salt with HookMiner so the resulting address
///     has the right Hooks.Permissions flags in its lowest bits.
///   - Call `deploy(salt, initCode)` with that salt + the hook's
///     constructor bytecode.
contract HookFactory {
    event Deployed(address addr, bytes32 salt);

    function deploy(bytes32 salt, bytes memory code) external payable returns (address addr) {
        assembly {
            addr := create2(callvalue(), add(code, 0x20), mload(code), salt)
            if iszero(addr) { revert(0, 0) }
        }
        emit Deployed(addr, salt);
    }
}
