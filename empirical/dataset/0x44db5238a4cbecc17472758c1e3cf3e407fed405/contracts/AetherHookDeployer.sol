// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AetherHook} from "./AetherHook.sol";
import {IPoolManager} from "./v4/IPoolManager.sol";

contract AetherHookDeployer {
    function deployHook(
        bytes32 salt,
        IPoolManager poolManager,
        address owner,
        address posm,
        address permit2
    ) external returns (AetherHook hook) {
        hook = new AetherHook{salt: salt}(poolManager, owner, posm, permit2);
    }
}
