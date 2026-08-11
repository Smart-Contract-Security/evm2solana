// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {BoostHub} from "../src/BoostHub.sol";

contract DeployEthereum is Script {
    address internal constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
    address internal constant VLSDT = 0x94818A7baa7e9F5dC62ce4da1B52ef9a760b80B8;
    address internal constant VLBOOST = 0xaB05ca46d1c78CAbB051efFE35099714Cad2AddA;
    address internal constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant SDCRV = 0xD1b5651E55D4CeeD36251c61c50C889B36F6abB5;
    address internal constant SDCRV_GAUGE = 0x7f50786A0b15723D741727882ee99a0BF34e3466;

    address internal constant SDFXN = 0xe19d1c837B8A1C83A56cD9165b2c0256D39653aD;
    address internal constant SDFXN_GAUGE = 0xbcfE5c47129253C6B8a9A00565B3358b488D42E0;

    function run() external returns (BoostHub hub) {
        vm.startBroadcast();

        hub = new BoostHub(msg.sender);
        hub.setStakeDaoAddresses(SDT, VLSDT, VLBOOST);

        address sdCrvDepositor = vm.envAddress("SDCRV_DEPOSITOR");
        address sdFxnDepositor = vm.envAddress("SDFXN_DEPOSITOR");

        address[] memory sdCrvRewards = new address[](4);
        sdCrvRewards[0] = SDT;
        sdCrvRewards[1] = THREE_CRV;
        sdCrvRewards[2] = CRV;
        sdCrvRewards[3] = CRVUSD;
        uint256 sdCrvPid = hub.addPool(SDCRV, SDCRV_GAUGE, sdCrvRewards);
        hub.approveStrategy(sdCrvDepositor, sdCrvPid, true);

        address[] memory sdFxnRewards = new address[](2);
        sdFxnRewards[0] = SDT;
        sdFxnRewards[1] = WSTETH;
        uint256 sdFxnPid = hub.addPool(SDFXN, SDFXN_GAUGE, sdFxnRewards);
        hub.approveStrategy(sdFxnDepositor, sdFxnPid, true);

        vm.stopBroadcast();
    }
}
