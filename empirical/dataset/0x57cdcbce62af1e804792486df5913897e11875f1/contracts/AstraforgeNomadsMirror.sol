// SPDX-License-Identifier: MIT

/*

    ASTRAFORGE NOMADS
    https://astraforgenomads.xyz
    https://x.com/astraforgeerc

*/

pragma solidity ^0.8.24;

import {DN404Mirror} from "./lib/DN404Mirror.sol";

contract AstraforgeNomadsMirror is DN404Mirror {
    constructor(address deployer) DN404Mirror(deployer) {}

    function name() public pure override returns (string memory) {
        return "Astraforge Nomads";
    }

    function symbol() public pure override returns (string memory) {
        return "NOMAD";
    }
}
