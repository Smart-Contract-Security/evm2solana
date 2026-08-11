// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "./PoolKey.sol";

type PoolId is bytes32;

library PoolIdLibrary {
    function toId(PoolKey calldata key) internal pure returns (PoolId) {
        return PoolId.wrap(keccak256(abi.encode(key)));
    }
}
