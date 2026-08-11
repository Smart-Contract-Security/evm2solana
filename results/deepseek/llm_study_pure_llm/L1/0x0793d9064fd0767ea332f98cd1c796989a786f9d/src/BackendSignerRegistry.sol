// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: zero address");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/// @title BackendSignerRegistry
/// @notice Stores the address of the backend signer used by BurnerDelegate to validate mint intents.
///         The owner can rotate the signer at any time.
contract BackendSignerRegistry is Ownable {
    address public backendSigner;

    event BackendSignerUpdated(address indexed oldSigner, address indexed newSigner);

    constructor(address initialSigner, address initialOwner) Ownable(initialOwner) {
        require(initialSigner != address(0), "zero signer");
        backendSigner = initialSigner;
    }

    /// @notice Rotates the backend signer. Only callable by owner.
    function setBackendSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "zero signer");
        emit BackendSignerUpdated(backendSigner, newSigner);
        backendSigner = newSigner;
    }
}