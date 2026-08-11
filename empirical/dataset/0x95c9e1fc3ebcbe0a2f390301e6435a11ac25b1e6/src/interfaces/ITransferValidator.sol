// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITransferValidator721 {
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
}

interface ITransferValidator1155 {
    function validateTransfer(address caller, address from, address to, uint256 tokenId, uint256 amount) external;
}
