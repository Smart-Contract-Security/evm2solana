// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MirrorClaim {
    address public token;
    mapping(address => uint256) public paid;

    function bind(address token_) external {
        require(token == address(0), "bound");
        token = token_;
    }

    function mark(address who, uint256 amount) external {
        require(msg.sender == token, "token");
        paid[who] += amount;
    }
}
