// SPDX-License-Identifier: MIT

import 'solana';

interface IVault {
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function totalSharesX18() external view returns (uint64);
    function totalLpClaims() external view returns (uint64);
    function userSharesX18(address user) external view returns (uint64);
    function assetBalance() external view returns (uint64);
    function protocolInventory() external view returns (uint64);

    function deposit(uint64 amount, address receiver) external returns (uint64 sharesMinted);
    function withdraw(uint64 shares, address receiver) external returns (uint64 amountOut);

    // Router-only
    function pullTo(address receiver, uint64 amount) external;

    // Treasury-only
    function seedInventory(uint64 amount) external;
    function withdrawInventory(uint64 amount, address receiver) external;

    event Deposit(address user, address receiver, uint64 amount, uint64 sharesMinted);
    event Withdraw(address user, address receiver, uint64 amount, uint64 sharesBurned);
    event InventorySeeded(uint64 amount);
    event InventoryWithdrawn(address receiver, uint64 amount);
}