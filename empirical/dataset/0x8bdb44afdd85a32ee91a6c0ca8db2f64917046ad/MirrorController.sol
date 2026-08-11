// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MirrorController {
    address public token;
    address public pair;
    uint256 public liveBlock;
    uint256 public opens;

    function bind(address token_) external {
        require(token == address(0), "bound");
        token = token_;
    }

    function opened(address pair_) external {
        require(msg.sender == token, "token");
        pair = pair_;
        liveBlock = block.number;
        opens++;
    }
}
