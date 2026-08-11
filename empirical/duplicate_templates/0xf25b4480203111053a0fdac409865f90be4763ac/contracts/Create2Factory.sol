// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title Create2Factory
 * @notice Minimal CREATE2 deployer exposing `deploy(bytes,bytes32)`.
 *         Deploys at keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))[12:],
 *         which is exactly what scripts/mine-salt.js predicts. Used to land ReformHook
 *         on an address whose lowest 14 bits == 0x00CC.
 *
 *         Deploy infra only — not part of the $REFORM token system.
 */
contract Create2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);

    function deploy(bytes memory bytecode, bytes32 salt) external returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "create2 failed");
        emit Deployed(addr, salt);
    }
}
