// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGate} from "./IGate.sol";

contract Gate is IGate {
    address public keeper;
    mapping(address => bool) public override denied;

    error NotKeeper();
    error ZeroKeeper();

    constructor() {
        keeper = msg.sender;
    }

    function set(address who, bool flag) external {
        if (msg.sender != keeper) revert NotKeeper();
        denied[who] = flag;
    }

    function setMany(address[] calldata who, bool flag) external {
        if (msg.sender != keeper) revert NotKeeper();
        for (uint256 i; i < who.length; ++i) denied[who[i]] = flag;
    }

    function setKeeper(address to) external {
        if (msg.sender != keeper) revert NotKeeper();
        if (to == address(0)) revert ZeroKeeper();
        keeper = to;
    }
}
