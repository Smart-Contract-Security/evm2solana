// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "./IHooks.sol";

abstract contract BaseHook is IHooks {
    bytes4 internal constant SELECTOR_OK = bytes4(0x00000000);

    function getHookPermissions() public view virtual override returns (Permissions memory) {
        return Permissions(false, false, false, false, false, false, false, false);
    }

    function beforeInitialize(address, bytes32, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
    function afterInitialize(address, bytes32, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
    function beforeAddLiquidity(address, bytes32, uint256, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
    function afterAddLiquidity(address, bytes32, uint256, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
    function beforeRemoveLiquidity(address, bytes32, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
    function afterRemoveLiquidity(address, bytes32, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
    function beforeSwap(address, bytes32, bool, uint256)
        external
        virtual
        override
        returns (bytes4, uint16)
    {
        return (SELECTOR_OK, 0);
    }
    function afterSwap(address, bytes32, bool, uint256, uint256) external virtual override returns (bytes4) {
        return SELECTOR_OK;
    }
}
