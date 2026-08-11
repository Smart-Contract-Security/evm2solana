// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract ClaimAgent {

  address private owner;

  constructor() {
    owner = msg.sender;
  }

  function claimFromNFTAllocation(address allocation, uint256 tokenId, address to, uint256 amount) external onlyOwner {
    NFTAllocation a = NFTAllocation(allocation);
    a.withdraw(tokenId, to, amount);
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

}

interface NFTAllocation {

  function withdraw(uint256 tokenId, address to, uint256 amount) external;

}