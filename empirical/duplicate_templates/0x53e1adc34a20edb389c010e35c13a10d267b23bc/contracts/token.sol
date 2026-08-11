// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KyberswapElastic is ERC20 {
    constructor() payable ERC20("Neon Lights", "NEON") {
        _mint(msg.sender, 742e12 * 10**decimals());
    }
}