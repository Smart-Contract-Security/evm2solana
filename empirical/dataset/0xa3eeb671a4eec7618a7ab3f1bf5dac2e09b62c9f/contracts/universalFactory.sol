// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract UniversalFactory {
    event Deployed(address indexed contractAddress, address indexed deployer);

    function deploy(bytes memory bytecode) external payable returns (address addr) {
        require(bytecode.length > 0, "Empty bytecode");

        assembly {
            addr := create(
                callvalue(),
                add(bytecode, 0x20),
                mload(bytecode)
            )
        }

        require(addr != address(0), "Deploy failed");

        emit Deployed(addr, msg.sender);
    }
}