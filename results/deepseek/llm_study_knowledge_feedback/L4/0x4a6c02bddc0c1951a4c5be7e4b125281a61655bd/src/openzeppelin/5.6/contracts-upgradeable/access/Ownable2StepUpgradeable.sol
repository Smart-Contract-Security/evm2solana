// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (access/Ownable2Step.sol)

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "../proxy/utils/Initializable.sol";

abstract contract Ownable2StepUpgradeable is Initializable, OwnableUpgradeable {
    struct Ownable2StepStorage {
        address _pendingOwner;
    }

    bytes32 private constant Ownable2StepStorageLocation = hex"237e158222e3e6968b72b9db0d8043aacf074ad9f650f0d1606b4d82ee432c00";

    function _getOwnable2StepStorage() private pure returns (Ownable2StepStorage storage $) {
        assembly {
            $.slot := Ownable2StepStorageLocation
        }
    }

    event OwnershipTransferStarted(address previousOwner, address newOwner);

    function __Ownable2Step_init() internal onlyInitializing {
    }

    function __Ownable2Step_init_unchained() internal onlyInitializing {
    }

    function pendingOwner() public view virtual returns (address) {
        Ownable2StepStorage storage $ = _getOwnable2StepStorage();
        return $._pendingOwner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        Ownable2StepStorage storage $ = _getOwnable2StepStorage();
        $._pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        Ownable2StepStorage storage $ = _getOwnable2StepStorage();
        delete $._pendingOwner;
        OwnableUpgradeable._transferOwnership(newOwner);
    }

    function acceptOwnership() public virtual {
        address sender = tx.accounts.dataAccount.key;
        if (pendingOwner() != sender) {
            revert();
        }
        _transferOwnership(sender);
    }
}