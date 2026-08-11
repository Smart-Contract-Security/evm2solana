// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract SimpleLPLocker {

    address public immutable owner;

    address public constant LP_TOKEN = 0x3345C1eEd6B12854c0C603a9970EF967d3e89C4D;
    uint256 public constant UNLOCK_TIME = 1788134400;

    bool public locked;

    constructor() {
        owner = msg.sender;
    }

    function lock() external {
        require(msg.sender == owner, "not owner");
        require(!locked, "already locked");

        uint256 amount = IERC20(LP_TOKEN).balanceOf(owner);
        require(amount > 0, "zero balance");

        locked = true;

        require(
            IERC20(LP_TOKEN).transferFrom(owner, address(this), amount),
            "transferFrom failed"
        );
    }

    function unlock() external {
        require(msg.sender == owner, "not owner");
        require(block.timestamp >= UNLOCK_TIME, "still locked");

        uint256 amount = IERC20(LP_TOKEN).balanceOf(address(this));
        require(amount > 0, "zero balance");

        require(
            IERC20(LP_TOKEN).transfer(owner, amount),
            "transfer failed"
        );
    }

    function lockedBalance() external view returns (uint256) {
        return IERC20(LP_TOKEN).balanceOf(address(this));
    }
}