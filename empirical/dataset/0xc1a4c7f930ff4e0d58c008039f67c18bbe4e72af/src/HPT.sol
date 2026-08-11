// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "./interfaces/IVault.sol";

/// @notice Vault share token. Mint/burn restricted to the Vault. Freely
/// transferable, but transfers call back into the Vault so per-user cost basis
/// can be moved with the shares (prevents wash-cycling gains to a fresh
/// address before withdrawing). See PLAN §2.1 / §6.4.
contract HPT is ERC20 {
    address public immutable vault;

    error OnlyVault();

    constructor(address _vault) ERC20("HPT Vault Share", "HPT") {
        vault = _vault;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }

    /// @dev Notifies the vault on user-to-user transfers so it can move cost
    /// basis with the shares. Mints/burns are skipped — the vault sets basis
    /// directly on those paths.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0) && to != address(0) && value != 0) {
            IVault(vault).onShareTransfer(from, to, value);
        }
    }
}
