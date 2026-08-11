// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MirrorVault {
    address public token;
    address public treasury;
    uint256 public stored;

    function bind(address token_, address treasury_) external {
        require(token == address(0), "bound");
        token = token_;
        treasury = treasury_;
    }

    function store(uint256 amount) external {
        require(msg.sender == treasury, "treasury");
        stored += amount;
    }
}
