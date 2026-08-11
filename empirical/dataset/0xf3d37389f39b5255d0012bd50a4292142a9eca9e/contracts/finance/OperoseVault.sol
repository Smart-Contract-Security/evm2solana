// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/ArbSys.sol";
import "./OperoseFactory.sol";
import "./OperoseStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OperoseVault is OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  struct SwapInfo {
    address srcToken;
    address dstToken;
    uint256 amount;
    address aggregator;
    bytes data;
  }

  struct VaultAuth {
    bytes32 nonce;
    uint256 deadline;
    uint256 amount;
    SwapInfo[] vaultSwaps;
    SwapInfo[] compoundSwaps;
  }

  struct VaultStats {
    uint256 tvl;
    uint256 growthIndex;
    uint256 shares;
    uint256 balance;
    address[] baseTokens;
    uint256[] baseBalances;
  }

  struct UserStats {
    uint256 shares;
    uint256 balance;
    address[] baseTokens;
    uint256[] baseBalances;
  }

  address private constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  uint256 private constant SHARES_SCALAR = 1e10;

  mapping(bytes32 => bool) public nonceUsed;
  string public name;
  address public factory;
  address public strategy;
  mapping(address => uint256) public userShares;
  uint256 public totalShares;

  uint256 public yieldFee;
  uint256 public uncollectedFees;
  uint256 public lastBalance;
  uint256 public lastGrowthIndex;
  mapping(address => uint256) public lastAdapterGrowthIndexMap;

  event Deposit(
    address indexed user,
    uint256 shares,
    uint256 amount,
    address zapToken,
    uint256 zapAmount,
    uint256 userShares,
    uint256 vaultShares,
    uint256 vaultBalanceBefore,
    uint256 vaultBalanceAfter,
    address[] baseTokens,
    uint256[] baseBalancesBefore,
    uint256[] baseBalancesAfter,
    uint256 timestamp
  );

  event Withdraw(
    address indexed user,
    uint256 shares,
    uint256 amount,
    address zapToken,
    uint256 zapAmount,
    uint256 userShares,
    uint256 vaultShares,
    uint256 vaultBalanceBefore,
    uint256 vaultBalanceAfter,
    address[] baseTokens,
    uint256[] baseBalancesBefore,
    uint256[] baseBalancesAfter,
    uint256 timestamp
  );

  error SwapFailed(SwapInfo swap, address srcAccount, address dstAccount);
  error InvalidSwapSrcBalance(uint256 srcBefore, uint256 srcAfter);
  error InvalidSwapDstBalance(uint256 dstBefore, uint256 dstAfter);
  error InvalidYieldFee(uint256 value);
  error AdapterZapFailed();
  error AggregatorNotEnabled(address aggregator);
  error InvalidAuthorization(string reason);
  error NonceAlreadyUsed(bytes32 nonce);
  error AuthorizationExpired(uint256 deadline);
  error InsufficientShares(uint256 requested, uint256 available);
  error SwapLengthMismatch(uint256 expected, uint256 actual);
  error InvalidSwapToken(address expected, address actual);

  function initialize(address _factory, string memory _name, address _strategy) external initializer {
    factory = _factory;
    name = _name;
    strategy = _strategy;
    yieldFee = 10e4;
    lastGrowthIndex = 1e18;
    __Ownable_init(msg.sender);
    __ReentrancyGuard_init();
  }

  function setYieldFee(uint256 value) external onlyOwner {
    if (value > 30e4) revert InvalidYieldFee(value);
    yieldFee = value;
  }

  function setName(string memory value) external onlyOwner {
    name = value;
  }

  function version() external pure returns (string memory) {
    return "1.0.0";
  }

  function getDefiToken() public view returns (address defiToken) {
    defiToken = OperoseStrategy(strategy).defiToken();
  }

  function getBaseTokens() public view virtual returns (address[] memory baseTokens) {
    baseTokens = OperoseFactory(factory).getBaseTokens(getDefiToken());
  }

  function getBaseRatios() external view virtual returns (uint256[] memory baseRatios) {
    baseRatios = OperoseFactory(factory).getBaseRatios(getDefiToken());
  }

  function getBaseAmounts(uint256 defiAmount) public view virtual returns (uint256[] memory baseAmounts) {
    baseAmounts = OperoseFactory(factory).getBaseAmounts(getDefiToken(), defiAmount);
  }

  function sharesToValue(uint256 shares) public view returns (uint256 value) {
    value = totalShares == 0 ? 0 : (shares * getBalance()) / totalShares;
  }

  function sharesToBaseAmounts(uint256 shares) external view returns (uint256[] memory baseAmounts) {
    baseAmounts = getBaseAmounts(sharesToValue(shares));
  }

  function getBalance() public view virtual returns (uint256 balance) {
    balance = OperoseStrategy(strategy).getBalance() - uncollectedFees;
  }

  function getBaseBalances() public view virtual returns (uint256[] memory baseBalances) {
    baseBalances = getBaseAmounts(getBalance());
  }

  function getUserBalance(address user) public view virtual returns (uint256 balance) {
    balance = sharesToValue(userShares[user]);
  }

  function getUserBaseBalances(address user) external view virtual returns (uint256[] memory baseBalances) {
    baseBalances = getBaseAmounts(getUserBalance(user));
  }

  function getRewardTokens() public view virtual returns (address[] memory tokens) {
    tokens = OperoseStrategy(strategy).getRewardTokens();
  }

  function getRewardBalances() external view returns (uint256[] memory balances) {
    balances = OperoseStrategy(strategy).getRewardBalances();
  }

  function getTvl() public view returns (uint256 tvl) {
    tvl = OperoseStrategy(strategy).getTvl();
  }

  function getBaseTvl() public view returns (uint256[] memory baseAmounts) {
    baseAmounts = getBaseAmounts(getTvl());
  }

  function getGrowthIndex() public view returns (uint256 index) {
    index = lastGrowthIndex;

    if (lastBalance > 0) {
      uint256 balance = getBalance();
      uint256 vaultYield = balance > lastBalance ? balance - lastBalance : 0;
      uint256 adapterYield = _getAdapterYield(getDefiToken(), lastBalance);
      uint256 totalYield = vaultYield + adapterYield;
      uint256 fees = totalYield > 0 ? (totalYield * yieldFee) / 1e6 : 0;

      // Δindex = lastGrowthIndex * (totalYield - fees) / lastBalance
      index = lastGrowthIndex + ((lastGrowthIndex * (totalYield - fees)) / lastBalance);
    }
  }

  function getUserStats(address user) public view returns (UserStats memory stats) {
    stats.shares = userShares[user];
    stats.balance = sharesToValue(userShares[user]);
    stats.baseTokens = getBaseTokens();
    stats.baseBalances = getBaseAmounts(stats.balance);
  }

  function getVaultStats() public view returns (uint256 timestamp, uint256 blockNumber, VaultStats memory stats) {
    timestamp = block.timestamp;
    blockNumber = ChainBlockNumber.canonicalBlockNumber();
    stats.tvl = getTvl();
    stats.growthIndex = getGrowthIndex();
    stats.shares = totalShares;
    stats.balance = getBalance();
    stats.baseTokens = getBaseTokens();
    stats.baseBalances = getBaseAmounts(stats.balance);
  }

  function compound(SwapInfo[] calldata swaps) public {
    if (swaps.length > 0) {
      OperoseStrategy(strategy).transferRewardsToVault();
      address defiToken = getDefiToken();
      uint256 defiAmount = _zapIn(defiToken, swaps);

      IERC20(defiToken).safeTransfer(strategy, defiAmount);
      OperoseStrategy(strategy).deposit(defiAmount);
      address[] memory rewardTokens = getRewardTokens();
      for (uint256 i = 0; i < rewardTokens.length; ++i) {
        uint256 rewardBalance = IERC20(rewardTokens[i]).balanceOf(address(this));
        if (rewardBalance > 0) IERC20(rewardTokens[i]).safeTransfer(strategy, rewardBalance);
      }
    }
  }

  function collectFees(SwapInfo[] calldata swaps) external onlyOwner {
    address zapToken = swaps[0].dstToken;
    uint256 zapAmount = IERC20(zapToken).balanceOf(address(this));
    OperoseStrategy(strategy).withdraw(uncollectedFees);
    _zapOut(getDefiToken(), swaps);
    zapAmount = IERC20(zapToken).balanceOf(address(this)) - zapAmount;
    if (!_isNative(zapToken)) IERC20(zapToken).safeTransfer(msg.sender, zapAmount);
  }

  function deposit(VaultAuth calldata auth) external payable nonReentrant {
    compound(auth.compoundSwaps);
    _recordYield();

    uint256 balanceBefore = getBalance();
    uint256[] memory baseBalancesBefore = getBaseAmounts(balanceBefore);

    address zapToken = auth.vaultSwaps[0].srcToken;
    if (!_isNative(zapToken))
      IERC20(zapToken).safeTransferFrom(msg.sender, address(this), auth.amount);

    address defiToken = getDefiToken();
    uint256 defiAmount = _zapIn(defiToken, auth.vaultSwaps);

    uint256 shares = totalShares == 0 ? defiAmount * SHARES_SCALAR : defiAmount * totalShares / getBalance();
    userShares[msg.sender] += shares;
    totalShares += shares;

    IERC20(defiToken).safeTransfer(strategy, defiAmount);
    OperoseStrategy(strategy).deposit(defiAmount);
    lastBalance = getBalance();

    emit Deposit(
      msg.sender,
      shares,
      defiAmount,
      zapToken,
      auth.amount,
      userShares[msg.sender],
      totalShares,
      balanceBefore,
      lastBalance,
      getBaseTokens(),
      baseBalancesBefore,
      getBaseAmounts(lastBalance),
      block.timestamp);
  }

  function withdraw(VaultAuth calldata auth) external nonReentrant {
    if (userShares[msg.sender] < auth.amount)
      revert InsufficientShares(auth.amount, userShares[msg.sender]);

    compound(auth.compoundSwaps);
    _recordYield();

    uint256 balanceBefore = getBalance();
    uint256[] memory baseBalancesBefore = getBaseAmounts(balanceBefore);

    uint256 defiAmount = (auth.amount * getBalance()) / totalShares;
    userShares[msg.sender] -= auth.amount;
    totalShares -= auth.amount;

    address zapToken = auth.vaultSwaps[0].dstToken;
    uint256 zapAmount = IERC20(zapToken).balanceOf(address(this));

    OperoseStrategy(strategy).withdraw(defiAmount);
    lastBalance = getBalance();

    _zapOut(getDefiToken(), auth.vaultSwaps);
    zapAmount = IERC20(zapToken).balanceOf(address(this)) - zapAmount;

    if (!_isNative(zapToken))
      IERC20(zapToken).safeTransfer(msg.sender, zapAmount);

    emit Withdraw(msg.sender,
      auth.amount,
      defiAmount,
      zapToken,
      zapAmount,
      userShares[msg.sender],
      totalShares,
      balanceBefore,
      lastBalance,
      getBaseTokens(),
      baseBalancesBefore,
      getBaseAmounts(lastBalance),
      block.timestamp);
  }

  function _zapIn(address token, SwapInfo[] calldata swaps) private returns (uint256 amount) {
    IOperoseAdapter adapter = IOperoseAdapter(OperoseFactory(factory).getTokenAdapter(token));
    if (address(adapter) != address(0)) {
      address[] memory baseTokens = adapter.getBaseTokens(token);
      if (baseTokens[0] != token) {
        uint256[] memory baseAmounts = new uint256[](baseTokens.length);
        for (uint256 i = 0; i < baseTokens.length; ++i) {
          baseAmounts[i] += _zapIn(baseTokens[i], swaps);
        }
        amount = IERC20(token).balanceOf(address(this));
        (bool success,) = address(adapter).delegatecall(abi.encodeWithSignature("zapIn(address,uint256[])", token, baseAmounts));
        if (!success) revert AdapterZapFailed();
        return IERC20(token).balanceOf(address(this)) - amount;
      }
    }
    for (uint256 i = 0; i < swaps.length; ++i) {
      if (token == swaps[i].dstToken) {
        if (token == swaps[i].srcToken) {
          amount += swaps[i].amount;
        } else if (swaps[i].amount > 0) {
          if (!OperoseFactory(factory).aggregatorMap(swaps[i].aggregator))
            revert AggregatorNotEnabled(swaps[i].aggregator);
          amount += _executeSwap(swaps[i]);
        }
      }
    }
  }

  function _zapOut(address token, SwapInfo[] calldata swaps) private {
    IOperoseAdapter adapter = IOperoseAdapter(OperoseFactory(factory).getTokenAdapter(token));
    if (address(adapter) != address(0)) {
      address[] memory baseTokens = adapter.getBaseTokens(token);
      if (baseTokens[0] != token) {
        uint256 amount = IERC20(token).balanceOf(address(this));
        (bool success, ) = address(adapter).delegatecall(abi.encodeWithSignature("zapOut(address,uint256)", token, amount));
        if (!success) revert AdapterZapFailed();
        for (uint256 i = 0; i < baseTokens.length; ++i) {
          _zapOut(baseTokens[i], swaps);
        }
        return;
      }
    }
    for (uint256 i = 0; i < swaps.length; ++i) {
      if (token == swaps[i].srcToken && swaps[i].amount > 0) {
        if (token != swaps[i].dstToken) {
          if (!OperoseFactory(factory).aggregatorMap(swaps[i].aggregator))
            revert AggregatorNotEnabled(swaps[i].aggregator);
          _executeSwap(swaps[i]);
        }
      }
    }
  }

  function _recordYield() private {
    uint256 adapterYeild = _recordAdapterYield(getDefiToken(), lastBalance);
    if (lastBalance > 0) {
      uint256 balance = getBalance();
      uint256 vaultYield = balance > lastBalance ? balance - lastBalance : 0;
      uint256 totalYield = vaultYield + adapterYeild;
      uint256 fees = totalYield > 0 ? (totalYield * yieldFee) / 1e6 : 0;
      if (fees > 0) uncollectedFees += fees;

      // Δindex = lastGrowthIndex * (totalYield - fees) / lastBalance
      lastGrowthIndex += (lastGrowthIndex * (totalYield - fees)) / lastBalance;
      lastBalance = balance;
    }
  }

  function _recordAdapterYield(address token, uint256 affectedBalance) private returns (uint256 yield) {
    IOperoseAdapter adapter = IOperoseAdapter(OperoseFactory(factory).getTokenAdapter(token));
    if (address(adapter) != address(0)) {
      uint256 currentIndex = IOperoseAdapter(adapter).getGrowthIndex(token);
      if (currentIndex > 0) {
        uint256 lastIndex = lastAdapterGrowthIndexMap[token];
        if (lastIndex == 0) {
          lastAdapterGrowthIndexMap[token] = currentIndex;
        } else if (currentIndex > lastIndex) {
          yield = (affectedBalance * (currentIndex - lastIndex)) / lastIndex;
          lastAdapterGrowthIndexMap[token] = currentIndex;
        }
      }

      address[] memory baseTokens = adapter.getBaseTokens(token);
      if (baseTokens[0] != token) {
        uint256[] memory baseRatios = adapter.getBaseRatios(token);
        for (uint256 i = 0; i < baseTokens.length; ++i) {
          yield += _recordAdapterYield(baseTokens[i], (affectedBalance * baseRatios[i]) / 1e18);
        }
      }
    }
  }

  function _getAdapterYield(address token, uint256 affectedBalance) private view returns (uint256 yield) {
    IOperoseAdapter adapter = IOperoseAdapter(OperoseFactory(factory).getTokenAdapter(token));
    if (address(adapter) != address(0)) {
      uint256 currentIndex = IOperoseAdapter(adapter).getGrowthIndex(token);
      if (currentIndex > 0) {
        uint256 lastIndex = lastAdapterGrowthIndexMap[token];
        if (currentIndex > lastIndex && lastIndex > 0) {
          yield = (affectedBalance * (currentIndex - lastIndex)) / lastIndex;
        }
      }
      address[] memory baseTokens = adapter.getBaseTokens(token);
      if (baseTokens[0] != token) {
        uint256[] memory baseRatios = adapter.getBaseRatios(token);
        for (uint256 i = 0; i < baseTokens.length; ++i) {
          yield += _getAdapterYield(baseTokens[i], (affectedBalance * baseRatios[i]) / 1e18);
        }
      }
    }
  }

  function _executeSwap(SwapInfo calldata swap) internal returns (uint256 returnAmount) {
    if (!_isNative(swap.srcToken)) {
      SafeERC20.safeIncreaseAllowance(IERC20(swap.srcToken), swap.aggregator, swap.amount);
    }

    uint256 srcBefore = _isNative(swap.srcToken) ? address(this).balance : IERC20(swap.srcToken).balanceOf(address(this));
    uint256 dstBefore = _isNative(swap.dstToken) ? address(this).balance : IERC20(swap.dstToken).balanceOf(address(this));
    
    (bool swapSuccess, ) = _isNative(swap.srcToken) ? swap.aggregator.call{value: swap.amount}(swap.data) : swap.aggregator.call(swap.data);

    if (!swapSuccess) 
      revert SwapFailed(swap, address(this), address(this));
    
    if (!_isNative(swap.srcToken)) {
      SafeERC20.forceApprove(IERC20(swap.srcToken), swap.aggregator, 0);
    }

    uint256 srcAfter = _isNative(swap.srcToken) ? address(this).balance : IERC20(swap.srcToken).balanceOf(address(this));
    if (srcAfter >= srcBefore || (srcBefore - srcAfter) > swap.amount)
      revert InvalidSwapSrcBalance(srcBefore, srcAfter);

    uint256 dstAfter = _isNative(swap.dstToken) ? address(this).balance : IERC20(swap.dstToken).balanceOf(address(this));
    if (dstAfter <= dstBefore)
      revert InvalidSwapDstBalance(dstBefore, dstAfter);
    return dstAfter - dstBefore;
  }

  function rescueToken(address token, uint256 amount) external onlyOwner() {
    IERC20(token).safeTransfer(msg.sender, amount);
  }

  function _isNative(address token) private pure returns (bool) {
    return (token == NATIVE_TOKEN || token == address(0));
  }
}