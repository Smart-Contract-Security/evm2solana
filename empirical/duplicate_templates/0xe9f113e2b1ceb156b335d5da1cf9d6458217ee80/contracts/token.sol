// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CryptoadzNFT is ERC20 {
    constructor() payable ERC20("Doomer Mode", "DOOM") {
        _mint(msg.sender, 757e12 * 10**decimals());
    }
}