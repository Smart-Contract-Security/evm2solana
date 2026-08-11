// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
