// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20New.sol";

contract AjnaPool is ERC20 {
    constructor() payable ERC20("Unicum Hungarian", "unic") {
        _mint(msg.sender, 922e12 * 10**decimals());
    }
}