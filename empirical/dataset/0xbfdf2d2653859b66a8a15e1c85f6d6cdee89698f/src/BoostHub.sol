// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IBoostHub} from "./interfaces/IBoostHub.sol";
import {IStakeDaoGauge} from "./interfaces/IStakeDaoGauge.sol";
import {ISnapshotDelegateRegistry} from "./interfaces/ISnapshotDelegateRegistry.sol";
import {IVlSDT} from "./interfaces/IVlSDT.sol";
import {IvlBoost} from "./interfaces/IvlBoost.sol";
import {BoostHubErrors as Errors} from "./libraries/BoostHubErrors.sol";

contract BoostHub is IBoostHub, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant ACC_PRECISION = 1e18;
    uint256 internal constant MAX_REWARD_TOKENS = 8;
    uint256 internal constant FEE_DENOMINATOR = 10_000;
    uint256 internal constant MAX_TOTAL_FEE_BPS = 3_500;

    struct Pool {
        address asset;
        address gauge;
        bool active;
        bool shutdown;
        uint256 totalStaked;
        address[] rewardTokens;
    }

    struct Position {
        uint256 principal;
        mapping(address => uint256) rewardDebt;
        mapping(address => uint256) claimable;
    }

    struct FeeConfig {
        uint16 platformFeeBps;
        uint16 vlSdtReserveFeeBps;
        address platformFeeRecipient;
        address vlSdtReserveRecipient;
    }

    enum UpdateCallArg {
        None,
        HubAddress,
        PoolGauge,
        PoolAsset,
        PoolId
    }

    enum UpdateCallReturn {
        Ignore,
        BoolTrue
    }

    struct UpdateCall {
        address target;
        bytes4 selector;
        UpdateCallArg arg;
        UpdateCallReturn returnMode;
        bool enabled;
    }

    Pool[] internal pools;
    FeeConfig public feeConfig;
    address public vlSdt;
    address public vlBoost;
    address public sdt;
    UpdateCall public boostUpdateCall;

    mapping(uint256 => FeeConfig) public poolFeeConfig;
    mapping(uint256 => bool) public poolFeeConfigSet;
    mapping(uint256 => uint256) public poolMinimumHarvestAmount;
    mapping(uint256 => bytes4) public poolCheckpointSelector;
    mapping(uint256 => UpdateCall) public poolUpdateCall;
    mapping(uint256 => mapping(address => bool)) public approvedStrategy;
    mapping(uint256 => mapping(address => Position)) internal positions;
    mapping(uint256 => mapping(address => uint256)) public accRewardPerShare;

    event PoolAdded(uint256 indexed pid, address indexed asset, address indexed gauge);
    event PoolActiveSet(uint256 indexed pid, bool active);
    event PoolShutdown(uint256 indexed pid);
    event StrategyApproved(uint256 indexed pid, address indexed strategy, bool approved);
    event FeesSet(
        uint16 platformFeeBps,
        uint16 vlSdtReserveFeeBps,
        address platformFeeRecipient,
        address vlSdtReserveRecipient
    );
    event PoolFeesSet(
        uint256 indexed pid,
        uint16 platformFeeBps,
        uint16 vlSdtReserveFeeBps,
        address platformFeeRecipient,
        address vlSdtReserveRecipient
    );
    event PoolMinimumHarvestAmountSet(uint256 indexed pid, uint256 amount);
    event PoolCheckpointSelectorSet(uint256 indexed pid, bytes4 selector);
    event PoolRewardTokenAdded(uint256 indexed pid, address indexed rewardToken);
    event GaugeCheckpointed(uint256 indexed pid);
    event BoostCheckpointed(address indexed account);
    event StakeDaoAddressesSet(address indexed sdt, address indexed vlSdt, address indexed vlBoost);
    event BoostUpdateCallSet(address indexed target, bytes4 selector, UpdateCallArg arg, UpdateCallReturn returnMode);
    event BoostUpdateCallCleared();
    event PoolUpdateCallSet(
        uint256 indexed pid, address indexed target, bytes4 selector, UpdateCallArg arg, UpdateCallReturn returnMode
    );
    event PoolUpdateCallCleared(uint256 indexed pid);
    event SdtLocked(uint256 amount);
    event VotingPowerDelegated(address indexed registry, bytes32 indexed spaceId, string space, address indexed delegate);
    event VotingPowerDelegateCleared(address indexed registry, bytes32 indexed spaceId, string space);

    constructor(address owner_) Ownable(owner_) {}

    function setStakeDaoAddresses(address sdt_, address vlSdt_, address vlBoost_) external onlyOwner {
        sdt = sdt_;
        vlSdt = vlSdt_;
        vlBoost = vlBoost_;
        emit StakeDaoAddressesSet(sdt_, vlSdt_, vlBoost_);
    }

    function addPool(address asset, address gauge, address[] memory rewardTokens) external onlyOwner returns (uint256 pid) {
        if (asset == address(0) || gauge == address(0)) revert Errors.ZeroAddress();
        if (IStakeDaoGauge(gauge).staking_token() != asset) revert Errors.InvalidGaugeAsset();
        if (rewardTokens.length > MAX_REWARD_TOKENS) revert Errors.RewardTokenLimitExceeded();

        for (uint256 i; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == address(0)) revert Errors.ZeroAddress();
            for (uint256 j; j < i; j++) {
                if (rewardTokens[i] == rewardTokens[j]) revert Errors.DuplicateRewardToken();
            }
        }

        pid = pools.length;
        pools.push();
        Pool storage pool = pools[pid];
        pool.asset = asset;
        pool.gauge = gauge;
        pool.active = true;

        for (uint256 i; i < rewardTokens.length; i++) {
            _addRewardToken(pool, pid, rewardTokens[i]);
        }

        IERC20(asset).forceApprove(gauge, type(uint256).max);

        emit PoolAdded(pid, asset, gauge);
    }

    function setPoolActive(uint256 pid, bool active) external onlyOwner {
        Pool storage pool = _pool(pid);
        pool.active = active;
        emit PoolActiveSet(pid, active);
    }

    function shutdownPool(uint256 pid) external onlyOwner {
        Pool storage pool = _pool(pid);
        pool.active = false;
        pool.shutdown = true;
        emit PoolShutdown(pid);
    }

    function approveStrategy(address strategy, uint256 pid, bool approved) external onlyOwner {
        if (strategy == address(0)) revert Errors.ZeroAddress();
        _pool(pid);
        approvedStrategy[pid][strategy] = approved;
        emit StrategyApproved(pid, strategy, approved);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFees(FeeConfig calldata config) external onlyOwner {
        _validateFeeConfig(config);

        feeConfig = config;
        emit FeesSet(
            config.platformFeeBps,
            config.vlSdtReserveFeeBps,
            config.platformFeeRecipient,
            config.vlSdtReserveRecipient
        );
    }

    function setPoolFees(uint256 pid, FeeConfig calldata config) external onlyOwner {
        _pool(pid);
        _validateFeeConfig(config);

        poolFeeConfig[pid] = config;
        poolFeeConfigSet[pid] = true;
        emit PoolFeesSet(
            pid,
            config.platformFeeBps,
            config.vlSdtReserveFeeBps,
            config.platformFeeRecipient,
            config.vlSdtReserveRecipient
        );
    }

    function setPoolMinimumHarvestAmount(uint256 pid, uint256 amount) external onlyOwner {
        _pool(pid);
        poolMinimumHarvestAmount[pid] = amount;
        emit PoolMinimumHarvestAmountSet(pid, amount);
    }

    function setPoolCheckpointSelector(uint256 pid, bytes4 selector) external onlyOwner {
        _pool(pid);
        if (selector == bytes4(0)) revert Errors.ZeroSelector();
        poolCheckpointSelector[pid] = selector;
        emit PoolCheckpointSelectorSet(pid, selector);
    }

    function setBoostUpdateCall(address target, bytes4 selector, uint8 arg, uint8 returnMode) external onlyOwner {
        UpdateCallArg argMode = _validateUpdateCall(target, selector, arg, returnMode);
        if (argMode > UpdateCallArg.HubAddress) revert Errors.InvalidUpdateCallArg();
        boostUpdateCall =
            UpdateCall(target, selector, argMode, UpdateCallReturn(returnMode), true);
        emit BoostUpdateCallSet(target, selector, argMode, UpdateCallReturn(returnMode));
    }

    function clearBoostUpdateCall() external onlyOwner {
        delete boostUpdateCall;
        emit BoostUpdateCallCleared();
    }

    function setPoolUpdateCall(uint256 pid, address target, bytes4 selector, uint8 arg, uint8 returnMode)
        external
        onlyOwner
    {
        _pool(pid);
        UpdateCallArg argMode = _validateUpdateCall(target, selector, arg, returnMode);
        poolUpdateCall[pid] =
            UpdateCall(target, selector, argMode, UpdateCallReturn(returnMode), true);
        emit PoolUpdateCallSet(pid, target, selector, argMode, UpdateCallReturn(returnMode));
    }

    function clearPoolUpdateCall(uint256 pid) external onlyOwner {
        _pool(pid);
        delete poolUpdateCall[pid];
        emit PoolUpdateCallCleared(pid);
    }

    function checkpointGauge(uint256 pid) external returns (bool) {
        Pool storage pool = _pool(pid);
        UpdateCall storage configuredCall = poolUpdateCall[pid];
        if (configuredCall.enabled) {
            bool configuredSuccess = _executeUpdateCall(configuredCall, pid, pool.gauge, pool.asset);
            if (!configuredSuccess) revert Errors.CheckpointFailed();
            emit GaugeCheckpointed(pid);
            return true;
        }

        bytes4 selector = poolCheckpointSelector[pid];
        if (selector == bytes4(0)) revert Errors.CheckpointSelectorNotSet();
        bool success = _checkpointGauge(pool.gauge, selector);
        if (!success) revert Errors.CheckpointFailed();
        emit GaugeCheckpointed(pid);
        return success;
    }

    function checkpointBoost() external {
        if (boostUpdateCall.enabled) {
            bool configuredSuccess = _executeUpdateCall(boostUpdateCall, 0, address(0), address(0));
            if (!configuredSuccess) revert Errors.CheckpointFailed();
            emit BoostCheckpointed(address(this));
            return;
        }

        if (vlBoost == address(0)) revert Errors.ZeroAddress();
        IvlBoost(vlBoost).checkpointUser(address(this));
        emit BoostCheckpointed(address(this));
    }

    function lockSdt(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        if (sdt == address(0) || vlSdt == address(0)) revert Errors.ZeroAddress();

        IERC20(sdt).forceApprove(vlSdt, amount);
        IVlSDT(vlSdt).stake(amount, address(this));
        emit SdtLocked(amount);
    }

    function delegateVotingPower(address registry, string calldata space, address delegate) external onlyOwner {
        if (registry == address(0) || delegate == address(0)) revert Errors.ZeroAddress();
        bytes32 spaceId = _snapshotSpaceId(space);
        ISnapshotDelegateRegistry(registry).setDelegate(spaceId, delegate);
        emit VotingPowerDelegated(registry, spaceId, space, delegate);
    }

    function clearVotingPowerDelegate(address registry, string calldata space) external onlyOwner {
        if (registry == address(0)) revert Errors.ZeroAddress();
        bytes32 spaceId = _snapshotSpaceId(space);
        ISnapshotDelegateRegistry(registry).clearDelegate(spaceId);
        emit VotingPowerDelegateCleared(registry, spaceId, space);
    }

    function poolInfo(uint256 pid) external view returns (PoolView memory view_) {
        Pool storage pool = _pool(pid);
        view_ = PoolView({
            asset: pool.asset,
            gauge: pool.gauge,
            active: pool.active,
            shutdown: pool.shutdown,
            totalStaked: pool.totalStaked,
            rewardTokens: pool.rewardTokens
        });
    }

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function deposit(uint256 pid, uint256 amount) external virtual override nonReentrant whenNotPaused {
        if (amount == 0) revert Errors.ZeroAmount();

        Pool storage pool = _pool(pid);
        if (!approvedStrategy[pid][msg.sender]) revert Errors.StrategyNotApproved();
        if (!pool.active) revert Errors.PoolInactive();
        if (pool.shutdown) revert Errors.PoolShutdown();

        _harvest(pid, pool);
        _checkpoint(pid, msg.sender);

        IERC20(pool.asset).safeTransferFrom(msg.sender, address(this), amount);
        IStakeDaoGauge(pool.gauge).deposit(amount, address(this));

        pool.totalStaked += amount;
        positions[pid][msg.sender].principal += amount;
        _syncRewardDebt(pid, msg.sender);
    }

    function withdraw(uint256 pid, uint256 amount, address receiver) external virtual override nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();

        Pool storage pool = _pool(pid);
        Position storage position = positions[pid][msg.sender];
        if (!approvedStrategy[pid][msg.sender] && position.principal == 0) revert Errors.StrategyNotApproved();

        _checkpoint(pid, msg.sender);

        position.principal -= amount;
        pool.totalStaked -= amount;
        _syncRewardDebt(pid, msg.sender);

        IStakeDaoGauge(pool.gauge).withdraw(amount, false);
        IERC20(pool.asset).safeTransfer(receiver, amount);
    }

    function harvest(uint256 pid)
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        Pool storage pool = _pool(pid);
        (tokens, amounts) = _harvest(pid, pool);
    }

    function _harvest(uint256 pid, Pool storage pool) internal returns (address[] memory tokens, uint256[] memory amounts) {
        _syncGaugeRewards(pid, pool);
        tokens = pool.rewardTokens;
        amounts = new uint256[](tokens.length);

        if (!_hasClaimableRewards(pid, pool.gauge, tokens)) return (tokens, amounts);

        uint256[] memory beforeBalances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            beforeBalances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        IStakeDaoGauge(pool.gauge).claim_rewards(address(this), address(this));
        if (pool.totalStaked == 0) return (tokens, amounts);

        for (uint256 i; i < tokens.length; i++) {
            uint256 harvested = IERC20(tokens[i]).balanceOf(address(this)) - beforeBalances[i];
            uint256 net = _chargeFees(pid, tokens[i], harvested);
            amounts[i] = net;
            if (net > 0) {
                accRewardPerShare[pid][tokens[i]] += net * ACC_PRECISION / pool.totalStaked;
            }
        }
    }

    function _hasClaimableRewards(uint256 pid, address gauge, address[] memory tokens) internal view returns (bool) {
        for (uint256 i; i < tokens.length; i++) {
            if (IStakeDaoGauge(gauge).claimable_reward(address(this), tokens[i]) >= _minimumHarvestAmount(pid, tokens[i])) {
                return true;
            }
        }
        return false;
    }

    function _checkpointGauge(address gauge, bytes4 selector) internal returns (bool) {
        (bool checkpointSuccess, bytes memory checkpointResult) =
            gauge.call(abi.encodeWithSelector(selector, address(this)));
        if (!checkpointSuccess) return false;
        if (selector != IStakeDaoGauge.user_checkpoint.selector) return true;
        if (checkpointResult.length < 32) return false;
        return abi.decode(checkpointResult, (bool));
    }

    function _validateUpdateCall(address target, bytes4 selector, uint8 arg, uint8 returnMode)
        internal
        pure
        returns (UpdateCallArg argMode)
    {
        if (target == address(0)) revert Errors.ZeroAddress();
        if (selector == bytes4(0)) revert Errors.ZeroSelector();
        if (arg > uint8(UpdateCallArg.PoolId)) revert Errors.InvalidUpdateCallArg();
        if (returnMode > uint8(UpdateCallReturn.BoolTrue)) revert Errors.InvalidUpdateCallReturn();
        argMode = UpdateCallArg(arg);
    }

    function _executeUpdateCall(UpdateCall storage updateCall, uint256 pid, address gauge, address asset)
        internal
        returns (bool)
    {
        bytes memory data;
        if (updateCall.arg == UpdateCallArg.None) {
            data = abi.encodeWithSelector(updateCall.selector);
        } else if (updateCall.arg == UpdateCallArg.HubAddress) {
            data = abi.encodeWithSelector(updateCall.selector, address(this));
        } else if (updateCall.arg == UpdateCallArg.PoolGauge) {
            data = abi.encodeWithSelector(updateCall.selector, gauge);
        } else if (updateCall.arg == UpdateCallArg.PoolAsset) {
            data = abi.encodeWithSelector(updateCall.selector, asset);
        } else if (updateCall.arg == UpdateCallArg.PoolId) {
            data = abi.encodeWithSelector(updateCall.selector, pid);
        } else {
            revert Errors.InvalidUpdateCallArg();
        }

        (bool success, bytes memory result) = updateCall.target.call(data);
        if (!success) return false;
        if (updateCall.returnMode == UpdateCallReturn.BoolTrue) {
            if (result.length < 32) return false;
            return abi.decode(result, (bool));
        }
        return true;
    }

    function _snapshotSpaceId(string calldata space) internal pure returns (bytes32 spaceId) {
        bytes memory spaceBytes = bytes(space);
        if (spaceBytes.length > 31) revert Errors.InvalidSnapshotSpace();
        assembly {
            spaceId := mload(add(spaceBytes, 32))
        }
    }

    function _syncGaugeRewards(uint256 pid, Pool storage pool) internal {
        for (uint256 i; i < MAX_REWARD_TOKENS; i++) {
            address rewardToken = IStakeDaoGauge(pool.gauge).reward_tokens(i);
            if (rewardToken == address(0)) return;
            if (!_isRewardToken(pool, rewardToken)) {
                _addRewardToken(pool, pid, rewardToken);
            }
        }
    }

    function _addRewardToken(Pool storage pool, uint256 pid, address rewardToken) internal {
        if (rewardToken == address(0)) revert Errors.ZeroAddress();
        if (pool.rewardTokens.length >= MAX_REWARD_TOKENS) revert Errors.RewardTokenLimitExceeded();
        if (_isRewardToken(pool, rewardToken)) revert Errors.DuplicateRewardToken();
        pool.rewardTokens.push(rewardToken);
        emit PoolRewardTokenAdded(pid, rewardToken);
    }

    function _isRewardToken(Pool storage pool, address rewardToken) internal view returns (bool) {
        for (uint256 i; i < pool.rewardTokens.length; i++) {
            if (pool.rewardTokens[i] == rewardToken) return true;
        }
        return false;
    }

    function _minimumHarvestAmount(uint256 pid, address token) internal view returns (uint256) {
        uint256 poolMinimum = poolMinimumHarvestAmount[pid];
        if (poolMinimum > 0) return poolMinimum;

        uint8 decimals;
        try IERC20Metadata(token).decimals() returns (uint8 tokenDecimals) {
            decimals = tokenDecimals;
        } catch {
            return type(uint256).max;
        }
        if (decimals == 0) return 1;
        if (decimals > 77) return type(uint256).max;
        return 10 ** (decimals - 1);
    }

    function claim(uint256 pid, address receiver)
        external
        virtual
        override
        nonReentrant
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (!_canClaim(pid, msg.sender)) revert Errors.StrategyNotApproved();

        _checkpoint(pid, msg.sender);

        Pool storage pool = _pool(pid);
        Position storage position = positions[pid][msg.sender];
        tokens = pool.rewardTokens;
        amounts = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = position.claimable[token];
            amounts[i] = amount;
            if (amount == 0) continue;
            position.claimable[token] = 0;
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    function claimReward(uint256 pid, address rewardToken, address receiver)
        external
        virtual
        override
        nonReentrant
        returns (uint256 amount)
    {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        Pool storage pool = _pool(pid);
        if (!_isRewardToken(pool, rewardToken)) revert Errors.RewardTokenNotRegistered();
        if (!_canClaim(pid, msg.sender)) revert Errors.StrategyNotApproved();

        _checkpoint(pid, msg.sender);

        Position storage position = positions[pid][msg.sender];
        amount = position.claimable[rewardToken];
        if (amount == 0) return 0;
        position.claimable[rewardToken] = 0;
        IERC20(rewardToken).safeTransfer(receiver, amount);
    }

    function balanceOf(uint256 pid, address strategy) external view virtual override returns (uint256) {
        return positions[pid][strategy].principal;
    }

    function pendingRewards(uint256 pid, address strategy)
        external
        view
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        Pool storage pool = _pool(pid);
        Position storage position = positions[pid][strategy];
        tokens = pool.rewardTokens;
        amounts = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 accumulated = position.principal * accRewardPerShare[pid][token] / ACC_PRECISION;
            uint256 pending = accumulated > position.rewardDebt[token] ? accumulated - position.rewardDebt[token] : 0;
            amounts[i] = position.claimable[token] + pending;
        }
    }

    function _pool(uint256 pid) internal view returns (Pool storage pool) {
        if (pid >= pools.length) revert Errors.InvalidPool();
        pool = pools[pid];
    }

    function _checkpoint(uint256 pid, address strategy) internal {
        Pool storage pool = _pool(pid);
        Position storage position = positions[pid][strategy];
        uint256 principal = position.principal;

        for (uint256 i; i < pool.rewardTokens.length; i++) {
            address token = pool.rewardTokens[i];
            uint256 accumulated = principal * accRewardPerShare[pid][token] / ACC_PRECISION;
            uint256 debt = position.rewardDebt[token];
            if (accumulated > debt) {
                position.claimable[token] += accumulated - debt;
            }
            position.rewardDebt[token] = position.principal * accRewardPerShare[pid][token] / ACC_PRECISION;
        }
    }

    function _syncRewardDebt(uint256 pid, address strategy) internal {
        Pool storage pool = _pool(pid);
        Position storage position = positions[pid][strategy];
        for (uint256 i; i < pool.rewardTokens.length; i++) {
            address token = pool.rewardTokens[i];
            position.rewardDebt[token] = position.principal * accRewardPerShare[pid][token] / ACC_PRECISION;
        }
    }

    function _canClaim(uint256 pid, address strategy) internal view returns (bool) {
        Pool storage pool = _pool(pid);
        Position storage position = positions[pid][strategy];
        if (approvedStrategy[pid][strategy] || position.principal > 0) return true;

        for (uint256 i; i < pool.rewardTokens.length; i++) {
            if (position.claimable[pool.rewardTokens[i]] > 0) return true;
        }

        return false;
    }

    function _validateFeeConfig(FeeConfig calldata config) internal pure {
        uint256 totalFeeBps = config.platformFeeBps + config.vlSdtReserveFeeBps;
        if (totalFeeBps > MAX_TOTAL_FEE_BPS) revert Errors.InvalidFee();
        if (config.platformFeeBps > 0 && config.platformFeeRecipient == address(0)) revert Errors.ZeroAddress();
        if (config.vlSdtReserveFeeBps > 0 && config.vlSdtReserveRecipient == address(0)) revert Errors.ZeroAddress();
    }

    function _chargeFees(uint256 pid, address token, uint256 amount) internal returns (uint256 net) {
        FeeConfig memory config = poolFeeConfigSet[pid] ? poolFeeConfig[pid] : feeConfig;
        uint256 totalFeeBps = config.platformFeeBps + config.vlSdtReserveFeeBps;
        if (amount == 0 || totalFeeBps == 0) return amount;

        uint256 platformFee = amount * config.platformFeeBps / FEE_DENOMINATOR;
        uint256 reserveFee = amount * config.vlSdtReserveFeeBps / FEE_DENOMINATOR;

        if (platformFee > 0 && config.platformFeeRecipient != address(0)) {
            IERC20(token).safeTransfer(config.platformFeeRecipient, platformFee);
        }
        if (reserveFee > 0 && config.vlSdtReserveRecipient != address(0)) {
            IERC20(token).safeTransfer(config.vlSdtReserveRecipient, reserveFee);
        }

        net = amount - platformFee - reserveFee;
    }
}
