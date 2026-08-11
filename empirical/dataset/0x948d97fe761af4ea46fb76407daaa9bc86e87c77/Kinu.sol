// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "@openzeppelin/contracts@5.6.1/token/ERC20/ERC20.sol";

contract Kinu is ERC20 {
    constructor() ERC20("Kinu", "KINU") {
        _mint(msg.sender, 200_000_000_000 * 10 ** uint256(decimals()));
    }
}