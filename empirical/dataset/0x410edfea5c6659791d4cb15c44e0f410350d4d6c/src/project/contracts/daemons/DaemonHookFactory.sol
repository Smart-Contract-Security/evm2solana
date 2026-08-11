// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract DaemonHookFactory {
    event Deployed(address deployed, bytes32 salt);

    error Create2DeployFailed();

    function deploy(bytes32 salt, bytes memory initCode) external returns (address deployed) {
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        if (deployed == address(0)) revert Create2DeployFailed();
        emit Deployed(deployed, salt);
    }
}
