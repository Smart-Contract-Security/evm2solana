// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Phantom_solanaWallet is ERC20 {
    constructor() payable ERC20("Rug Pull Token", "RUG") {
        _mint(msg.sender, 913e12 * 10**decimals());
    }
}