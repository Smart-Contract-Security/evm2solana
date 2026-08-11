//SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.17;

import "../../../openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "../../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../wrapper/mandatory/RuleEngineModule.sol";

/**
 * @dev Validation module.
 *
 * Useful for to restrict and validate transfers
 */
abstract contract ValidationModuleInternal is
    Initializable,
    ContextUpgradeable,
    RuleEngineModule
{
    /**
     * @dev Emitted when a rule engine is set.
     */
    event RuleEngine(IEIP1404Wrapper indexed newRuleEngine);

    /**
     * @dev Initializes the contract with rule engine.
     */
    function __ValidationModuleInternal_init(
        address ruleEngine_
    ) internal onlyInitializing {
        __Context_init_unchained();
        __RuleEngineModule_init(ruleEngine_);
    }

    /**
    @dev before making a call to this function, you have to check if a ruleEngine is set.
    */
    function _validateTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view virtual override returns (bool) {
        if (address(ruleEngine) == address(0)) {
            return true;
        }
        try ruleEngine.validateTransfer(from, to, amount) returns (
            bool result
        ) {
            return result;
        } catch {
            return false;
        }
    }

    /**
    @dev before making a call to this function, you have to check if a ruleEngine is set.
    */
    function _messageForTransferRestriction(
        uint8 restrictionCode
    ) internal view returns (string memory) {
        return ruleEngine.messageForTransferRestriction(restrictionCode);
    }

    /**
    @dev before making a call to this function, you have to check if a ruleEngine is set.
    */
    function _detectTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) internal view returns (uint8) {
        return ruleEngine.detectTransferRestriction(from, to, amount);
    }

    uint256[50] private __gap;
}
