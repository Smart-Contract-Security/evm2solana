// SPDX-License-Identifier: MIT

import {AccountMeta, AccountInfo} from 'solana';

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

struct CollectionSecurityPolicy {
    uint8 transferSecurityLevel;
    uint64 operatorWhitelistId;
    uint64 permittedContractReceiversId;
}

interface ICreatorTokenTransferValidator {
    function setTransferSecurityLevelOfCollection(address collection, uint8 level) external;
    function setOperatorWhitelistOfCollection(address collection, uint64 operatorWhitelistId) external;
    function setPermittedContractReceiverAllowlistOfCollection(address collection, uint64 permittedContractReceiversAllowlistId) external;
    function getCollectionSecurityPolicy(address collection) external view returns (CollectionSecurityPolicy memory);
    function getWhitelistedOperators(uint64 operatorWhitelistId) external view returns (address[] memory);
    function getPermittedContractReceivers(uint64 permittedContractReceiversId) external view returns (address[] memory);
    function isOperatorWhitelisted(uint64 operatorWhitelistId, address operator) external view returns (bool);
    function isContractReceiverPermitted(uint64 permittedContractReceiversId, address receiver) external view returns (bool);
    function applyCollectionTransferPolicy(address caller, address from, address to) external;
}

abstract contract CreatorTokenBase {
    
    address public constant DEFAULT_TRANSFER_VALIDATOR = address(0);
    uint8 public constant DEFAULT_TRANSFER_SECURITY_LEVEL = 1;
    uint64 public constant DEFAULT_OPERATOR_WHITELIST_ID = uint64(1);

    address private transferValidator;

    function setToDefaultSecurityPolicy() public virtual {
        _requireCallerIsContractOwner();
        setTransferValidator(DEFAULT_TRANSFER_VALIDATOR);
        ICreatorTokenTransferValidator(DEFAULT_TRANSFER_VALIDATOR).setTransferSecurityLevelOfCollection(address(this), DEFAULT_TRANSFER_SECURITY_LEVEL);
        ICreatorTokenTransferValidator(DEFAULT_TRANSFER_VALIDATOR).setOperatorWhitelistOfCollection(address(this), DEFAULT_OPERATOR_WHITELIST_ID);
    }

    function setToCustomValidatorAndSecurityPolicy(
        address validator, 
        uint8 level, 
        uint64 operatorWhitelistId, 
        uint64 permittedContractReceiversAllowlistId) public {
        _requireCallerIsContractOwner();

        setTransferValidator(validator);

        ICreatorTokenTransferValidator(validator).
            setTransferSecurityLevelOfCollection(address(this), level);

        ICreatorTokenTransferValidator(validator).
            setOperatorWhitelistOfCollection(address(this), operatorWhitelistId);

        ICreatorTokenTransferValidator(validator).
            setPermittedContractReceiverAllowlistOfCollection(address(this), permittedContractReceiversAllowlistId);
    }

    function setToCustomSecurityPolicy(
        uint8 level, 
        uint64 operatorWhitelistId, 
        uint64 permittedContractReceiversAllowlistId) public {
        _requireCallerIsContractOwner();

        address validator = getTransferValidator();
        if (validator == address(0)) {
            revert("CreatorTokenBase__SetTransferValidatorFirst");
        }

        ICreatorTokenTransferValidator(validator).setTransferSecurityLevelOfCollection(address(this), level);
        ICreatorTokenTransferValidator(validator).setOperatorWhitelistOfCollection(address(this), operatorWhitelistId);
        ICreatorTokenTransferValidator(validator).setPermittedContractReceiverAllowlistOfCollection(address(this), permittedContractReceiversAllowlistId);
    }

    function setTransferValidator(address transferValidator_) public {
        _requireCallerIsContractOwner();

        bool isValidTransferValidator = false;

        if(transferValidator_ != address(0)) {
            (bool success, bytes memory returnData) = address(transferValidator_).call{accounts: []}(
                abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ICreatorTokenTransferValidator).interfaceId)
            );
            if (success && returnData.length == 32) {
                isValidTransferValidator = abi.decode(returnData, (bool));
            }
        }

        if(transferValidator_ != address(0) && !isValidTransferValidator) {
            revert("CreatorTokenBase__InvalidTransferValidatorContract");
        }

        emit TransferValidatorUpdated(transferValidator, transferValidator_);

        transferValidator = transferValidator_;
    }

    function getTransferValidator() public view returns (address) {
        return transferValidator;
    }

    function getSecurityPolicy() public view returns (CollectionSecurityPolicy memory) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this));
        }

        return CollectionSecurityPolicy({
            transferSecurityLevel: 0,
            operatorWhitelistId: 0,
            permittedContractReceiversId: 0
        });
    }

    function getWhitelistedOperators() public view returns (address[] memory) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).getWhitelistedOperators(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).operatorWhitelistId);
        }

        return new address[](0);
    }

    function getPermittedContractReceivers() public view returns (address[] memory) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).getPermittedContractReceivers(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).permittedContractReceiversId);
        }

        return new address[](0);
    }

    function isOperatorWhitelisted(address operator) public view returns (bool) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).isOperatorWhitelisted(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).operatorWhitelistId, operator);
        }

        return false;
    }

    function isContractReceiverPermitted(address receiver) public view returns (bool) {
        if (transferValidator != address(0)) {
            return ICreatorTokenTransferValidator(transferValidator).isContractReceiverPermitted(
                ICreatorTokenTransferValidator(transferValidator).getCollectionSecurityPolicy(address(this)).permittedContractReceiversId, receiver);
        }

        return false;
    }

    function isTransferAllowed(address caller, address from, address to) public view returns (bool) {
        if (transferValidator != address(0)) {
            (bool success, ) = address(transferValidator).call{accounts: []}(
                abi.encodeWithSelector(ICreatorTokenTransferValidator.applyCollectionTransferPolicy.selector, caller, from, to)
            );
            return success;
        }
        return true;
    }

    function _preValidateTransfer(
        address caller, 
        address from, 
        address to, 
        uint64 /*tokenId*/, 
        uint64 /*value*/) internal virtual {
        if (transferValidator != address(0)) {
            ICreatorTokenTransferValidator(transferValidator).applyCollectionTransferPolicy(caller, from, to);
        }
    }

    function _requireCallerIsContractOwner() internal virtual;

    event TransferValidatorUpdated(address indexed oldValidator, address indexed newValidator);
}