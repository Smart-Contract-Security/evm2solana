// SPDX-License-Identifier: MIT

import {ERC20} from "../ERC20.sol";
import {Pausable} from "../../../utils/Pausable.sol";

abstract contract ERC20Pausable is ERC20, Pausable {
    function _update(address from, address to, uint64 value) internal virtual override(ERC20, Pausable) {
        require(!paused(), "Pausable: paused");
        super._update(from, to, value);
    }
}