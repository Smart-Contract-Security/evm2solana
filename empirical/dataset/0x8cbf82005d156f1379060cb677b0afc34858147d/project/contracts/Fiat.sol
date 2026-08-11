// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {FiatStore} from "./FiatStore.sol";
import {FiatOptions} from "./FiatOptions.sol";

/// @custom:security-contact security@sivo.com
contract Fiat is
    Initializable,
    AccessControlEnumerableUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    FiatOptions,
    FiatStore,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Error thrown when a zero address is supplied where a non-zero address is required
    error FiatZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Options memory options) public initializer {
        if (options.owner == address(0)) revert FiatZeroAddress();
        __ERC20_init(options.name, options.symbol);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init(options.name);
        _grantRole(DEFAULT_ADMIN_ROLE, options.owner);
        _grantRole(MINTER_ROLE, options.owner);
        _grantRole(PAUSER_ROLE, options.owner);
        FiatStorage storage $ = _getFiatStorage();
        $.decimals = options.decimals;
    }

    function decimals() public view override returns (uint8) {
        FiatStorage storage $ = _getFiatStorage();
        return $.decimals;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // The following functions are overrides required by Solidity.

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._update(from, to, value);
    }

    function _spendAllowance(
        address owner_,
        address spender,
        uint256 value
    ) internal override {
        // MINTER_ROLE bypasses allowance checks to process fiat
        // withdrawal requests. This ERC-20 token tracks the user's fiat balance.
        if (hasRole(MINTER_ROLE, spender)) return;
        super._spendAllowance(owner_, spender, value);
    }
}
