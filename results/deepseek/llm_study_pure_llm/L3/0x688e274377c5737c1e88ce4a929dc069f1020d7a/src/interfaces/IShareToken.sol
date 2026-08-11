// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IShareToken is IERC20, IERC165 {
    event VaultAdded(address indexed asset, address indexed vault);
    event VaultRemoved(address indexed asset, address indexed vault);

    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function addVault(address asset, address vault_) external;
    function removeVault(address asset) external;
    function vault(address asset) external view returns (address);
    function asset(address vault_) external view returns (address);
    function isVault(address vault_) external view returns (bool);
}