/**
Matthew 6:24
“No one can serve two masters, for either he will hate the one and love the other;

or else he will be devoted to one and despise the other.

You can’t serve both God and Mammon."

https://x.com/Mammon_ERC20

https://t.me/MammonErc20

https://www.mammon.fun/


*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20.sol";

contract MammonToken is ERC20 {
    constructor() ERC20("Mammon", "MAM") {
        _mint(msg.sender, 666000000*10**18);
    }
}
