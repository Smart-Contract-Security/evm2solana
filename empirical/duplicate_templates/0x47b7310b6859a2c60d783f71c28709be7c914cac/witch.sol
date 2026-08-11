/**
The Law of the Dark Forest 23
“The Law of Conservation of Magic: Witches should not use their magic to harm other creatures or for personal gain, but only for good purposes."


https://t.me/tokenwitchchannel

https://witch.name/


*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "./ERC20.sol";
contract WitchToken is ERC20 {
    constructor() ERC20("Witch", "WITCH") {
        _mint(msg.sender, 666000000*10**18);
    }
}
