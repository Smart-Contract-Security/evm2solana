// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable-4.9.5/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-4.9.5/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable-4.9.5/proxy/utils/UUPSUpgradeable.sol";

import {IKNTPTT} from "@src/interfaces/IKNTPTT.sol";

/// @title Keyring Non-Transferable Pre Token Token.
/// @author Keyring Network -- mgnfy-view.
/// @notice Pre token contract to accumulate rewards for users.
contract KNTPTT is ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable, IKNTPTT {
    /// @dev The token name.
    string private constant NAME = "Keyring Non-Transferable Pre Token Token";
    /// @dev The token symbol.
    string private constant SYMBOL = "KNTPTT";
    /// @dev Minter can mint tokens.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Burner can burn tokens.
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Initializes the contract.
    /// @param _admin The initial admin address.
    /// @param _minter The initial minter.
    /// @param _burner The initial burner.
    function initialize(address _admin, address _minter, address _burner) external initializer {
        __ERC20_init(NAME, SYMBOL);
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _minter);
        _grantRole(BURNER_ROLE, _burner);
    }

    /// @notice Allows the minter to mint tokens to an address.
    /// @param _to The token recipient.
    /// @param _amount The amount of tokens to mint.
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    /// @notice Allows the burner to burn tokens from an address.
    /// @param _from The address to burn tokens from.
    /// @param _amount The amount of tokens to burn.
    function burn(address _from, uint256 _amount) external onlyRole(BURNER_ROLE) {
        _burn(_from, _amount);
    }

    /// @notice Disallows transfers.
    function _transfer(address, address, uint256) internal pure override {
        revert KNTPTT__TransfersDisallowed();
    }

    /// @notice Allows only the user with the admin role to upgrade the contract.
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Gets the minter role identifier.
    /// @return The minter role identifier.
    function getMinterRole() external pure returns (bytes32) {
        return MINTER_ROLE;
    }

    /// @notice Gets the burner role identifier.
    /// @return The burner role identifier.
    function getBurnerRole() external pure returns (bytes32) {
        return BURNER_ROLE;
    }
}
