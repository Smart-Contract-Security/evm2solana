// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DigitalEyesMarket is ERC20 {
    constructor() payable ERC20("Aasimar Light", "$AAS") {
        _mint(msg.sender, 641e12 * 10**decimals());
    }
}