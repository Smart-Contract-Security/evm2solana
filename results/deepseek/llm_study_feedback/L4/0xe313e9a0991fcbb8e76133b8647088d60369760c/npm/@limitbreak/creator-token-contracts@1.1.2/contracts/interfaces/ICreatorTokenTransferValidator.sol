// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IEOARegistry {
    function isVerifiedEOA(address account) external view returns (bool);
}

interface ITransferSecurityRegistry {
    function getTransferSecurityLevel(address collection) external view returns (uint8);
}

interface ITransferValidator {
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view returns (bool);
}

interface ICreatorTokenTransferValidator is ITransferSecurityRegistry, ITransferValidator, IEOARegistry {}