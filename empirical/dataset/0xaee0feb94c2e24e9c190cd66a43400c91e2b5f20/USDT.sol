// SPDX-License-Identifier: MIT
     pragma solidity ^0.8.0;

     contract USDT {
         string public name = "USDT";
         string public symbol = "USDT";
         uint8 public decimals = 6;
         uint256 public totalSupply = 1000000 * (10 ** uint256(decimals)); // 1,000,000 tokens

         mapping(address => uint256) public balanceOf;

         constructor() {
             balanceOf[msg.sender] = totalSupply;
         }

         function transfer(address _to, uint256 _value) public returns (bool success) {
             require(balanceOf[msg.sender] >= _value);
             balanceOf[msg.sender] -= _value;
             balanceOf[_to] += _value;
             return true;
         }
     }