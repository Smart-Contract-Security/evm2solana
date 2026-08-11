// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseStrategy} from "./yearn/BaseStrategy.sol";
import {IBoostHub} from "./interfaces/IBoostHub.sol";

interface IRewardSwapExecutor {
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 maxSlippageBps,
        bytes calldata data
    )
        external
        returns (uint256 amountOut);
}

contract StrategyStakeDaoBoostHubYearn is BaseStrategy {
    using SafeERC20 for ERC20;

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_WITHDRAW_FEE_BPS = 300;
    uint256 public constant PUBLIC_HARVEST_FEE_BPS = 5;
    uint16 public constant DEFAULT_REWARD_SWAP_SLIPPAGE_BPS = 25;
    uint16 public constant MAX_REWARD_SWAP_SLIPPAGE_BPS = 200;
    uint16 public constant DEFAULT_WITHDRAW_FEE_BPS = 120;
    uint16 public constant DEFAULT_STRATEGY_YIELD_BOOST_FEE_BPS = 20;

    IBoostHub public immutable boostHub;
    uint256 public immutable pid;

    uint16 public withdrawFeeBps;
    uint16 public strategyYieldBoostFeeBps;
    address public adminFeeRecipient;
    uint256 public pendingAdminFeeAssets;
    bool public debtManagementFeeExempt;
    address public publicHarvestCaller;
    address public pendingPublicHarvestFeeRecipient;

    struct RewardSwapRoute {
        address executor;
        address spender;
        uint16 maxSlippageBps;
        bytes data;
        bool enabled;
    }

    mapping(address => RewardSwapRoute) public rewardSwapRoutes;
    mapping(address => bool) public rewardSwapSetters;

    event WithdrawFeeConfigSet(uint16 withdrawFeeBps, uint16 strategyYieldBoostFeeBps, address adminFeeRecipient);
    event StrategyYieldBoostFeeAssets(uint256 assets);
    event AdminFeeAssetsAccrued(uint256 assets);
    event AdminFeesClaimed(address indexed receiver, uint256 assets);
    event DebtManagementFeeExemptSet(bool exempt);
    event PublicHarvestCallerSet(address indexed caller);
    event PublicHarvestFeePrepared(address indexed receiver);
    event PublicHarvestFeePaid(address indexed receiver, uint256 assets);
    event RewardSwapRouteSet(
        address indexed rewardToken, address indexed executor, address indexed spender, uint16 maxSlippageBps
    );
    event RewardSwapRouteCleared(address indexed rewardToken);
    event RewardSwapRouteSlippageSet(address indexed rewardToken, uint16 maxSlippageBps);
    event RewardSwapSetterSet(address indexed setter, bool approved);
    event RewardSwapped(address indexed rewardToken, uint256 amountIn, uint256 amountOut);

    error ZeroAddress();
    error FeeTooHigh();
    error YieldBoostFeeExceedsWithdrawFee();
    error NotAdminFeeRecipient();
    error InsufficientAdminFees();
    error NotPublicHarvestCaller();
    error AssetRouteNotAllowed();
    error RewardSwapRouteNotSet(address rewardToken);
    error RewardSwapFailed(address rewardToken);
    error NotRewardSwapSetter();

    constructor(address asset_, string memory name_, address boostHub_, uint256 pid_, address adminFeeRecipient_)
        BaseStrategy(asset_, name_)
    {
        if (boostHub_ == address(0) || adminFeeRecipient_ == address(0)) revert ZeroAddress();
        boostHub = IBoostHub(boostHub_);
        pid = pid_;
        adminFeeRecipient = adminFeeRecipient_;
        withdrawFeeBps = DEFAULT_WITHDRAW_FEE_BPS;
        strategyYieldBoostFeeBps = DEFAULT_STRATEGY_YIELD_BOOST_FEE_BPS;
        rewardSwapSetters[msg.sender] = true;
        ERC20(asset_).forceApprove(boostHub_, type(uint256).max);
    }

    modifier onlyRewardSwapSetter() {
        if (!rewardSwapSetters[msg.sender]) {
            try TokenizedStrategy.requireKeeperOrManagement(msg.sender) {}
            catch {
                revert NotRewardSwapSetter();
            }
        }
        _;
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

    function setPublicHarvestCaller(address caller) external onlyManagement {
        publicHarvestCaller = caller;
        emit PublicHarvestCallerSet(caller);
    }

    function setRewardSwapRoute(
        address rewardToken,
        address executor,
        address spender,
        bytes calldata data
    ) external onlyRewardSwapSetter {
        if (rewardToken == address(asset)) revert AssetRouteNotAllowed();
        if (rewardToken == address(0) || executor == address(0) || spender == address(0)) revert ZeroAddress();

        rewardSwapRoutes[rewardToken] =
            RewardSwapRoute({
                executor: executor,
                spender: spender,
                maxSlippageBps: DEFAULT_REWARD_SWAP_SLIPPAGE_BPS,
                data: data,
                enabled: true
            });

        emit RewardSwapRouteSet(rewardToken, executor, spender, DEFAULT_REWARD_SWAP_SLIPPAGE_BPS);
    }

    function clearRewardSwapRoute(address rewardToken) external onlyRewardSwapSetter {
        RewardSwapRoute storage route = rewardSwapRoutes[rewardToken];
        if (route.spender != address(0)) {
            ERC20(rewardToken).forceApprove(route.spender, 0);
        }
        delete rewardSwapRoutes[rewardToken];
        emit RewardSwapRouteCleared(rewardToken);
    }

    function setRewardSwapRouteSlippage(address rewardToken, uint16 maxSlippageBps) external onlyManagement {
        if (maxSlippageBps > MAX_REWARD_SWAP_SLIPPAGE_BPS) revert FeeTooHigh();
        RewardSwapRoute storage route = rewardSwapRoutes[rewardToken];
        if (!route.enabled) revert RewardSwapRouteNotSet(rewardToken);
        route.maxSlippageBps = maxSlippageBps;
        emit RewardSwapRouteSlippageSet(rewardToken, maxSlippageBps);
    }

    function setRewardSwapSetter(address setter, bool approved) external onlyManagement {
        if (setter == address(0)) revert ZeroAddress();
        rewardSwapSetters[setter] = approved;
        emit RewardSwapSetterSet(setter, approved);
    }

    function preparePublicHarvestFee(address receiver) external {
        if (msg.sender != publicHarvestCaller) revert NotPublicHarvestCaller();
        if (receiver == address(0)) revert ZeroAddress();
        pendingPublicHarvestFeeRecipient = receiver;
        emit PublicHarvestFeePrepared(receiver);
    }

    function claimAdminFees(address receiver, uint256 amount) external {
        if (msg.sender != adminFeeRecipient) revert NotAdminFeeRecipient();
        if (receiver == address(0)) revert ZeroAddress();
        if (amount > pendingAdminFeeAssets) revert InsufficientAdminFees();

        uint256 idle = asset.balanceOf(address(this));
        if (idle < amount) {
            boostHub.withdraw(pid, amount - idle, address(this));
        }

        pendingAdminFeeAssets -= amount;
        asset.safeTransfer(receiver, amount);
        emit AdminFeesClaimed(receiver, amount);
    }

    function availableDepositLimit(address) public view override returns (uint256) {
        if (boostHub.poolInfo(pid).shutdown) return 0;
        return type(uint256).max;
    }

    function availableWithdrawLimit(address) public view override returns (uint256) {
        return _strategyAssets();
    }

    function _deployFunds(uint256 amount) internal override {
        if (amount > 0) {
            boostHub.deposit(pid, amount);
        }
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
            boostHub.withdraw(pid, toReturn, address(this));
        }
    }

    function _harvestAndReport() internal override returns (uint256 totalAssets_) {
        uint256 idleBefore = asset.balanceOf(address(this));
        uint256 feeBaseBefore = idleBefore > pendingAdminFeeAssets ? idleBefore - pendingAdminFeeAssets : 0;

        boostHub.harvest(pid);
        boostHub.claim(pid, address(this));
        _compoundRewardTokens();

        uint256 idle = asset.balanceOf(address(this));
        address publicFeeReceiver = pendingPublicHarvestFeeRecipient;
        if (publicFeeReceiver != address(0)) {
            pendingPublicHarvestFeeRecipient = address(0);
            uint256 feeBaseAfter = idle > pendingAdminFeeAssets ? idle - pendingAdminFeeAssets : 0;
            if (feeBaseAfter > feeBaseBefore) {
                uint256 publicFeeAssets = ((feeBaseAfter - feeBaseBefore) * PUBLIC_HARVEST_FEE_BPS) / MAX_BPS;
                if (publicFeeAssets > 0) {
                    asset.safeTransfer(publicFeeReceiver, publicFeeAssets);
                    idle -= publicFeeAssets;
                    emit PublicHarvestFeePaid(publicFeeReceiver, publicFeeAssets);
                }
            }
        }

        if (idle > pendingAdminFeeAssets && !TokenizedStrategy.isShutdown()) {
            boostHub.deposit(pid, idle - pendingAdminFeeAssets);
        }

        return _strategyAssets();
    }

    function _compoundRewardTokens() internal {
        IBoostHub.PoolView memory pool = boostHub.poolInfo(pid);
        address assetAddress = address(asset);

        for (uint256 i; i < pool.rewardTokens.length; i++) {
            address rewardToken = pool.rewardTokens[i];
            if (rewardToken == assetAddress) continue;

            uint256 amountIn = ERC20(rewardToken).balanceOf(address(this));
            if (amountIn == 0) continue;

            RewardSwapRoute memory route = rewardSwapRoutes[rewardToken];
            if (!route.enabled) continue;

            uint256 assetBefore = asset.balanceOf(address(this));
            ERC20(rewardToken).forceApprove(route.spender, amountIn);

            try IRewardSwapExecutor(route.executor).swapExactInput(
                rewardToken, assetAddress, amountIn, route.maxSlippageBps, route.data
            ) returns (uint256) {
                ERC20(rewardToken).forceApprove(route.spender, 0);
            } catch {
                ERC20(rewardToken).forceApprove(route.spender, 0);
                revert RewardSwapFailed(rewardToken);
            }

            uint256 amountOut = asset.balanceOf(address(this)) - assetBefore;
            if (ERC20(rewardToken).balanceOf(address(this)) != 0) revert RewardSwapFailed(rewardToken);

            emit RewardSwapped(rewardToken, amountIn, amountOut);
        }
    }

    function _emergencyWithdraw(uint256 amount) internal override {
        uint256 poolBalance = boostHub.balanceOf(pid, address(this));
        if (amount > poolBalance) amount = poolBalance;
        if (amount > 0) {
            boostHub.withdraw(pid, amount, address(this));
        }
    }

    function _strategyAssets() internal view returns (uint256) {
        uint256 grossAssets = asset.balanceOf(address(this)) + boostHub.balanceOf(pid, address(this));
        uint256 adminAssets = pendingAdminFeeAssets;
        return grossAssets > adminAssets ? grossAssets - adminAssets : 0;
    }
}
