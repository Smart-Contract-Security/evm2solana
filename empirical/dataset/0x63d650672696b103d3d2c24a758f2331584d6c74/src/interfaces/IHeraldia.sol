// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IHeraldia {
    function mint(address to, uint256 tokenId) external;
    
    function ownerOf(uint256 tokenId) external view returns (address);
    
    function totalSupply() external view returns (uint256);
    
    function maxSupply() external pure returns (uint256);
}