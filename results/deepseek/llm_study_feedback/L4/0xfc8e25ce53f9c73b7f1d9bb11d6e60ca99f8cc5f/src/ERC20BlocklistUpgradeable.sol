// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.22;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

abstract contract ERC20BlocklistUpgradeable is ERC20Upgradeable {
    struct ERC20BlocklistUpgradeableStorage {
        mapping(address => bool) _blocked;
    }

    bytes32 private constant ERC20BlocklistUpgradeableStorageLocation =
        0x943d6f0aae33a11bdac5b1e1fa272eeefbfbb201792466fc6e6bfcdac78e2f00;

    function _getERC20BlocklistStorage() private view returns (ERC20BlocklistUpgradeableStorage storage $) {
        assembly {
            $.slot := ERC20BlocklistUpgradeableStorageLocation
        }
    }

    event UserBlocked(address indexed user);
    event UserUnblocked(address indexed user);

    error ERC20Blocked(address user);

    function blocked(address account) public view virtual returns (bool) {
        ERC20BlocklistUpgradeableStorage storage $ = _getERC20BlocklistStorage();
        return $._blocked[account];
    }

    function _blockUser(address user) internal virtual returns (bool) {
        bool isBlocked = blocked(user);
        if (!isBlocked) {
            ERC20BlocklistUpgradeableStorage storage $ = _getERC20BlocklistStorage();
            $._blocked[user] = true;
            emit UserBlocked(user);
        }
        return isBlocked;
    }

    function _unblockUser(address user) internal virtual returns (bool) {
        bool isBlocked = blocked(user);
        if (isBlocked) {
            ERC20BlocklistUpgradeableStorage storage $ = _getERC20BlocklistStorage();
            $._blocked[user] = false;
            emit UserUnblocked(user);
        }
        return isBlocked;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (blocked(from)) {
            revert("ERC20Blocked: from address is blocked");
        }
        if (blocked(to)) {
            revert("ERC20Blocked: to address is blocked");
        }
        super._update(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        if (blocked(owner)) {
            revert("ERC20Blocked: owner address is blocked");
        }
        super._approve(owner, spender, value, emitEvent);
    }
}