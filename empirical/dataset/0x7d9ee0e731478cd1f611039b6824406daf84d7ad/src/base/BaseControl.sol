// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Errors} from "../errors/Errors.sol";

/**
 * @title BaseControl
 * @dev Base access control contract providing role management,
 * pause functionality, and UUPS upgrade support.
 *
 * When a child contract inherits BaseControl, it must call
 * `_BaseControl_initialize(admin)` inside its `initialize` function.
 *
 * Example:
 *
 * function initialize(address admin) external initializer {
 *     _BaseControl_initialize(admin);
 * }
 */
abstract contract BaseControl is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard
{
    ////////////////////////////////////////////////////////////////
    //                  Role Definitions
    ////////////////////////////////////////////////////////////////

    /// @notice Business-level contract role for inter-contract calls (e.g. mint, updateBoost)
    bytes32 public constant CONTRACT_ROLE = keccak256("CONTRACT_ROLE");

    /// @notice COO role responsible for operational parameter management
    bytes32 public constant COO_ROLE = keccak256("COO_ROLE");

    /// @notice Project-side role for project withdrawal, repayment, and clearing operations
    bytes32 public constant PROJECT_ROLE = keccak256("PROJECT_ROLE");

    /// @notice Role responsible for pausing and unpausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role responsible for upgrading the contract implementation
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    ////////////////////////////////////////////////////////////////
    //                  Parameter Storage
    ////////////////////////////////////////////////////////////////

    mapping(bytes32 => uint256) private _uintParams;
    mapping(bytes32 => address) private _addressParams;

    ////////////////////////////////////////////////////////////////
    //                  Events
    ////////////////////////////////////////////////////////////////

    event ParamUpdated(bytes32 indexed paramName, uint256 value);

    ////////////////////////////////////////////////////////////////
    //                  Constructor
    ////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    ////////////////////////////////////////////////////////////////
    //                  Initialization
    ////////////////////////////////////////////////////////////////

    function _BaseControl_initialize(address admin) internal virtual onlyInitializing {
        if (admin == address(0)) revert Errors.ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COO_ROLE, admin);
        //_grantRole(PROJECT_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(CONTRACT_ROLE, admin);
    }

    ////////////////////////////////////////////////////////////////
    //                  UUPS Upgrade Authorization
    ////////////////////////////////////////////////////////////////

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert Errors.ZeroAddress();
        if (newImplementation.code.length == 0) revert Errors.ZeroAddress();
    }

    ////////////////////////////////////////////////////////////////
    //                  Uint256 Parameter Management
    ////////////////////////////////////////////////////////////////

    function _setUintParam(bytes32 paramName, uint256 value) internal virtual {
        _uintParams[paramName] = value;
        emit ParamUpdated(paramName, value);
    }

    function _getUintParam(bytes32 paramName) internal view virtual returns (uint256) {
        return _uintParams[paramName];
    }

    ////////////////////////////////////////////////////////////////
    //                  Address Parameter Management
    ////////////////////////////////////////////////////////////////

    function _setAddressParam(bytes32 paramName, address value) internal virtual {
        _addressParams[paramName] = value;
        emit ParamUpdated(paramName, uint256(uint160(value)));
    }

    function _getAddressParam(bytes32 paramName) internal view virtual returns (address) {
        return _addressParams[paramName];
    }

    ////////////////////////////////////////////////////////////////
    //                  Pause Control
    ////////////////////////////////////////////////////////////////

    function pause() external virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
