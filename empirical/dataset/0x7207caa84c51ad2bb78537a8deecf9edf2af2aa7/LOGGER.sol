// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface TOKEN {
    function lastFrom() external view returns (address);
    function lastTo() external view returns (address);
    function sender() external view returns (address);
}

contract LOGGER {
    uint256 public transferCount =0;

    event log(address, address, address);
    function send() public payable
    {
        address from = TOKEN(msg.sender).lastFrom();
        address to = TOKEN(msg.sender).lastTo();
        address sender = TOKEN(msg.sender).sender();
        emit log(
           from, to, sender
        );
        transferCount++;
    }
}