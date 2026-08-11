// SPDX-License-Identifier: MIT

import {IBeacon} from "./IBeacon.sol";
import {ERC1967Utils} from "../ERC1967/ERC1967Utils.sol";

contract BeaconProxy {
    address private immutable _beacon;

    @payer(payer)
    @space(0)
    constructor(address beacon, bytes memory data) {
        ERC1967Utils.upgradeBeaconToAndCall(beacon, data);
        _beacon = beacon;
    }

    function _implementation() internal view returns (address) {
        return IBeacon(_getBeacon()).implementation();
    }

    function _getBeacon() internal view returns (address) {
        return _beacon;
    }

    fallback() external {
        address impl = _implementation();
        (bool success, bytes memory returndata) = impl.call{value: 0}(msg.data);
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            } else {
                revert();
            }
        }
        assembly {
            return(add(returndata, 32), mload(returndata))
        }
    }
}