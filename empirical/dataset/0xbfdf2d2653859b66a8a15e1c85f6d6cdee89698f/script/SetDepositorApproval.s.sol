// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHub} from "../src/BoostHub.sol";

contract SetDepositorApproval is Script {
    function run() external {
        BoostHub hub = BoostHub(vm.envAddress("BOOSTHUB"));
        uint256 pid = vm.envUint("PID");
        address depositor = vm.envAddress("DEPOSITOR");
        bool approved = vm.envBool("APPROVED");

        vm.startBroadcast();
        hub.approveStrategy(depositor, pid, approved);
        vm.stopBroadcast();
    }
}
