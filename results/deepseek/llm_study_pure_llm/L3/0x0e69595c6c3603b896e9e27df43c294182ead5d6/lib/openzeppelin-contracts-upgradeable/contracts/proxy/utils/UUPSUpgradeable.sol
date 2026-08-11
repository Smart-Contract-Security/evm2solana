// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract MyContract is UUPSUpgradeable {
    address public owner;
    uint256 public value;

    event ValueUpdated(uint256 newValue);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function initialize(address initialOwner) public initializer {
        __UUPSUpgradeable_init();
        owner = initialOwner;
    }

    function setValue(uint256 newValue) public onlyOwner {
        value = newValue;
        emit ValueUpdated(newValue);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}