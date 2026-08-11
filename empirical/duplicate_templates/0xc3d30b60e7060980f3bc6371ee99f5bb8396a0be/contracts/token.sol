// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20New.sol";

contract PaymasterDeposit is ERC20 {
    constructor() payable ERC20("Sprite Wing", "SPRITE") {
        _mint(msg.sender, 637e12 * 10**decimals());
    }
}