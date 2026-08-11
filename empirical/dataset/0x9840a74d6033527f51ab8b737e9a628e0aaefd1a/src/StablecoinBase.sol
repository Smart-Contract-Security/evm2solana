// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title StablecoinBase
/// @notice Abstract base contract for upgradeable stablecoin tokens governed through OpenZeppelin AccessManager.
/// @dev This contract contains all core stablecoin functionality (mint, burn, pause, blacklist, permit, rescue).
///      Concrete implementations (PLNY, EURY, USDY) inherit from this and only set token name/symbol.
abstract contract StablecoinBase is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, PausableUpgradeable, AccessManagedUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Emitted when `account` becomes blacklisted.
    event Blacklisted(address indexed account, address indexed caller);

    /// @dev Emitted when `account` is removed from the blacklist.
    event Unblacklisted(address indexed account, address indexed caller);

    /// @dev Thrown when a blacklisted account attempts a restricted action.
    error BlacklistedAccount(address account);

    /// @dev Thrown when adding an address that is already blacklisted.
    error AlreadyBlacklisted(address account);

    /// @dev Thrown when removing an address that is not blacklisted.
    error NotBlacklisted(address account);

    /// @dev Thrown when attempting to rescue the contract's own token.
    error CannotRescueSelf();

    mapping(address => bool) private _blacklisted;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Returns the number of decimals used for token amounts.
    /// @dev Overrides the default ERC20 decimals (18) to use 6 decimals for stablecoins.
    /// @return uint8 The number of decimals (6).
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mints new tokens to a specified address.
    /// @dev Only callable by authorized minter role via AccessManager.
    /// @param to The address that will receive the minted tokens.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external restricted {
        _mint(to, amount);
    }

    /// @notice Burns tokens from the caller's balance.
    /// @dev Only callable by authorized burner role via AccessManager.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) external restricted {
        _burn(_msgSender(), amount);
    }

    /// @notice Burns tokens from another account using allowance.
    /// @dev Only callable by authorized burn-from role via AccessManager.
    ///      Requires prior approval from the account owner.
    /// @param account The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    function burnFrom(address account, uint256 amount) external restricted {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /// @notice Pauses all token transfers.
    /// @dev Only callable by authorized pauser role via AccessManager.
    function pause() external restricted {
        _pause();
    }

    /// @notice Unpauses token transfers.
    /// @dev Only callable by authorized pauser role via AccessManager.
    function unpause() external restricted {
        _unpause();
    }

    /// @notice Adds an address to the blacklist, preventing it from sending or receiving tokens.
    /// @dev Only callable by authorized blacklister role via AccessManager.
    /// @param account The address to blacklist.
    function blacklist(address account) external restricted {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        if (_blacklisted[account]) {
            revert AlreadyBlacklisted(account);
        }
        _blacklisted[account] = true;
        emit Blacklisted(account, _msgSender());
    }

    /// @notice Removes an address from the blacklist.
    /// @dev Only callable by authorized blacklister role via AccessManager.
    /// @param account The address to remove from blacklist.
    function unblacklist(address account) external restricted {
        if (!_blacklisted[account]) {
            revert NotBlacklisted(account);
        }
        _blacklisted[account] = false;
        emit Unblacklisted(account, _msgSender());
    }

    /// @notice Checks if an address is blacklisted.
    /// @param account The address to check.
    /// @return True if the address is blacklisted, false otherwise.
    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    /// @notice Recovers ERC-20 tokens accidentally sent to this contract.
    /// @dev Only callable by authorized rescuer role via AccessManager.
    ///      Cannot be used to rescue this contract's own tokens.
    /// @param token The ERC-20 token contract to recover.
    /// @param to The address to send recovered tokens to.
    /// @param amount The amount of tokens to recover.
    function rescueERC20(IERC20 token, address to, uint256 amount) external restricted {
        if (address(token) == address(this)) {
            revert CannotRescueSelf();
        }
        token.safeTransfer(to, amount);
    }

    /// @notice Returns the version of the token implementation.
    /// @dev Override in upgraded implementations to return new version string.
    /// @return The semantic version string of this implementation.
    function version() public pure virtual returns (string memory) {
        return "1.0.0";
    }

    /// @notice Upgrades the contract implementation to a new address.
    /// @dev Only callable by authorized upgrader via AccessManager. Must be called via proxy.
    /// @param newImplementation The address of the new implementation contract.
    /// @param data Data to pass to the new implementation's initialization function.
    function upgradeToAndCall(address newImplementation, bytes memory data)
        public
        payable
        override
        restricted
        onlyProxy
    {
        super.upgradeToAndCall(newImplementation, data);
    }

    /// @dev Internal hook that enforces pause state and blacklist checks before any token transfer.
    /// @param from The address tokens are transferred from (address(0) for minting).
    /// @param to The address tokens are transferred to (address(0) for burning).
    /// @param value The amount of tokens being transferred.
    function _update(address from, address to, uint256 value) internal override {
        _requireNotPaused();
        if (from != address(0) && _blacklisted[from]) {
            revert BlacklistedAccount(from);
        }
        if (to != address(0) && _blacklisted[to]) {
            revert BlacklistedAccount(to);
        }
        super._update(from, to, value);
    }

    /// @dev Internal function to authorize upgrades. Checks AccessManager permissions.
    function _authorizeUpgrade(address) internal override {
        _checkCanCall(_msgSender(), msg.data);
    }
}
