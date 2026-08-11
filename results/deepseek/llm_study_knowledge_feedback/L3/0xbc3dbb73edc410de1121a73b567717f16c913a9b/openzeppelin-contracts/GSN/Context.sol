// SPDX-License-Identifier: MIT

import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes memory) {
        return msg.data;
    }
}