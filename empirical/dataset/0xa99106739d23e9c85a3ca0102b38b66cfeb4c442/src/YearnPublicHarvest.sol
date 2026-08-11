// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IYearnVaultV3} from "./interfaces/IYearnVaultV3.sol";

interface IYearnReportStrategy {
    function report() external returns (uint256 profit, uint256 loss);
}

interface IStrategyPublicHarvestFee {
    function preparePublicHarvestFee(address receiver) external;
}

contract YearnPublicHarvest {
    uint256 public constant STALE_PERIOD = 7 days;

    IYearnVaultV3 public immutable vault;
    address public immutable strategy;

    address public owner;
    mapping(address => bool) public keepers;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event KeeperSet(address indexed keeper, bool allowed);
    event Harvest(address indexed caller, uint256 strategyProfit, uint256 strategyLoss, uint256 vaultGain, uint256 vaultLoss);
    event PublicHarvest(
        address indexed caller, uint256 strategyProfit, uint256 strategyLoss, uint256 vaultGain, uint256 vaultLoss
    );

    error NotOwner();
    error NotAuthorized();
    error ZeroAddress();
    error NotStale();

    constructor(address vault_, address strategy_, address owner_) {
        if (vault_ == address(0) || strategy_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        vault = IYearnVaultV3(vault_);
        strategy = strategy_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && !keepers[msg.sender]) revert NotAuthorized();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setKeeper(address keeper, bool allowed) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        keepers[keeper] = allowed;
        emit KeeperSet(keeper, allowed);
    }

    function harvest()
        external
        onlyAuthorized
        returns (uint256 strategyProfit, uint256 strategyLoss, uint256 vaultGain, uint256 vaultLoss)
    {
        (strategyProfit, strategyLoss, vaultGain, vaultLoss) = _harvest();
        emit Harvest(msg.sender, strategyProfit, strategyLoss, vaultGain, vaultLoss);
    }

    function publicHarvest()
        external
        returns (uint256 strategyProfit, uint256 strategyLoss, uint256 vaultGain, uint256 vaultLoss)
    {
        if (!isStale()) revert NotStale();
        IStrategyPublicHarvestFee(strategy).preparePublicHarvestFee(msg.sender);
        (strategyProfit, strategyLoss, vaultGain, vaultLoss) = _harvest();
        emit PublicHarvest(msg.sender, strategyProfit, strategyLoss, vaultGain, vaultLoss);
    }

    function isStale() public view returns (bool) {
        IYearnVaultV3.StrategyParams memory params = vault.strategies(strategy);
        return params.lastReport + STALE_PERIOD <= block.timestamp;
    }

    function _harvest()
        internal
        returns (uint256 strategyProfit, uint256 strategyLoss, uint256 vaultGain, uint256 vaultLoss)
    {
        (strategyProfit, strategyLoss) = IYearnReportStrategy(strategy).report();
        (vaultGain, vaultLoss) = vault.process_report(strategy);
    }
}
