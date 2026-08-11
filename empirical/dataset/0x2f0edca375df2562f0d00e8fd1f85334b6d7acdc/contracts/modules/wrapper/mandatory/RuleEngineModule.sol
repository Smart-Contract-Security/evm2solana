//SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.17;

import "../../../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../security/AuthorizationModule.sol";
import "../../../interfaces/IRuleEngine.sol";

abstract contract RuleEngineModule is Initializable, AuthorizationModule {
    IRuleEngine public ruleEngine;

    event RuleEngine(address indexed newRuleEngine);

    error RuleEngineTransferRestricted(string message);

    function __RuleEngineModule_init(
        address ruleEngine_
    ) internal onlyInitializing {
        if (ruleEngine_ != address(0)) {
            ruleEngine = IRuleEngine(ruleEngine_);
        }
    }

    function _setRuleEngine(address newRuleEngine) internal {
        ruleEngine = IRuleEngine(newRuleEngine);
        emit RuleEngine(newRuleEngine);
    }

    function _validateTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view virtual returns (bool) {
        if (address(ruleEngine) == address(0)) {
            return true;
        }
        if (!ruleEngine.validateTransfer(from, to, amount)) {
            uint8 restrictionCode = ruleEngine.detectTransferRestriction(
                from,
                to,
                amount
            );
            revert RuleEngineTransferRestricted(
                ruleEngine.messageForTransferRestriction(restrictionCode)
            );
        }
        return true;
    }

    uint256[49] private __gap;
}
