// SPDX-License-Identifier: UNLICENSED

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

abstract contract ERC20FreezableUpgradeable is ERC20Upgradeable {
    struct ERC20FreezableUpgradeableStorage {
        mapping(address user => uint64 amount) _frozen;
    }

    bytes32 private constant ERC20FreezableUpgradeableStorageLocation =
        0x3fa3c15e60cd35140c36fb837aa364f49ac6961def966d04c318a640c7984100;

    function _getERC20FreezableStorage() private view returns (ERC20FreezableUpgradeableStorage storage $) {
        assembly {
            $.slot := ERC20FreezableUpgradeableStorageLocation
        }
    }

    event TokensFrozen(address indexed user, uint64 amount);
    event TokensUnfrozen(address indexed user, uint64 amount);

    uint64 constant ERROR_INSUFFICIENT_UNFROZEN = 1;
    uint64 constant ERROR_INSUFFICIENT_FROZEN = 2;
    uint64 constant ERROR_NOT_FREEZER = 3;

    modifier onlyFreezer() {
        if (!_isFreezer(tx.accounts.dataAccount.key)) {
            revert();
        }
        _;
    }

    function frozen(address user) public view virtual returns (uint64) {
        ERC20FreezableUpgradeableStorage storage $ = _getERC20FreezableStorage();
        return $._frozen[user];
    }

    function freeze(address user, uint64 amount) external virtual onlyFreezer {
        if (availableBalance(user) < amount) {
            revert();
        }
        ERC20FreezableUpgradeableStorage storage $ = _getERC20FreezableStorage();
        $._frozen[user] = amount;
        emit TokensFrozen(user, amount);
    }

    function availableBalance(address account) public view returns (uint64 available) {
        available = balanceOf(account) - frozen(account);
    }

    function _isFreezer(address user) internal view virtual returns (bool);

    function _update(address from, address to, uint64 value) internal virtual override {
        if (from != address(0) && availableBalance(from) < value) {
            revert();
        }
        super._update(from, to, value);
    }
}