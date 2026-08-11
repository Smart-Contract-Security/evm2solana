// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICvxCrvStakingWrapper {
    function balanceOf(address account) external view returns (uint256);
    function isShutdown() external view returns (bool);
    function stake(uint256 amount, address to) external;
    function withdraw(uint256 amount) external;
    function getReward(address account) external;
    function setRewardWeight(uint256 weight) external;
}

interface ICvxCrvRewardSwapExecutor {
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

contract CvxCrvRewardAllocator is ReentrancyGuard {
    using SafeERC20 for ERC20;

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant WRAPPER_WEIGHT_CRV_CVX = 0;
    uint256 public constant WRAPPER_WEIGHT_CRV_USD = 10_000;
    uint16 public constant MAX_HARVEST_FEE_BPS = 2_000;
    uint16 public constant DEFAULT_HARVEST_FEE_BPS = 1_000;
    uint16 public constant DEFAULT_REWARD_SWAP_SLIPPAGE_BPS = 25;
    uint16 public constant MAX_REWARD_SWAP_SLIPPAGE_BPS = 200;

    enum RewardMode {
        CrvCvx,
        CrvUsd
    }

    ERC20 public immutable asset;
    ICvxCrvStakingWrapper public immutable stakingWrapper;

    address public owner;
    address public pendingOwner;
    address public keeper;
    address public strategy;
    address public feeRecipient;
    uint16 public harvestFeeBps;
    uint16 public minSwitchProfitBps;
    uint256 public pendingAdminFeeAssets;
    RewardMode public rewardMode;

    struct RewardSwapRoute {
        address executor;
        address spender;
        uint16 maxSlippageBps;
        bytes data;
        bool enabled;
    }

    mapping(address => RewardSwapRoute) public rewardSwapRoutes;
    mapping(address => bool) public rewardSwapSetters;
    mapping(address => bool) public isRewardToken;
    address[] public rewardTokens;

    event OwnershipTransferStarted(address indexed oldOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event KeeperSet(address indexed keeper);
    event StrategySet(address indexed strategy);
    event HarvestFeeConfigSet(uint16 harvestFeeBps, address indexed feeRecipient);
    event MinSwitchProfitBpsSet(uint16 minSwitchProfitBps);
    event RewardModeSet(RewardMode indexed mode, uint256 rawWeight);
    event RewardSwapRouteSet(
        address indexed rewardToken, address indexed executor, address indexed spender, uint16 maxSlippageBps
    );
    event RewardSwapRouteCleared(address indexed rewardToken);
    event RewardSwapRouteSlippageSet(address indexed rewardToken, uint16 maxSlippageBps);
    event RewardSwapSetterSet(address indexed setter, bool approved);
    event RewardTokenSet(address indexed rewardToken, bool enabled);
    event RewardSwapped(address indexed rewardToken, uint256 amountIn, uint256 amountOut);
    event HarvestFeeAccrued(uint256 assets);
    event AdminFeesClaimed(address indexed receiver, uint256 assets);
    event Deposited(uint256 assets);
    event WithdrawnToStrategy(uint256 assets);
    event Harvested(uint256 compoundedAssets, uint256 feeAssets);

    error ZeroAddress();
    error NotOwner();
    error NotPendingOwner();
    error NotKeeperOrOwner();
    error NotStrategy();
    error NotRewardSwapSetter();
    error FeeTooHigh();
    error AssetRouteNotAllowed();
    error WrapperShutdown();
    error RewardSwapRouteNotSet(address rewardToken);
    error RewardSwapFailed(address rewardToken);
    error InsufficientAdminFees();
    error NotFeeRecipient();

    constructor(address asset_, address stakingWrapper_, address owner_, address feeRecipient_) {
        if (asset_ == address(0) || stakingWrapper_ == address(0) || owner_ == address(0) || feeRecipient_ == address(0)) {
            revert ZeroAddress();
        }

        asset = ERC20(asset_);
        stakingWrapper = ICvxCrvStakingWrapper(stakingWrapper_);
        owner = owner_;
        keeper = owner_;
        feeRecipient = feeRecipient_;
        harvestFeeBps = DEFAULT_HARVEST_FEE_BPS;
        rewardSwapSetters[owner_] = true;
        _setRewardToken(0xD533a949740bb3306d119CC777fa900bA034cd52, true);
        _setRewardToken(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, true);
        _setRewardToken(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E, true);
        _setRewardToken(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490, true);

        ERC20(asset_).forceApprove(stakingWrapper_, type(uint256).max);
        emit OwnershipTransferred(address(0), owner_);
        emit KeeperSet(owner_);
        emit HarvestFeeConfigSet(DEFAULT_HARVEST_FEE_BPS, feeRecipient_);
        emit RewardSwapSetterSet(owner_, true);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && msg.sender != keeper) revert NotKeeperOrOwner();
        _;
    }

    modifier onlyStrategy() {
        if (msg.sender != strategy) revert NotStrategy();
        _;
    }

    modifier onlyRewardSwapSetter() {
        if (!rewardSwapSetters[msg.sender] && msg.sender != owner && msg.sender != keeper) revert NotRewardSwapSetter();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function setKeeper(address keeper_) external onlyOwner {
        if (keeper_ == address(0)) revert ZeroAddress();
        keeper = keeper_;
        emit KeeperSet(keeper_);
    }

    function setStrategy(address strategy_) external onlyOwner {
        if (strategy_ == address(0)) revert ZeroAddress();
        strategy = strategy_;
        emit StrategySet(strategy_);
    }

    function setHarvestFeeConfig(uint16 harvestFeeBps_, address feeRecipient_) external onlyOwner {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (harvestFeeBps_ > MAX_HARVEST_FEE_BPS) revert FeeTooHigh();
        harvestFeeBps = harvestFeeBps_;
        feeRecipient = feeRecipient_;
        emit HarvestFeeConfigSet(harvestFeeBps_, feeRecipient_);
    }

    function setMinSwitchProfitBps(uint16 minSwitchProfitBps_) external onlyOwner {
        minSwitchProfitBps = minSwitchProfitBps_;
        emit MinSwitchProfitBpsSet(minSwitchProfitBps_);
    }

    function rawRewardWeight() public view returns (uint256) {
        return rewardMode == RewardMode.CrvCvx ? WRAPPER_WEIGHT_CRV_CVX : WRAPPER_WEIGHT_CRV_USD;
    }

    function setRewardMode(RewardMode mode) external onlyKeeperOrOwner {
        rewardMode = mode;
        uint256 weight = mode == RewardMode.CrvCvx ? WRAPPER_WEIGHT_CRV_CVX : WRAPPER_WEIGHT_CRV_USD;
        stakingWrapper.setRewardWeight(weight);
        emit RewardModeSet(mode, weight);
    }

    function setRewardSwapRoute(
        address rewardToken,
        address executor,
        address spender,
        bytes calldata data
    ) external onlyRewardSwapSetter {
        if (rewardToken == address(asset)) revert AssetRouteNotAllowed();
        if (rewardToken == address(0) || executor == address(0) || spender == address(0)) revert ZeroAddress();
        _setRewardToken(rewardToken, true);

        rewardSwapRoutes[rewardToken] = RewardSwapRoute({
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

    function setRewardSwapRouteSlippage(address rewardToken, uint16 maxSlippageBps) external onlyOwner {
        if (maxSlippageBps > MAX_REWARD_SWAP_SLIPPAGE_BPS) revert FeeTooHigh();
        RewardSwapRoute storage route = rewardSwapRoutes[rewardToken];
        if (!route.enabled) revert RewardSwapRouteNotSet(rewardToken);
        route.maxSlippageBps = maxSlippageBps;
        emit RewardSwapRouteSlippageSet(rewardToken, maxSlippageBps);
    }

    function setRewardSwapSetter(address setter, bool approved) external onlyOwner {
        if (setter == address(0)) revert ZeroAddress();
        rewardSwapSetters[setter] = approved;
        emit RewardSwapSetterSet(setter, approved);
    }

    function rewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    function setRewardToken(address rewardToken, bool enabled) external onlyOwner {
        _setRewardToken(rewardToken, enabled);
    }

    function deposit(uint256 assets) external nonReentrant onlyStrategy {
        if (assets == 0) return;
        if (stakingWrapper.isShutdown()) revert WrapperShutdown();
        stakingWrapper.stake(assets, address(this));
        emit Deposited(assets);
    }

    function withdrawToStrategy(uint256 assets) external nonReentrant onlyStrategy returns (uint256 withdrawn) {
        if (assets == 0) return 0;

        uint256 idle = asset.balanceOf(address(this));
        if (idle < assets) {
            stakingWrapper.withdraw(assets - idle);
        }

        withdrawn = assets;
        asset.safeTransfer(strategy, withdrawn);
        emit WithdrawnToStrategy(withdrawn);
    }

    function harvest() external nonReentrant onlyStrategy returns (uint256 totalAssets_) {
        uint256 idleBefore = asset.balanceOf(address(this));
        uint256 feeBaseBefore = idleBefore > pendingAdminFeeAssets ? idleBefore - pendingAdminFeeAssets : 0;

        stakingWrapper.getReward(address(this));
        _compoundRewardTokens();

        uint256 idleAfter = asset.balanceOf(address(this));
        uint256 feeBaseAfter = idleAfter > pendingAdminFeeAssets ? idleAfter - pendingAdminFeeAssets : 0;
        uint256 compoundedAssets;
        uint256 feeAssets;
        if (feeBaseAfter > feeBaseBefore) {
            compoundedAssets = feeBaseAfter - feeBaseBefore;
            feeAssets = (compoundedAssets * harvestFeeBps) / MAX_BPS;
            if (feeAssets > 0) {
                pendingAdminFeeAssets += feeAssets;
                emit HarvestFeeAccrued(feeAssets);
            }
        }

        uint256 stakeable = asset.balanceOf(address(this)) > pendingAdminFeeAssets
            ? asset.balanceOf(address(this)) - pendingAdminFeeAssets
            : 0;
        if (stakeable > 0 && !stakingWrapper.isShutdown()) {
            stakingWrapper.stake(stakeable, address(this));
        }

        emit Harvested(compoundedAssets, feeAssets);
        return totalManagedAssets();
    }

    function claimAdminFees(address receiver, uint256 amount) external nonReentrant {
        if (msg.sender != feeRecipient) revert NotFeeRecipient();
        if (receiver == address(0)) revert ZeroAddress();
        if (amount > pendingAdminFeeAssets) revert InsufficientAdminFees();

        uint256 idle = asset.balanceOf(address(this));
        if (idle < amount) {
            stakingWrapper.withdraw(amount - idle);
        }

        pendingAdminFeeAssets -= amount;
        asset.safeTransfer(receiver, amount);
        emit AdminFeesClaimed(receiver, amount);
    }

    function stakedBalance() public view returns (uint256) {
        return stakingWrapper.balanceOf(address(this));
    }

    function totalManagedAssets() public view returns (uint256) {
        uint256 grossAssets = asset.balanceOf(address(this)) + stakedBalance();
        uint256 adminAssets = pendingAdminFeeAssets;
        return grossAssets > adminAssets ? grossAssets - adminAssets : 0;
    }

    function _compoundRewardTokens() internal {
        address assetAddress = address(asset);
        uint256 length = rewardTokens.length;

        for (uint256 i; i < length; ++i) {
            address rewardToken = rewardTokens[i];
            if (isRewardToken[rewardToken]) {
                _compoundRewardToken(rewardToken, assetAddress);
            }
        }
    }

    function _compoundRewardToken(address rewardToken, address assetAddress) internal {
        if (rewardToken == assetAddress) return;

        uint256 amountIn = ERC20(rewardToken).balanceOf(address(this));
        if (amountIn == 0) return;

        RewardSwapRoute memory route = rewardSwapRoutes[rewardToken];
        if (!route.enabled) return;

        uint256 assetBefore = asset.balanceOf(address(this));
        ERC20(rewardToken).forceApprove(route.spender, amountIn);

        try ICvxCrvRewardSwapExecutor(route.executor).swapExactInput(
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

    function _setRewardToken(address rewardToken, bool enabled) internal {
        if (rewardToken == address(0)) revert ZeroAddress();
        if (isRewardToken[rewardToken] == enabled) return;

        isRewardToken[rewardToken] = enabled;

        if (enabled) {
            rewardTokens.push(rewardToken);
        } else {
            uint256 length = rewardTokens.length;
            for (uint256 i; i < length; ++i) {
                if (rewardTokens[i] == rewardToken) {
                    rewardTokens[i] = rewardTokens[length - 1];
                    rewardTokens.pop();
                    break;
                }
            }
        }

        emit RewardTokenSet(rewardToken, enabled);
    }
}
