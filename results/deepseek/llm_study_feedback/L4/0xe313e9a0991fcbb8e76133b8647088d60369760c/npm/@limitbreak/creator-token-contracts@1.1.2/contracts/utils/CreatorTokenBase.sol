// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title OwnablePermissions
 * @dev Placeholder for the missing OwnablePermissions contract.
 *      In a full port, this would be replaced with the actual implementation.
 */
abstract contract OwnablePermissions {
    function _requireCallerIsContractOwner() internal view virtual;
}

/**
 * @title TransferValidation
 * @dev Placeholder for the missing TransferValidation contract.
 *      In a full port, this would be replaced with the actual implementation.
 */
abstract contract TransferValidation {
    function _preValidateTransfer(
        address caller,
        address from,
        address to,
        uint256 tokenId,
        uint256 value
    ) internal virtual;
}

/**
 * @title ICreatorToken
 * @dev Placeholder for the missing ICreatorToken interface.
 *      In a full port, this would be replaced with the actual interface.
 */
interface ICreatorToken {
    function getSecurityPolicy() external view returns (CollectionSecurityPolicy memory);
    function getWhitelistedOperators() external view returns (address[] memory);
    function getPermittedContractReceivers() external view returns (address[] memory);
    function isOperatorWhitelisted(address operator) external view returns (bool);
    function isContractReceiverPermitted(address receiver) external view returns (bool);
    function isTransferAllowed(address caller, address from, address to) external view returns (bool);
}

/**
 * @title ICreatorTokenTransferValidator
 * @dev Placeholder for the missing ICreatorTokenTransferValidator interface.
 *      In a full port, this would be replaced with the actual interface.
 */
interface ICreatorTokenTransferValidator {
    function setTransferSecurityLevelOfCollection(address collection, TransferSecurityLevels level) external;
    function setOperatorWhitelistOfCollection(address collection, uint120 operatorWhitelistId) external;
    function setPermittedContractReceiverAllowlistOfCollection(address collection, uint120 permittedContractReceiversAllowlistId) external;
    function getCollectionSecurityPolicy(address collection) external view returns (CollectionSecurityPolicy memory);
    function getWhitelistedOperators(uint120 operatorWhitelistId) external view returns (address[] memory);
    function getPermittedContractReceivers(uint120 permittedContractReceiversId) external view returns (address[] memory);
    function isOperatorWhitelisted(uint120 operatorWhitelistId, address operator) external view returns (bool);
    function isContractReceiverPermitted(uint120 permittedContractReceiversId, address receiver) external view returns (bool);
    function applyCollectionTransferPolicy(address caller, address from, address to) external;
}

/**
 * @title TransferSecurityLevels
 * @dev Enum representing transfer security levels.
 */
enum TransferSecurityLevels {
    Zero,
    One,
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine
}

/**
 * @title CollectionSecurityPolicy
 * @dev Struct representing the security policy for a collection.
 */
struct CollectionSecurityPolicy {
    TransferSecurityLevels transferSecurityLevel;
    uint120 operatorWhitelistId;
    uint120 permittedContractReceiversId;
}

/**
 * @title CreatorTokenBase
 * @author Limit Break, Inc.
 * @notice CreatorTokenBase is an abstract contract that provides basic functionality for managing token 
 * transfer policies through an implementation of ICreatorTokenTransferValidator. This contract is intended to be used
 * as a base for creator-specific token contracts, enabling customizable transfer restrictions and security policies.
 *
 * <h4>Features:</h4>
 * <ul>Ownable: This contract can have an owner who can set and update the transfer validator.</ul>
 * <ul>TransferValidation: Implements the basic token transfer validation interface.</ul>
 * <ul>ICreatorToken: Implements the interface for creator tokens, providing view functions for token security policies.</ul>
 *
 * <h4>Benefits:</h4>
 * <ul>Provides a flexible and modular way to implement custom token transfer restrictions and security policies.</ul>
 * <ul>Allows creators to enforce policies such as whitelisted operators and permitted contract receivers.</ul>
 * <ul>Can be easily integrated into other token contracts as a base contract.</ul>
 *
 * <h4>Intended Usage:</h4>
 * <ul>Use as a base contract for creator token implementations that require advanced transfer restrictions and 
 *   security policies.</ul>
 * <ul>Set and update the ICreatorTokenTransferValidator implementation contract to enforce desired policies for the 
 *   creator token.</ul>
 */
abstract contract CreatorTokenBase is OwnablePermissions, TransferValidation, ICreatorToken {
    
    error CreatorTokenBase__InvalidTransferValidatorContract();
    error CreatorTokenBase__SetTransferValidatorFirst();

    // Solana does not support Ethereum address literals. Use a bytes32 constant instead.
    bytes32 public constant DEFAULT_TRANSFER_VALIDATOR = hex"0000721C310194CcfC01E523fc93C9cCcFa2A0Ac";
    TransferSecurityLevels public constant DEFAULT_TRANSFER_SECURITY_LEVEL = TransferSecurityLevels.One;
    uint120 public constant DEFAULT_OPERATOR_WHITELIST_ID = uint120(1);

    address private transferValidator;

    /**
     * @notice Allows the contract owner to set the transfer validator to the official validator contract
     *         and set the security policy to the recommended default settings.
     * @dev    May be overridden to change the default behavior of an individual collection.
     */
    function setToDefaultSecurityPolicy() public virtual {
        _requireCallerIsContractOwner();
        setTransferValidator(DEFAULT_TRANSFER_VALIDATOR);
        ICreatorTokenTransferValidator(DEFAULT_TRANSFER_VALIDATOR).setTransferSecurityLevelOfCollection(address(this), DEFAULT_TRANSFER_SECURITY_LEVEL);
        ICreatorTokenTransferValidator(DEFAULT_TRANSFER_VALIDATOR).setOperatorWhitelistOfCollection(address(this), DEFAULT_OPERATOR_WHITELIST_ID);
    }

    /**
     * @notice Allows the contract owner to set the transfer validator to a custom validator contract
     *         and set the security policy to their own custom settings.
     */
    function setToCustomValidatorAndSecurityPolicy(
        address validator, 
        TransferSecurityLevels level, 
        uint120 operatorWhitelistId, 
        uint120 permittedContractReceiversAllowlistId) public {
        _requireCallerIsContractOwner();

        setTransferValidator(validator);

        ICreatorTokenTransferValidator(validator).
            setTransferSecurityLevelOfCollection(address(this), level);

        ICreatorTokenTransferValidator(validator).
            setOperatorWhitelistOfCollection(address(this), operatorWhitelistId);

        ICreatorTokenTransferValidator(validator).
            setPermittedContractReceiverAllowlistOfCollection(address(this), permittedContractReceiversAllowlistId);
    }

    /**
     * @notice Allows the contract owner to set the security policy to their own custom settings.
     * @dev    Reverts if the transfer validator has not been set.
     */
    function setToCustomSecurityPolicy(
        TransferSecurityLevels level, 
        uint120 operatorWhitelistId, 
        uint120 permittedContractReceiversAllowlistId) public {
        _requireCallerIsContractOwner();

        address validator = getTransferValidator();
        if (validator == address(0)) {
            revert CreatorTokenBase__SetTransferValidatorFirst();
        }

        ICreatorTokenTransferValidator(validator).setTransferSecurityLevelOfCollection(address(this), level);
        ICreatorTokenTransferValidator(validator).setOperatorWhitelistOfCollection(address(this), operatorWhitelistId);
        ICreatorTokenTransferValidator(validator).setPermittedContractReceiverAllowlistOfCollection(address(this), permittedContractReceiversAllowlistId);
    }

    /**
     * @notice Sets the transfer validator for the token contract.
     *
     * @dev    Throws when provided validator contract is not the zero address and doesn't support 
     *         the ICreatorTokenTransferValidator interface. 
     * @dev    Throws when the caller is not the contract owner.
     *
     * @dev    <h4>Postconditions:</h4>
     *         1. The transferValidator address is updated.
     *         2. The `TransferValidatorUpdated` event is emitted.
     *
     * @param transferValidator_ The address of the transfer validator contract.
     */
    function setTransferValidator(address transferValidator_) public {
        _requireCallerIsContractOwner();

        bool isValidTransferValidator = false;

        if(transferValidator_.code.length > 0) {
            (bool success, bytes memory returnData) = transferValidator_.call(abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ICreatorTokenTransferValidator).interfaceId));
            if (success && returnData.length >= 32) {
                isValidTransferValidator = abi.decode(returnData, (bool));
            }
        }

        if(transferValidator_ != address(0) && !isValidTransferValidator) {
            revert CreatorTokenBase__InvalidTransferValidatorContract();
        }

        emit TransferValidatorUpdated(transferValidator, transferValidator_);

        transferValidator = transferValidator_;
    }

    /**
     * @notice Returns the transfer validator contract address for this token contract.
     */
    function getTransferValidator() public view override returns (address) {
        return transferValidator;
    }

    /**
     * @notice Returns the security policy for this token contract, which includes:
     *         Transfer security level, operator whitelist id, permitted contract receiver allowlist id.
     */
    function getSecurityPolicy() public view override returns (CollectionSecurityPolicy memory) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this));
        }

        return CollectionSecurityPolicy({
            transferSecurityLevel: TransferSecurityLevels.Zero,
            operatorWhitelistId: 0,
            permittedContractReceiversId: 0
        });
    }

    /**
     * @notice Returns the list of all whitelisted operators for this token contract.
     * @dev    This can be an expensive call and should only be used in view-only functions.
     */
    function getWhitelistedOperators() public view override returns (address[] memory) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).getWhitelistedOperators(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).operatorWhitelistId);
        }

        return new address[](0);
    }

    /**
     * @notice Returns the list of permitted contract receivers for this token contract.
     * @dev    This can be an expensive call and should only be used in view-only functions.
     */
    function getPermittedContractReceivers() public view override returns (address[] memory) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).getPermittedContractReceivers(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).permittedContractReceiversId);
        }

        return new address[](0);
    }

    /**
     * @notice Checks if an operator is whitelisted for this token contract.
     * @param operator The address of the operator to check.
     */
    function isOperatorWhitelisted(address operator) public view override returns (bool) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).isOperatorWhitelisted(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).operatorWhitelistId, operator);
        }

        return false;
    }

    /**
     * @notice Checks if a contract receiver is permitted for this token contract.
     * @param receiver The address of the receiver to check.
     */
    function isContractReceiverPermitted(address receiver) public view override returns (bool) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).isContractReceiverPermitted(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).permittedContractReceiversId, receiver);
        }

        return false;
    }

    /**
     * @notice Determines if a transfer is allowed based on the token contract's security policy.  Use this function
     *         to simulate whether or not a transfer made by the specified `caller` from the `from` address to the `to`
     *         address would be allowed by this token's security policy.
     *
     * @notice This function only checks the security policy restrictions and does not check whether token ownership
     *         or approvals are in place. 
     *
     * @param caller The address of the simulated caller.
     * @param from   The address of the sender.
     * @param to     The address of the receiver.
     * @return       True if the transfer is allowed, false otherwise.
     */
    function isTransferAllowed(address caller, address from, address to) public view override returns (bool) {
        if (transferValidator != address(0)) {
            (bool success, ) = transferValidator.staticcall(abi.encodeWithSelector(ICreatorTokenTransferValidator.applyCollectionTransferPolicy.selector, caller, from, to));
            if (success) {
                return true;
            } else {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Pre-validates a token transfer, reverting if the transfer is not allowed by this token's security policy.
     *      Inheriting contracts are responsible for overriding the _beforeTokenTransfer function, or its equivalent
     *      and calling _validateBeforeTransfer so that checks can be properly applied during token transfers.
     *
     * @dev Throws when the transfer doesn't comply with the collection's transfer policy, if the transferValidator is
     *      set to a non-zero address.
     *
     * @param caller  The address of the caller.
     * @param from    The address of the sender.
     * @param to      The address of the receiver.
     */
    function _preValidateTransfer(
        address caller, 
        address from, 
        address to, 
        uint256 /*tokenId*/, 
        uint256 /*value*/) internal virtual override {
        if (transferValidator != address(0)) {
            ICreatorTokenTransferValidator(transferValidator).applyCollectionTransferPolicy(caller, from, to);
        }
    }
}