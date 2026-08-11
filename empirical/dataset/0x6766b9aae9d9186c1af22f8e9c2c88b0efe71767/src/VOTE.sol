// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * Telegram: https://x.com/Freethepotus
 * X: https://x.com/Freethepotus
 * Website: https://www.savetrump.online
 */
contract VOTE is ERC20 {
    constructor() ERC20("NEVER SURRENDER", "VOTE") {
        _mint(msg.sender, 47_474_747_474_747e18);
    }
}
