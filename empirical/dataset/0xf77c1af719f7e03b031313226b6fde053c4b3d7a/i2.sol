// SPDX-License-Identifier: MIT
// This contract handles the locking and unlocking of SKAI tokens for different vesting categories.
// For more information,refer to https://docs.skainet.xyz/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SkAITokenLocker is Ownable {
    IERC20 public skaiToken;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 duration;
    }

    mapping(string => VestingSchedule) public vestingSchedules;

    event Deposit(address indexed user, uint256 amount, string category);
    event Withdrawal(address indexed recipient, uint256 amount, string category);

    constructor(address _skaiTokenAddress) Ownable(msg.sender) {
        skaiToken = IERC20(_skaiTokenAddress);
    }


    function deposit(uint256 amount, string memory category, uint256 startTime, uint256 cliffDuration, uint256 duration) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");

        VestingSchedule storage schedule = vestingSchedules[category];
        schedule.totalAmount += amount;
        schedule.startTime = startTime;
        schedule.cliffDuration = cliffDuration;
        schedule.duration = duration;

        skaiToken.transferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount, category);
    }

    function withdraw(address recipient, string memory category) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");

        VestingSchedule storage schedule = vestingSchedules[category];
        uint256 vestedAmount = _vestedAmount(schedule);
        uint256 withdrawableAmount = vestedAmount - schedule.releasedAmount;

        require(withdrawableAmount > 0, "No tokens available for withdrawal");

        schedule.releasedAmount += withdrawableAmount;
        skaiToken.transfer(recipient, withdrawableAmount);

        emit Withdrawal(recipient, withdrawableAmount, category);
    }


    function _vestedAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        } else if (block.timestamp >= schedule.startTime + schedule.duration) {
            return schedule.totalAmount;
        } else {
            uint256 elapsedTime = block.timestamp - schedule.startTime;
            return (schedule.totalAmount * elapsedTime) / schedule.duration;
        }
    }


    function getContractBalance() external view returns (uint256) {
        return skaiToken.balanceOf(address(this));
    }
}
