// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHubSidechain} from "../src/BoostHubSidechain.sol";

contract DeploySidechainDeterministic is Script {
    bytes32 internal constant SALT = keccak256("STAKE_DAO_BOOSTHUB_SIDECHAIN_V1");

    function run() external returns (BoostHubSidechain hub) {
        vm.startBroadcast();
        hub = new BoostHubSidechain{salt: SALT}(msg.sender);
        vm.stopBroadcast();
    }

    function predictedAddress(address deployer, address owner) external pure returns (address) {
        bytes memory initCode = abi.encodePacked(type(BoostHubSidechain).creationCode, abi.encode(owner));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, SALT, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }
}
