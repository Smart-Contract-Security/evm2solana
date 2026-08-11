/**

LP Burned. Simple contract.
website: https://trump.no/


*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ERC20.sol";
contract Trumpnotoken is ERC20 {
    constructor() ERC20("Trump.No", "TN") {
        _mint(msg.sender, 888000000*10**18);
    }
}
