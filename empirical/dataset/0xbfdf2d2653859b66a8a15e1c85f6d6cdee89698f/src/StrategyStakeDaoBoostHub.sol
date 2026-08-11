// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IBoostHub} from "./interfaces/IBoostHub.sol";

contract StrategyStakeDaoBoostHub is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable want;
    IBoostHub public immutable boostHub;
    uint256 public immutable pid;
    address public vault;

    error OnlyVault();
    error ZeroAddress();

    constructor(address want_, address boostHub_, uint256 pid_, address vault_) Ownable(msg.sender) {
        if (want_ == address(0) || boostHub_ == address(0) || vault_ == address(0)) revert ZeroAddress();
        want = want_;
        boostHub = IBoostHub(boostHub_);
        pid = pid_;
        vault = vault_;
        IERC20(want_).forceApprove(boostHub_, type(uint256).max);
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    function deposit() public nonReentrant {
        uint256 balance = IERC20(want).balanceOf(address(this));
        if (balance > 0) {
            boostHub.deposit(pid, balance);
        }
    }

    function withdraw(uint256 amount) external onlyVault nonReentrant {
        boostHub.withdraw(pid, amount, vault);
    }

    function harvest() external onlyVault nonReentrant {
        boostHub.harvest(pid);
        boostHub.claim(pid, vault);
    }

    function claimReward(address rewardToken) external onlyVault nonReentrant returns (uint256 amount) {
        amount = boostHub.claimReward(pid, rewardToken, vault);
    }

    function balanceOfPool() public view returns (uint256) {
        return boostHub.balanceOf(pid, address(this));
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOf() external view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
    }
}
