// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AscentHook} from "./AscentHook.sol";
import {IPoolManager} from "./v4/IPoolManager.sol";

/// @notice CREATE2 deploy helper (same pattern as Uniswap v4 periphery scripts).
contract AscentHookDeployer {
    function deployHook(
        bytes32 salt,
        IPoolManager poolManager,
        address owner,
        address posm,
        address permit2
    ) external returns (AscentHook hook) {
        hook = new AscentHook{salt: salt}(poolManager, owner, posm, permit2);
    }
}
