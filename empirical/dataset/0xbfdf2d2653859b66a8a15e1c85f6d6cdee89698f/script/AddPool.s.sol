// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHub} from "../src/BoostHub.sol";

contract AddPool is Script {
    function run() external returns (uint256 pid) {
        BoostHub hub = BoostHub(vm.envAddress("BOOSTHUB"));
        address asset = vm.envAddress("ASSET");
        address gauge = vm.envAddress("GAUGE");
        address depositor = vm.envAddress("DEPOSITOR");
        uint256 rewardCount = vm.envUint("REWARD_COUNT");

        address[] memory rewards = new address[](rewardCount);
        for (uint256 i; i < rewardCount; i++) {
            rewards[i] = vm.envAddress(string.concat("REWARD_", vm.toString(i)));
        }

        vm.startBroadcast();
        pid = hub.addPool(asset, gauge, rewards);
        hub.approveStrategy(depositor, pid, true);
        vm.stopBroadcast();
    }
}
