//SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.17;

// required OZ imports here
import "../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "./wrapper/mandatory/BaseModule.sol";
import "./wrapper/mandatory/BurnModule.sol";
import "./wrapper/mandatory/MintModule.sol";
import "./wrapper/mandatory/EnforcementModule.sol";
import "./wrapper/mandatory/ERC20BaseModule.sol";
import "./wrapper/mandatory/PauseModule.sol";
import "./wrapper/optional/ValidationModule.sol";
import "./security/AuthorizationModule.sol";
import "../interfaces/IEIP1404/IEIP1404Wrapper.sol";
import "./internal/ValidationModuleInternal.sol";
import "./wrapper/mandatory/RuleEngineModule.sol";

abstract contract CMTAT_BASE is
    Initializable,
    ContextUpgradeable,
    BaseModule,
    PauseModule,
    MintModule,
    BurnModule,
    EnforcementModule,
    ValidationModule,
    ERC20BaseModule,
    UUPSUpgradeable
{
    /**
    @notice 
    initialize the proxy contract
    The calls to this function will revert if the contract was deployed without a proxy
    */
    function initialize(
        address admin,
        string memory nameIrrevocable,
        string memory symbolIrrevocable,
        string memory tokenId_,
        string memory terms_,
        IEIP1404Wrapper ruleEngine_,
        string memory information_,
        uint256 flag_,
        string memory currencyNAV_
    ) public initializer {
        __CMTAT_init(
            admin,
            nameIrrevocable,
            symbolIrrevocable,
            tokenId_,
            terms_,
            address(ruleEngine_),
            information_,
            flag_,
            currencyNAV_
        );
    }

    /**
    @dev calls the different initialize functions from the different modules
    */
    function __CMTAT_init(
        address admin_,
        string memory name_,
        string memory symbol_,
        string memory tokenId_,
        string memory terms_,
        address ruleEngine_,
        string memory information_,
        uint256 flag_,
        string memory currencyNAV_
    ) internal onlyInitializing {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
        __UUPSUpgradeable_init();

        // Initialize modules
        __AccessControl_init_unchained();
        __ERC165_init_unchained();
        __Pausable_init_unchained();
        __AuthorizationModule_init_unchained(admin_);
        __ValidationModuleInternal_init(ruleEngine_);
        __ValidationModule_init(ruleEngine_, admin_);
        __Base_init_unchained(tokenId_, terms_, information_, flag_);
        __EnforcementModule_init_unchained();
        __PauseModule_init_unchained();
        __BurnModule_init(name_, symbol_, admin_, ruleEngine_, currencyNAV_);
        __MintModule_init(name_, symbol_, admin_, ruleEngine_, currencyNAV_);

        // Own initialization
        __CMTAT_init_unchained();
    }

    function __CMTAT_init_unchained() internal onlyInitializing {
        // no variable to initialize
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     * 
     * Normally, this function will use an access control modifier such as {Ownable-onlyOwner}.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // Only admin can upgrade
    }

    /**
    @notice Returns the number of decimals used to get its user representation.
    */
    function decimals()
        public
        view
        virtual
        override(ERC20Upgradeable, ERC20BaseModule)
        returns (uint8)
    {
        return 18;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        virtual
        override(ERC20Upgradeable, ERC20BaseModule)
        returns (bool)
    {
        return ERC20BaseModule.transferFrom(sender, recipient, amount);
    }

    /*
    @dev 
    SnapshotModule:
    - override SnapshotModuleInternal if you add the SnapshotModule
    e.g. override(SnapshotModuleInternal, ERC20Upgradeable)
    - remove the keyword view
    */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view override {
        require(
            ValidationModule.validateTransfer(from, to, amount),
            "CMTAT: transfer rejected by validation module"
        );
        // We call the SnapshotModule only if the transfer is valid
        /*
        SnapshotModule:
        Add this call in case you add the SnapshotModule
        SnapshotModuleInternal._beforeTokenTransfer(from, to, amount);
        */
    }

    function _validateTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        view
        virtual
        override(ValidationModuleInternal, RuleEngineModule)
        returns (bool)
    {
        return ValidationModuleInternal._validateTransfer(from, to, amount);
    }
}
