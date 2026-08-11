// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IVault {
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function totalSharesX18() external view returns (uint256);
    function totalLpClaims() external view returns (uint256);
    function userSharesX18(address user) external view returns (uint256);
    function assetBalance() external view returns (uint256);
    function protocolInventory() external view returns (uint256);

    function deposit(uint256 amount, address receiver) external returns (uint256 sharesMinted);
    function withdraw(uint256 shares, address receiver) external returns (uint256 amountOut);

    // Router-only
    function pullTo(address receiver, uint256 amount) external;

    // Treasury-only
    function seedInventory(uint256 amount) external;
    function withdrawInventory(uint256 amount, address receiver) external;

    event Deposit(address indexed user, address indexed receiver, uint256 amount, uint256 sharesMinted);
    event Withdraw(address indexed user, address indexed receiver, uint256 amount, uint256 sharesBurned);
    event InventorySeeded(uint256 amount);
    event InventoryWithdrawn(address indexed receiver, uint256 amount);
}
