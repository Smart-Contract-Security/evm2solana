// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract OperoseStrategy is OwnableUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20;
  
  address public vault;
  address public defiToken;
  address[] internal rewardTokens;

  error NotVault(address sender);
  error AdapterZapFailed();

  error AggregatorNotEnabled(address aggregator);
  error InvalidSwapToken(address expected, address actual);

  function name() public virtual returns (string memory);
  function version() public virtual returns (string memory);
  function getTvl() public view virtual returns (uint256 tvl) { }
  function deposit(uint256 defiAmount) external virtual;
  function withdraw(uint256 defiAmount) external virtual;
  function getClaimable(address token) public virtual view returns (uint256 amount) { }
  function claimRewards() public virtual { }

  function _initialize(address _vault, address _defiToken) internal onlyInitializing {
    vault = _vault;
    defiToken = _defiToken;

    __Ownable_init(msg.sender);
    __Pausable_init();
  }

  function setRewardTokens(address[] calldata tokens) external onlyOwner {
    rewardTokens = tokens;
  }

  function getBalance() public view virtual returns (uint256 balance) {
    balance = IERC20(defiToken).balanceOf(address(this));
  }

  function getRewardTokens() public view virtual returns (address[] memory tokens) {
    tokens = rewardTokens;
  }

  function getRewardBalances() external view returns (uint256[] memory balances) {
    balances = new uint256[](rewardTokens.length);
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      balances[i] = IERC20(rewardTokens[i]).balanceOf(address(this)) + getClaimable(rewardTokens[i]);
    }
  }

  function transferRewardsToVault() external onlyVault whenNotPaused {
    claimRewards();
    for (uint256 i = 0; i < rewardTokens.length; ++i) {
      uint256 rewardBalance = IERC20(rewardTokens[i]).balanceOf(address(this));
      if (rewardBalance > 0) IERC20(rewardTokens[i]).safeTransfer(vault, rewardBalance);
    }
  }

  modifier onlyVault() {
    if (_msgSender() != vault)
      revert NotVault(msg.sender);
    _;
  }
}