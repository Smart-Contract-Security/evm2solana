// SPDX-License-Identifier: MIT

import {Initializable} from "../proxy/utils/Initializable.sol";

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }

    function _msgSender() internal view virtual returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        bytes memory data = new bytes(tx.accounts.dataAccount.data.length);
        for (uint64 i = 0; i < tx.accounts.dataAccount.data.length; i++) {
            data[i] = tx.accounts.dataAccount.data[i];
        }
        return data;
    }

    function _contextSuffixLength() internal view virtual returns (uint64) {
        return 0;
    }
}