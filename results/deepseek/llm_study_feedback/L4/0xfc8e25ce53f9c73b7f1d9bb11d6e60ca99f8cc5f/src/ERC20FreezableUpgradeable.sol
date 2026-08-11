// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.22;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

abstract contract ERC20FreezableUpgradeable is ERC20Upgradeable {
    struct ERC20FreezableUpgradeableStorage {
        mapping(address => uint256) _frozen;
    }

    bytes32 private constant ERC20FreezableUpgradeableStorageLocation =
        0x3fa3c15e60cd35140c36fb837aa364f49ac6961def966d04c318a640c7984100;

    function _getERC20FreezableStorage() private view returns (ERC20FreezableUpgradeableStorage storage $) {
        bytes32 slot = ERC20FreezableUpgradeableStorageLocation;
        assembly {
            $.slot := slot
        }
    }

    event TokensFrozen(address indexed user, uint256 amount);
    event TokensUnfrozen(address indexed user, uint256 amount);

    modifier onlyFreezer() {
        require(_isFreezer(msg.sender), "ERC20NotFreezer");
        _;
    }

    function frozen(address user) public view virtual returns (uint256) {
        ERC20FreezableUpgradeableStorage storage $ = _getERC20FreezableStorage();
        return $._frozen[user];
    }

    function freeze(address user, uint256 amount) external virtual onlyFreezer {
        require(availableBalance(user) >= amount, "ERC20InsufficientUnfrozenBalance");
        ERC20FreezableUpgradeableStorage storage $ = _getERC20FreezableStorage();
        $._frozen[user] = amount;
        emit TokensFrozen(user, amount);
    }

    function availableBalance(address account) public view returns (uint256 available) {
        available = balanceOf(account) - frozen(account);
    }

    function _isFreezer(address user) internal view virtual returns (bool);

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && availableBalance(from) < value) {
            require(false, "ERC20InsufficientUnfrozenBalance");
        }
        super._update(from, to, value);
    }
}