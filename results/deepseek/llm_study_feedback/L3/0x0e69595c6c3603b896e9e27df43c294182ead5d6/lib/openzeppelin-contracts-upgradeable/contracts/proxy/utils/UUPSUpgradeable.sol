// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

contract MyContract {
    address public owner;
    uint256 public value;
    address private _implementation;

    event ValueUpdated(uint256 newValue);

    modifier onlyOwner() {
        require(tx.accounts[0].key == owner, "Not owner");
        _;
    }

    function initialize(address initialOwner) public {
        require(owner == address(0), "Already initialized");
        owner = initialOwner;
    }

    function setValue(uint256 newValue) public onlyOwner {
        value = newValue;
        emit ValueUpdated(newValue);
    }

    function upgradeTo(address newImplementation) public onlyOwner {
        _implementation = newImplementation;
    }

    function getImplementation() public view returns (address) {
        return _implementation;
    }
}