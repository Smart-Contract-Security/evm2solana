// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SymmetryBaskets is ERC20 {
    constructor() payable ERC20("Popcat Solana", "$POPCAT") {
        _mint(msg.sender, 531e12 * 10**decimals());
    }
}