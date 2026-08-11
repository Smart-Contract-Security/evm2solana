// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHub} from "../src/BoostHub.sol";

contract SetPoolMinimumHarvestAmount is Script {
    function run() external {
        BoostHub hub = BoostHub(vm.envAddress("BOOSTHUB"));
        uint256 pid = vm.envUint("PID");
        uint256 amount = vm.envUint("MINIMUM_HARVEST_AMOUNT");

        vm.startBroadcast();
        hub.setPoolMinimumHarvestAmount(pid, amount);
        vm.stopBroadcast();
    }
}
