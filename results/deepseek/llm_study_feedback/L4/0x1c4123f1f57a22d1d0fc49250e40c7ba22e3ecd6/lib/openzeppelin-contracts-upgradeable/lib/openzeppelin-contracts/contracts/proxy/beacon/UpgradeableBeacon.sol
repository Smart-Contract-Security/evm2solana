// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBeacon} from "./IBeacon.sol";

contract UpgradeableBeacon is IBeacon {
    address private _implementation;
    address private _owner;

    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    constructor(address implementation_, address initialOwner) {
        _transferOwnership(initialOwner);
        _setImplementation(implementation_);
    }

    function implementation() public view virtual returns (address) {
        return _implementation;
    }

    function upgradeTo(address newImplementation) public virtual onlyOwner {
        _setImplementation(newImplementation);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert("Ownable: new owner is the zero address");
        }
        _transferOwnership(newOwner);
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function _setImplementation(address newImplementation) private {
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    function _checkOwner() internal view virtual {
        if (tx.origin != _owner) {
            revert("Ownable: caller is not the owner");
        }
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}