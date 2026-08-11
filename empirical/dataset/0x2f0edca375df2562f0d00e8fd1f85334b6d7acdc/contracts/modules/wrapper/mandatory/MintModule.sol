//SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.17;

import "../../../../openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../../../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../security/AuthorizationModule.sol";
import "../custom/NAVModule.sol";
import "./RuleEngineModule.sol";

abstract contract MintModule is
    ERC20Upgradeable,
    AuthorizationModule,
    RuleEngineModule,
    NAVModule
{
    event Mint(
        address indexed beneficiary,
        uint256 amount,
        uint256 nav,
        string currencyNAV
    );

    // Add these error definitions at the top of the contract
    error CMTAT_MintModule_ZeroNAV();
    error CMTAT_MintModule_EmptyAccounts();
    error CMTAT_MintModule_AccountsValueslengthMismatch();
    error CMTAT_MintModule_TransferRestricted(string message);

    function __MintModule_init(
        string memory name_,
        string memory symbol_,
        address admin,
        address ruleEngine_,
        string memory currencyNAV_
    ) internal onlyInitializing {
        /* OpenZeppelin */
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
        // AccessControlUpgradeable inherits from ERC165Upgradeable
        __ERC165_init_unchained();
        // AuthorizationModule inherits from AccessControlUpgradeable
        __AccessControl_init_unchained();

        /* CMTAT modules */
        // Security
        __AuthorizationModule_init_unchained(admin);

        // NAV Module
        __NAVModule_init_unchained(currencyNAV_);
        // own function
        __MintModule_init_unchained();

        // set ruleEngine instance
        if (ruleEngine_ != address(0)) {
            ruleEngine = IRuleEngine(ruleEngine_);
        }
    }

    function __MintModule_init_unchained() internal onlyInitializing {
        // no variable to initialize
    }

    function _validateMint(address to, uint256 amount) internal view {
        _validateTransfer(address(0), to, amount);
    }

    /**
     * @dev Creates `amount` new tokens for `to` with associated NAV.
     * If there's no NAV set for the current epoch, it will set the provided NAV.
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     * @param NAV The NAV value to use if no NAV is set for the current epoch (scaled by 1e18)
     */
    function mint(
        address to,
        uint256 amount,
        uint256 NAV
    ) public onlyRole(MINTER_ROLE) {
        if (NAV == 0) {
            revert CMTAT_MintModule_ZeroNAV();
        }
        _validateMint(to, amount);
        // set NAV if it hasn't been set for this epoch yet, or if it has changed for the same epoch
        if (
            _epochToNAV[currentEpoch] == 0 || _epochToNAV[currentEpoch] != NAV
        ) {
            setLatestNAV(NAV);
        }

        _mint(to, amount);
        emit Mint(to, amount, NAV, currencyNAV);
    }

    /**
     *
     * @notice batch version of {mint}
     * @dev
     * See {OpenZeppelin ERC20-_mint} and {OpenZeppelin ERC1155_mintBatch}.
     *
     * For each mint action:
     * - Emits a {Mint} event.
     * - Emits a {Transfer} event with `from` set to the zero address (emits inside _mint).
     *
     * Requirements:
     * - `accounts` and `values` must have the same length
     * - `accounts` cannot contain a zero address (check made by _mint).
     * - the caller must have the `MINTER_ROLE`.
     */
    function mintBatch(
        address[] calldata accounts,
        uint256[] calldata values,
        uint256 NAV
    ) public onlyRole(MINTER_ROLE) {
        if (NAV == 0) {
            revert CMTAT_MintModule_ZeroNAV();
        }
        if (accounts.length == 0) {
            revert CMTAT_MintModule_EmptyAccounts();
        }
        if (accounts.length != values.length) {
            revert CMTAT_MintModule_AccountsValueslengthMismatch();
        }

        // set NAV if it hasn't been set for this epoch yet, or if it has changed for the same epoch
        if (
            _epochToNAV[currentEpoch] == 0 || _epochToNAV[currentEpoch] != NAV
        ) {
            setLatestNAV(NAV);
        }

        // No need of unchecked block since Soliditiy 0.8.22
        for (uint256 i = 0; i < accounts.length; ++i) {
            _validateMint(accounts[i], values[i]);
            _mint(accounts[i], values[i]);
            emit Mint(accounts[i], values[i], NAV, currencyNAV);
        }
    }

    uint256[50] private __gap;
}
