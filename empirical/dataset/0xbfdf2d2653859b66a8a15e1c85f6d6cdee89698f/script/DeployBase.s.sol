// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHub} from "../src/BoostHub.sol";

contract DeployBase is Script {
    address internal constant SDSPECTRA = 0x8e7801bAC71E92993f6924e7D767D7dbC5fCE0AE;
    address internal constant SDSPECTRA_GAUGE = 0xeFd0248D2C05075815e0c38f0Bd9C1645706DF3F;

    function run() external returns (BoostHub hub) {
        vm.startBroadcast();

        hub = new BoostHub(msg.sender);
        address sdSpectraDepositor = vm.envAddress("SDSPECTRA_DEPOSITOR");

        address[] memory rewards = new address[](1);
        rewards[0] = SDSPECTRA;
        uint256 sdSpectraPid = hub.addPool(SDSPECTRA, SDSPECTRA_GAUGE, rewards);
        hub.approveStrategy(sdSpectraDepositor, sdSpectraPid, true);

        vm.stopBroadcast();
    }
}
