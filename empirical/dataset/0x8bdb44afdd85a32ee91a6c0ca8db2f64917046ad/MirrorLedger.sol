// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MirrorLedger {
    address public token;
    uint256 public points;
    uint256 private constant SCALE = 1e18;
    mapping(address => uint256) public paidAt;

    function bind(address token_) external {
        require(token == address(0), "bound");
        token = token_;
    }

    function reflect(uint256 amount, uint256 supply) external {
        require(msg.sender == token, "token");
        if (supply != 0) points += amount * SCALE / supply;
    }

    function preview(address who, uint256 bal) external view returns (uint256) {
        uint256 diff = points - paidAt[who];
        return diff * bal / SCALE;
    }

    function claim(address who, uint256 bal) external returns (uint256 due) {
        require(msg.sender == token, "token");
        due = (points - paidAt[who]) * bal / SCALE;
        paidAt[who] = points;
    }
}
