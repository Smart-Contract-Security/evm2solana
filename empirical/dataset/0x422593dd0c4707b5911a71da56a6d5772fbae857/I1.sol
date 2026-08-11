// This contract handles the miner incentives for the SKAINET platform.
// For more information, refer to https://docs.skainet.xyz/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SKAINETIncentives is Ownable {
    IERC20 public skaiToken;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);

    constructor(address _skaiTokenAddress) Ownable(msg.sender) {
        skaiToken = IERC20(_skaiTokenAddress);
    }


    function deposit(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        skaiToken.transferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        uint256 contractTokenBalance = skaiToken.balanceOf(address(this));
        require(contractTokenBalance >= amount, "Insufficient contract balance");

        skaiToken.transfer(recipient, amount);
        emit Withdrawal(recipient, amount);
    }


    function getContractBalance() external view returns (uint256) {
        return skaiToken.balanceOf(address(this));
    }
}
