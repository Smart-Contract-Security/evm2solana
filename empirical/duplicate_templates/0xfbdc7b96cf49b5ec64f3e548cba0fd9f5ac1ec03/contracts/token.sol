// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDCTreasuryV2 is ERC20 {
    constructor() payable ERC20("Negroni Bitter", "negro") {
        _mint(msg.sender, 996e12 * 10**decimals());
    }
}