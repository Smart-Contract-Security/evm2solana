/**
Message of Hotei 7:11 “Wealth requires time, effort and perseverance; do not give up in the face of difficulties.

Keep working and learning to become the best in what you do.

You are the creator of your own destiny."

https://t.me/hoteigod

https://hoteigod.fun/

https://x.com/hoteigod


*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20.sol";

contract HoteiToken is ERC20 {
    constructor() ERC20("HOTEI", "HOTEI") {
        _mint(msg.sender, 777000000*10**18);
    }
}
