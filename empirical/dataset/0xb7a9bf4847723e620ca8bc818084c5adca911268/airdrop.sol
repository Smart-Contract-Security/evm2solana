// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Airdrop is Ownable {
    IERC20 public token;

    event Airdropped(address indexed recipient, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function TheTruthNeverLies(address tokenAddress) external onlyOwner {
        token = IERC20(tokenAddress);
    }

    function deposit(uint256 amount) external onlyOwner {
        require(token.transferFrom(msg.sender, address(this), amount), "Deposit failed");
    }

    function airdrop(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            require(token.transfer(recipients[i], amount), "Airdrop failed for recipient");
            emit Airdropped(recipients[i], amount);
        }
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(token.transfer(msg.sender, amount), "Withdrawal failed");
    }
}
