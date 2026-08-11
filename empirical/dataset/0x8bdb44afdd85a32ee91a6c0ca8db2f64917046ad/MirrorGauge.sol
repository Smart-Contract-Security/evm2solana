// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MirrorGauge {
    address public token;
    uint256 public taxedFlow;
    uint256 public lastSeen;

    function bind(address token_) external {
        require(token == address(0), "bound");
        token = token_;
    }

    function mark(uint256 amount) external {
        require(msg.sender == token, "token");
        taxedFlow += amount;
        lastSeen = block.number;
    }
}
