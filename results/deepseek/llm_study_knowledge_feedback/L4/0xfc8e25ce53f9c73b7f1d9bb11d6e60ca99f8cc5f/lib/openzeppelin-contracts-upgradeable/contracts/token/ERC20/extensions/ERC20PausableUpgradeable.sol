// SPDX-License-Identifier: MIT

import {Initializable} from "../../../proxy/utils/Initializable.sol";

abstract contract ERC20PausableUpgradeable is Initializable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _pause(address account) internal virtual whenNotPaused {
        _paused = true;
        emit Paused(account);
    }

    function _unpause(address account) internal virtual whenPaused {
        _paused = false;
        emit Unpaused(account);
    }

    function _update(address from, address to, uint64 value) internal virtual whenNotPaused {
        // ERC20 _update logic should be implemented here or in a derived contract
    }
}