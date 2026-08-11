// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
contract Counter {
uint256 public count;
event CountChanged(uint256 newCount);
constructor(uint256 _initialCount){
count = _initialCount;
}
function increment() public {
count += 1;
emit CountChanged(count);
}
function decrement() public {
require(count > 0, "Count cannot go below zero");
count -= 1;
emit CountChanged(count);
}
function getCount() public view returns(uint256) { 
return count;
}
}
