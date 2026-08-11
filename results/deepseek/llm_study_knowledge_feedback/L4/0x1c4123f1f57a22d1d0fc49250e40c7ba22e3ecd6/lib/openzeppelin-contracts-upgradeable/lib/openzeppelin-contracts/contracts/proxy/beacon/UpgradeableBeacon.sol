// SPDX-License-Identifier: MIT

import {IBeacon} from "./IBeacon.sol";
import {Ownable} from "../../access/Ownable.sol";

contract UpgradeableBeacon is IBeacon, Ownable {
    address private _implementation;

    event Upgraded(address implementation);

    constructor(address implementation_, address initialOwner) {
        Ownable(initialOwner);
        _setImplementation(implementation_);
    }

    function implementation() public view virtual returns (address) {
        return _implementation;
    }

    function upgradeTo(address newImplementation) public virtual {
        _setImplementation(newImplementation);
    }

    function _setImplementation(address newImplementation) private {
        if (newImplementation == address(0)) {
            revert();
        }
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }
}