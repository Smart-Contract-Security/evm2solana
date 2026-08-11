// SPDX-License-Identifier: MIT

import {Ownable} from "./Ownable.sol";

abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address previousOwner, address newOwner);

    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    function acceptOwnership() public virtual {
        address sender = tx.accounts.dataAccount.key;
        if (pendingOwner() != sender) {
            revert();
        }
        _transferOwnership(sender);
    }
}