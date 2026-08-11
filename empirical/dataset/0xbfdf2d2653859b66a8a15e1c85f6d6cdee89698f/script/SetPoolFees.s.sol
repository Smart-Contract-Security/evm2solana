// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHub} from "../src/BoostHub.sol";

contract SetPoolFees is Script {
    function run() external {
        BoostHub hub = BoostHub(vm.envAddress("BOOSTHUB"));
        uint256 pid = vm.envUint("PID");
        BoostHub.FeeConfig memory config = BoostHub.FeeConfig({
            platformFeeBps: _readBps("PLATFORM_FEE_BPS"),
            vlSdtReserveFeeBps: _readBps("VLSDT_RESERVE_FEE_BPS"),
            platformFeeRecipient: vm.envAddress("PLATFORM_FEE_RECIPIENT"),
            vlSdtReserveRecipient: vm.envAddress("VLSDT_RESERVE_RECIPIENT")
        });

        vm.startBroadcast();
        hub.setPoolFees(pid, config);
        vm.stopBroadcast();
    }

    function _readBps(string memory key) internal view returns (uint16) {
        uint256 value = vm.envUint(key);
        require(value <= type(uint16).max, "fee bps too large");
        return uint16(value);
    }
}
