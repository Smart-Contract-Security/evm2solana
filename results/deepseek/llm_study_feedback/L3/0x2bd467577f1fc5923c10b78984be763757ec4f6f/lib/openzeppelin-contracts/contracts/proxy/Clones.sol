// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Errors} from "../utils/Errors.sol";

library Clones {
    function clone(address implementation) internal returns (address) {
        return clone(implementation, 0);
    }

    function clone(address implementation, uint256 value) internal returns (address) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        address deployed;
        // Solang does not support inline assembly. Use a low-level call to deploy.
        // We construct the creation bytecode manually and use the `new` keyword is not possible for arbitrary bytecode.
        // Instead, we use a pre-deployed factory or a different approach.
        // Since Solang does not support CREATE/CREATE2 directly, we simulate deployment via a call to a deployer contract.
        // However, for simplicity, we can use the `new` keyword with a proxy contract, but that requires a separate contract.
        // Given the constraints, we'll use a workaround: deploy a minimal proxy using a precompiled deployer.
        // But Solang does not have precompiles for CREATE.
        // The only way is to use a separate contract that performs the deployment.
        // We'll define a helper contract inside the library? No, libraries cannot contain contracts.
        // We'll assume a global deployer exists. This is a known limitation.
        // For now, we'll use a simple revert to indicate unsupported operation.
        revert("Clones: inline assembly not supported in Solang");
    }

    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address) {
        return cloneDeterministic(implementation, salt, 0);
    }

    function cloneDeterministic(
        address implementation,
        bytes32 salt,
        uint256 value
    ) internal returns (address) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        address deployed;
        revert("Clones: inline assembly not supported in Solang");
    }

    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        bytes32 initCodeHash = keccak256(bytecode);
        predicted = address(uint160(uint256(keccak256(abi.encodePacked(
            hex"ff",
            deployer,
            salt,
            initCodeHash
        )))));
    }

    function predictDeterministicAddress(
        address implementation,
        bytes32 salt
    ) internal view returns (address predicted) {
        return predictDeterministicAddress(implementation, salt, address(this));
    }
}