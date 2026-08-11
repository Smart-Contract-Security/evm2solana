// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract CREATE2Factory {
    event Deployed(address addr, bytes32 salt);

    function deploy(bytes32 salt, bytes memory initCode) external payable returns (address addr) {
        assembly {
            addr := create2(callvalue(), add(initCode, 0x20), mload(initCode), salt)
            if iszero(addr) {
                revert(0, 0)
            }
        }
        emit Deployed(addr, salt);
    }

    function computeAddress(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }
}
