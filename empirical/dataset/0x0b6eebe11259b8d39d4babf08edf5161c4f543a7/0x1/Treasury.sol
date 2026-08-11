// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITreasury} from "./interfaces/ITreasury.sol";

contract Treasury is Ownable2Step, ReentrancyGuard, ITreasury {
    using SafeERC20 for IERC20;

    error WithdrawalFailed();
    error ZeroAddress();
    error InsufficientBalance();

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Withdraw ERC-20 tokens held by the treasury.
    function withdrawToken(address token, address to, uint256 amount)
        external
        override
        onlyOwner
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    /// @notice Withdraw ETH held by the treasury.
    function withdrawEth(address payable to, uint256 amount) external override onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount > address(this).balance) revert InsufficientBalance();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert WithdrawalFailed();
        emit EthWithdrawn(to, amount);
    }
}
