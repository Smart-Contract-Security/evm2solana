// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Phantom_solanaWallet is ERC20 {
    constructor() payable ERC20("Mojito Mint", "MOJITO") {
        _mint(msg.sender, 889e12 * 10**decimals());
    }
}