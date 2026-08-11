// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MindHook} from "./MindHook.sol";
import {IPoolManager} from "./v4/IPoolManager.sol";

contract MindHookDeployer {
    function deployHook(
        bytes32 salt,
        IPoolManager poolManager,
        address owner,
        address posm,
        address permit2
    ) external returns (MindHook hook) {
        hook = new MindHook{salt: salt}(poolManager, owner, posm, permit2);
    }
}
