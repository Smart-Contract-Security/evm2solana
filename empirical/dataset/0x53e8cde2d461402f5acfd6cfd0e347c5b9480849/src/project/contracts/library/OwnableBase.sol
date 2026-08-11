// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OwnableBase {
    address _owner;

    event RenounceOwnership();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error InvalidOwner();

    constructor(address initialOwner) {
        _owner = initialOwner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "only owner");
        _;
    }

    function owner() external view virtual returns (address) {
        return _owner;
    }

    function ownerRenounce() public onlyOwner {
        _owner = address(0);
        emit RenounceOwnership();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        address previousOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
