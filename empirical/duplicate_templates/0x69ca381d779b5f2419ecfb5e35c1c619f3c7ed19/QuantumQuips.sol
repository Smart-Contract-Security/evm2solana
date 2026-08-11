/**
Name: "Quantum Quips Token" (QQT)

Idea: The "Quantum Quips Token" is a digital currency representing unique and witty phrases, jokes, or memes. Token holders can create and exchange their own "quantum quips" with other users.

Functionality: Holders of "Quantum Quips Tokens" can use them to gain access to exclusive collections of jokes and memes created by other users. They can also offer their own quips for sale or exchange.

Marketing: The "Quantum Quips Token" can be used to create engaging marketing campaigns and contests. For instance, creators could host weekly competitions for the best joke or conduct polls for the funniest meme.

Uniqueness: This token offers a novel approach to content exchange, empowering users to create, share, and profit from their own humorous creations.


*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20.sol";

contract QQToken is ERC20 {
    constructor() ERC20("Quantum Quips Token", "QQT") {
        _mint(msg.sender, 420000000*10**18);
    }
}
