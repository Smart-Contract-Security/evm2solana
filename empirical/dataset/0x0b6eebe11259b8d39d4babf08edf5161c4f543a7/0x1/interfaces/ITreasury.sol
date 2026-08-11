// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {
    event Received(address indexed from, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);
    event EthWithdrawn(address indexed to, uint256 amount);

    function withdrawToken(address token, address to, uint256 amount) external;
    function withdrawEth(address payable to, uint256 amount) external;
}
