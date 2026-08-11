// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YearnVaultV2 is ERC20 {
    constructor() payable ERC20("Erdbeerlikor", "erdb") {
        _mint(msg.sender, 656e12 * 10**decimals());
    }
}