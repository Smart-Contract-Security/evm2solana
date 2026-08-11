// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BoostHub} from "./BoostHub.sol";

contract BoostHubSidechain is BoostHub {
    constructor(address owner_) BoostHub(owner_) {}
}
