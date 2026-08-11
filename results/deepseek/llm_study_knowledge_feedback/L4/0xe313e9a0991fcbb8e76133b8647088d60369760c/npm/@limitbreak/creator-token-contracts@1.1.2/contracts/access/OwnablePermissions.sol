// SPDX-License-Identifier: MIT

import 'solana';

abstract contract OwnablePermissions {
    function _requireCallerIsContractOwner() internal view virtual;
}