//SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.17;

import "../../../../openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../../../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../security/AuthorizationModule.sol";
import "../custom/NAVModule.sol";
import "./RuleEngineModule.sol";

// Add these error definitions at the top of the contract
error CMTAT_BurnModule_ZeroNAV();
error CMTAT_BurnModule_EmptyAccounts();
error CMTAT_BurnModule_AccountsValueslengthMismatch();
error CMTAT_BurnModule_TransferRestricted(string message);

abstract contract BurnModule is ERC20Upgradeable, RuleEngineModule, NAVModule {
    event Burn(
        address indexed owner,
        uint256 amount,
        string reason,
        uint256 NAV,
        string currencyNAV
    );

    function __BurnModule_init(
        string memory name_,
        string memory symbol_,
        address admin,
        address ruleEngine_,
        string memory currencyNAV
    ) internal onlyInitializing {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
        __RuleEngineModule_init(ruleEngine_);
        __NAVModule_init_unchained(currencyNAV);
        __AuthorizationModule_init_unchained(admin);

        // Add back the unchained init
        __BurnModule_init_unchained();
    }

    function __BurnModule_init_unchained() internal onlyInitializing {
        // no variable to initialize
    }

    function _validateBurn(address from, uint256 amount) internal view {
        _validateTransfer(from, address(0), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account` with associated NAV.
     * If there's no NAV set for the current epoch, it will set the provided NAV.
     * @param account The address from which to burn tokens
     * @param amount The amount of tokens to burn
     * @param reason The reason for burning
     * @param NAV The NAV value to use if no NAV is set for the current epoch (scaled by 1e18)
     */
    function burn(
        address account,
        uint256 amount,
        string memory reason,
        uint256 NAV
    ) public onlyRole(MINTER_ROLE) {
        if (NAV == 0) {
            revert CMTAT_BurnModule_ZeroNAV();
        }
        _validateBurn(account, amount);

        // set NAV if it hasn't been set for this epoch yet, or if it has changed for the same epoch
        if (
            _epochToNAV[currentEpoch] == 0 || _epochToNAV[currentEpoch] != NAV
        ) {
            setLatestNAV(NAV);
        }

        _burn(account, amount);
        emit Burn(account, amount, reason, NAV, currencyNAV);
    }

    uint256[50] private __gap;

    /**
     *
     * @notice batch version of {burn}.
     * @dev
     * See {ERC20-_burn} and {OpenZeppelin ERC1155_burnBatch}.
     *
     * For each burn action:
     * -Emits a {Burn} event
     * -Emits a {Transfer} event with `to` set to the zero address  (emits inside _burn).
     * The burn `reason`is the same for all `accounts` which tokens are burnt.
     * Requirements:
     * - `accounts` and `values` must have the same length
     * - the caller must have the `MINTER_ROLE`.
     */
    function burnBatch(
        address[] calldata accounts,
        uint256[] calldata values,
        string calldata reason,
        uint256 NAV
    ) public onlyRole(MINTER_ROLE) {
        if (NAV == 0) {
            revert CMTAT_BurnModule_ZeroNAV();
        }
        if (accounts.length == 0) {
            revert CMTAT_BurnModule_EmptyAccounts();
        }
        // Only set NAV if it hasn't been set for this epoch yet
        if (_epochToNAV[currentEpoch] == 0) {
            setLatestNAV(NAV);
        }
        if (accounts.length != values.length) {
            revert CMTAT_BurnModule_AccountsValueslengthMismatch();
        }
        // set NAV if it hasn't been set for this epoch yet, or if it has changed for the same epoch
        if (
            _epochToNAV[currentEpoch] == 0 || _epochToNAV[currentEpoch] != NAV
        ) {
            setLatestNAV(NAV);
        }

        // No need of unchecked block since Soliditiy 0.8.22
        for (uint256 i = 0; i < accounts.length; ++i) {
            _validateBurn(accounts[i], values[i]);
            _burn(accounts[i], values[i]);
            emit Burn(accounts[i], values[i], reason, NAV, currencyNAV);
        }
    }
}
