// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IStrategyInterface {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxLoss) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function report() external returns (uint256 profit, uint256 loss);
    function setProfitMaxUnlockTime(uint256 profitMaxUnlockTime) external;
    function setPerformanceFee(uint16 performanceFee) external;
}
