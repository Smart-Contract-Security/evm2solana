// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseStrategy} from "./yearn/BaseStrategy.sol";
import {CvxCrvRewardAllocator} from "./CvxCrvRewardAllocator.sol";

contract StrategyConvexCvxCrvYearn is BaseStrategy {
    using SafeERC20 for ERC20;

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_WITHDRAW_FEE_BPS = 300;
    uint16 public constant DEFAULT_WITHDRAW_FEE_BPS = 120;
    uint16 public constant DEFAULT_STRATEGY_YIELD_BOOST_FEE_BPS = 20;

    CvxCrvRewardAllocator public immutable allocator;

    uint16 public withdrawFeeBps;
    uint16 public strategyYieldBoostFeeBps;
    address public adminFeeRecipient;
    uint256 public pendingAdminFeeAssets;
    bool public debtManagementFeeExempt;

    event WithdrawFeeConfigSet(uint16 withdrawFeeBps, uint16 strategyYieldBoostFeeBps, address adminFeeRecipient);
    event StrategyYieldBoostFeeAssets(uint256 assets);
    event AdminFeeAssetsAccrued(uint256 assets);
    event AdminFeesClaimed(address indexed receiver, uint256 assets);
    event DebtManagementFeeExemptSet(bool exempt);

    error ZeroAddress();
    error FeeTooHigh();
    error YieldBoostFeeExceedsWithdrawFee();
    error NotAdminFeeRecipient();
    error InsufficientAdminFees();

    constructor(address asset_, string memory name_, address allocator_, address adminFeeRecipient_)
        BaseStrategy(asset_, name_)
    {
        if (allocator_ == address(0) || adminFeeRecipient_ == address(0)) revert ZeroAddress();
        allocator = CvxCrvRewardAllocator(allocator_);
        adminFeeRecipient = adminFeeRecipient_;
        withdrawFeeBps = DEFAULT_WITHDRAW_FEE_BPS;
        strategyYieldBoostFeeBps = DEFAULT_STRATEGY_YIELD_BOOST_FEE_BPS;
    }

    function setWithdrawFeeConfig(uint16 withdrawFeeBps_, uint16 strategyYieldBoostFeeBps_, address adminFeeRecipient_)
        external
        onlyManagement
    {
        if (adminFeeRecipient_ == address(0)) revert ZeroAddress();
        if (withdrawFeeBps_ > MAX_WITHDRAW_FEE_BPS) revert FeeTooHigh();
        if (strategyYieldBoostFeeBps_ > withdrawFeeBps_) revert YieldBoostFeeExceedsWithdrawFee();

        withdrawFeeBps = withdrawFeeBps_;
        strategyYieldBoostFeeBps = strategyYieldBoostFeeBps_;
        adminFeeRecipient = adminFeeRecipient_;
        emit WithdrawFeeConfigSet(withdrawFeeBps_, strategyYieldBoostFeeBps_, adminFeeRecipient_);
    }

    function setDebtManagementFeeExempt(bool exempt) external onlyManagement {
        debtManagementFeeExempt = exempt;
        emit DebtManagementFeeExemptSet(exempt);
    }

    function claimAdminFees(address receiver, uint256 amount) external {
        if (msg.sender != adminFeeRecipient) revert NotAdminFeeRecipient();
        if (receiver == address(0)) revert ZeroAddress();
        if (amount > pendingAdminFeeAssets) revert InsufficientAdminFees();

        uint256 idle = asset.balanceOf(address(this));
        if (idle < amount) {
            allocator.withdrawToStrategy(amount - idle);
        }

        pendingAdminFeeAssets -= amount;
        asset.safeTransfer(receiver, amount);
        emit AdminFeesClaimed(receiver, amount);
    }

    function availableDepositLimit(address) public view override returns (uint256) {
        if (allocator.stakingWrapper().isShutdown()) return 0;
        return type(uint256).max;
    }

    function availableWithdrawLimit(address) public view override returns (uint256) {
        return _strategyAssets();
    }

    function _deployFunds(uint256 amount) internal override {
        if (amount == 0) return;
        asset.safeTransfer(address(allocator), amount);
        allocator.deposit(amount);
    }

    function _freeFunds(uint256 amount) internal override {
        if (amount == 0) return;

        uint256 feeAssets = debtManagementFeeExempt ? 0 : (amount * withdrawFeeBps) / MAX_BPS;
        uint256 boostAssets = debtManagementFeeExempt ? 0 : (amount * strategyYieldBoostFeeBps) / MAX_BPS;
        uint256 adminAssets = feeAssets - boostAssets;
        uint256 toReturn = amount - feeAssets;

        if (adminAssets > 0) {
            pendingAdminFeeAssets += adminAssets;
            emit AdminFeeAssetsAccrued(adminAssets);
        }

        if (boostAssets > 0) {
            emit StrategyYieldBoostFeeAssets(boostAssets);
        }

        if (toReturn > 0) {
            allocator.withdrawToStrategy(toReturn);
        }
    }

    function _harvestAndReport() internal override returns (uint256) {
        allocator.harvest();

        uint256 idle = asset.balanceOf(address(this));
        if (idle > pendingAdminFeeAssets && !TokenizedStrategy.isShutdown()) {
            uint256 stakeable = idle - pendingAdminFeeAssets;
            asset.safeTransfer(address(allocator), stakeable);
            allocator.deposit(stakeable);
        }

        return _strategyAssets();
    }

    function _emergencyWithdraw(uint256 amount) internal override {
        uint256 allocatorAssets = allocator.totalManagedAssets();
        if (amount > allocatorAssets) amount = allocatorAssets;
        if (amount > 0) {
            allocator.withdrawToStrategy(amount);
        }
    }

    function _strategyAssets() internal view returns (uint256) {
        uint256 grossAssets = asset.balanceOf(address(this)) + allocator.totalManagedAssets();
        uint256 adminAssets = pendingAdminFeeAssets;
        return grossAssets > adminAssets ? grossAssets - adminAssets : 0;
    }
}
