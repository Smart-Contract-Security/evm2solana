// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IERC4626Minimal {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
}

interface IRateProvider {
    function getRate() external view returns (uint256);
}

interface IERC4626RateProvider is IRateProvider {
    function erc4626() external view returns (address);
}

interface IChainlinkRateProvider is IRateProvider {
    function pricefeed() external view returns (address);
}

interface IAaveMarketRateTransformer is IERC4626RateProvider {
    function vaultAssetFeed() external view returns (address);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}