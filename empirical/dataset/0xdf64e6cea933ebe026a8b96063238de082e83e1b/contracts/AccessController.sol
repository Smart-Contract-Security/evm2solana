// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {Errors} from "./libs/Errors.sol";

/// @notice Central role and pause registry. Used by every other Stablehouse contract.
contract AccessController is AccessControl, IAccessController {
    bytes32 public constant GUARDIAN_ROLE         = keccak256("GUARDIAN_ROLE");
    bytes32 public constant PARAM_MANAGER_ROLE    = keccak256("PARAM_MANAGER_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant ROUTER_ROLE           = keccak256("ROUTER_ROLE");
    bytes32 public constant ADMIN_ROLE            = keccak256("ADMIN_ROLE");

    bool public globalSwapsPaused;

    // assetPaused[asset][scope]
    mapping(address => mapping(PauseScope => bool)) private _assetPaused;

    // pairPaused[hash(a,b)]
    mapping(bytes32 => bool) private _pairPaused;

    event GlobalSwapsPaused(bool paused, string reason);
    event AssetPaused(address indexed asset, PauseScope scope, bool paused, string reason);
    event PairPaused(address indexed a, address indexed b, bool paused, string reason);

    constructor(address admin) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);
        _grantRole(PARAM_MANAGER_ROLE, admin);
        _grantRole(TREASURY_MANAGER_ROLE, admin);
    }

    function hasRole(bytes32 role, address account)
        public
        view
        override(AccessControl, IAccessController)
        returns (bool)
    {
        return super.hasRole(role, account);
    }

    /* ------------------------- pause controls ------------------------- */

    function setGlobalSwapsPaused(bool paused, string calldata reason) external onlyRole(GUARDIAN_ROLE) {
        globalSwapsPaused = paused;
        emit GlobalSwapsPaused(paused, reason);
    }

    function setAssetPaused(address asset, PauseScope scope, bool paused, string calldata reason)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (scope == PauseScope.All) {
            _assetPaused[asset][PauseScope.Deposits] = paused;
            _assetPaused[asset][PauseScope.Withdrawals] = paused;
            _assetPaused[asset][PauseScope.Swaps] = paused;
        } else {
            _assetPaused[asset][scope] = paused;
        }
        emit AssetPaused(asset, scope, paused, reason);
    }

    function setPairPaused(address a, address b, bool paused, string calldata reason)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        if (a == address(0) || b == address(0)) revert Errors.ZeroAddress();
        bytes32 key = _pairKey(a, b);
        _pairPaused[key] = paused;
        emit PairPaused(a, b, paused, reason);
    }

    function assetPaused(address asset, PauseScope scope) external view returns (bool) {
        return _assetPaused[asset][scope];
    }

    function pairPaused(address a, address b) external view returns (bool) {
        return _pairPaused[_pairKey(a, b)];
    }

    function _pairKey(address a, address b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
