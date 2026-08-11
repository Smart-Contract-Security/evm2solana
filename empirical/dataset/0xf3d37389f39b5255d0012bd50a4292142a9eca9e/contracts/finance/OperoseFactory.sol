// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IOperoseAdapter.sol";

contract OperoseFactory is OwnableUpgradeable {
  mapping(address => bytes32) public tokenAdapterMap;
  mapping(bytes32 => address) public adapterMap;
  mapping(bytes32 => address) public strategyBeaconMap;
  mapping(address => bool) public aggregatorMap;

  error InvalidAdapter(string adapterName);
  error StrategyNotFound(string strategy);
  error StrategyAlreadyExists(string strategy);

  event AdapterSet(string adapterName, address adapterAddress);
  event TokenAdapterSet(address token, string adapterName);

  function initialize() external initializer {
    __Ownable_init(msg.sender);
  }

  function getAdapter(string memory name) public view returns (address) {
    return adapterMap[keccak256(bytes(name))];
  }

  function getTokenAdapter(address token) public view returns (address adapter) {
    adapter = adapterMap[tokenAdapterMap[token]];
  }

  function getBaseCount(address token) public view returns (uint256 count) {
    IOperoseAdapter adapter = IOperoseAdapter(getTokenAdapter(token));
    if (address(adapter) == address(0)) return 1; 
    address[] memory baseTokens = adapter.getBaseTokens(token);
    for (uint256 i = 0; i < baseTokens.length; ++i) {
      count += getBaseCount(baseTokens[i]);
    }
  }

  function _fillBaseTokens(address token, address[] memory tokens, uint256 index) private view returns (uint256) {
    IOperoseAdapter adapter = IOperoseAdapter(getTokenAdapter(token));
    if (address(adapter) == address(0)) {
      tokens[index] = token;
      return index + 1;
    }
    address[] memory baseTokens = adapter.getBaseTokens(token);
    for (uint256 i = 0; i < baseTokens.length; ++i) {
      index = _fillBaseTokens(baseTokens[i], tokens, index);
    }
    return index;
  }

  function getBaseTokens(address token) public view returns (address[] memory tokens) {
    uint256 count = getBaseCount(token);
    tokens = new address[](count);
    _fillBaseTokens(token, tokens, 0);
  }

  function _fillBaseRatios(address token, uint256 ratio, uint256[] memory ratios, uint256 index) private view returns (uint256) {
    IOperoseAdapter adapter = IOperoseAdapter(getTokenAdapter(token));
    if (address(adapter) == address(0)) {
      ratios[index] = ratio;
      return index + 1;
    }
    address[] memory baseTokens = adapter.getBaseTokens(token);
    uint256[] memory baseRatios = adapter.getBaseRatios(token);
    for (uint256 i = 0; i < baseTokens.length; ++i) {
      index = _fillBaseRatios(baseTokens[i], (baseRatios[i] * ratio) / 1e18, ratios, index);
    }
    return index;
  }

  function getBaseRatios(address token) public view returns (uint256[] memory ratios) {
    uint256 count = getBaseCount(token);
    ratios = new uint256[](count);
    _fillBaseRatios(token, 1e18, ratios, 0);
  }

  function _fillBaseAmounts(address token, uint256 amount, uint256[] memory amounts, uint256 index) private view returns (uint256) {
    IOperoseAdapter adapter = IOperoseAdapter(getTokenAdapter(token));
    if (address(adapter) == address(0)) {
      amounts[index] = amount;
      return index + 1;
    }
    address[] memory baseTokens = adapter.getBaseTokens(token);
    uint256[] memory baseAmounts = adapter.getBaseAmounts(token, amount);
    for (uint256 i = 0; i < baseTokens.length; ++i) {
      index = _fillBaseAmounts(baseTokens[i], baseAmounts[i], amounts, index);
    }
    return index;
  }

  function getBaseAmounts(address token, uint256 amount) public view returns (uint256[] memory amounts) {
    uint256 count = getBaseCount(token);
    amounts = new uint256[](count);
    _fillBaseAmounts(token, amount, amounts, 0);
  }

  function getStrategyImplementation(string calldata strategy) external view returns (address) {
    return UpgradeableBeacon(strategyBeaconMap[keccak256(bytes(strategy))]).implementation();
  }

  function setAdapter(string memory adapterName, address adapterAddress) public onlyOwner {
    if (bytes(adapterName).length == 0) revert InvalidAdapter(adapterName);
    adapterMap[keccak256(bytes(adapterName))] = adapterAddress;
    emit AdapterSet(adapterName, adapterAddress);
  }

  function setTokenAdapter(address token, string memory adapterName) public onlyOwner {
    if (bytes(adapterName).length == 0) revert InvalidAdapter(adapterName);
    tokenAdapterMap[token] = keccak256(bytes(adapterName));
    emit TokenAdapterSet(token, adapterName);
  }

  function addStrategyBeacon(string calldata strategy, address implementation) external onlyOwner {
    if (address(strategyBeaconMap[keccak256(bytes(strategy))]) != address(0))
      revert StrategyAlreadyExists(strategy);
    strategyBeaconMap[keccak256(bytes(strategy))] = address(new UpgradeableBeacon(implementation, address(this)));
  }

  function upgradeStrategyBeacon(string calldata strategy, address implementation) external onlyOwner {
    address beacon = strategyBeaconMap[keccak256(bytes(strategy))];
    if (beacon == address(0))
      revert StrategyNotFound(strategy);
    UpgradeableBeacon(beacon).upgradeTo(implementation);
  }

  function createStrategyProxy(string calldata strategy) external onlyOwner returns (address proxy) {
    address beacon = strategyBeaconMap[keccak256(bytes(strategy))];
    if (beacon == address(0))
      revert StrategyNotFound(strategy);
    proxy = address(new BeaconProxy(beacon, ""));
  }

  function setAggregator(address aggregator, bool enabled) external onlyOwner {
    aggregatorMap[aggregator] = enabled;
  }
}