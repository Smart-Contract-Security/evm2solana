// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// TransferPolicy structs defined inline since the import is not available
library TransferPolicy {
    struct CollectionSecurityPolicy {
        uint8 transferSecurityLevel;
        uint120 operatorWhitelistId;
        uint120 permittedContractReceiversId;
    }
}

interface ITransferSecurityRegistry {
    event AddedToAllowlist(uint8 indexed kind, uint256 indexed id, address indexed account);
    event CreatedAllowlist(uint8 indexed kind, uint256 indexed id, string indexed name);
    event ReassignedAllowlistOwnership(uint8 indexed kind, uint256 indexed id, address indexed newOwner);
    event RemovedFromAllowlist(uint8 indexed kind, uint256 indexed id, address indexed account);
    event SetAllowlist(uint8 indexed kind, address indexed collection, uint120 indexed id);
    event SetTransferSecurityLevel(address indexed collection, uint8 level);

    function createOperatorWhitelist(string calldata name) external returns (uint120);
    function createPermittedContractReceiverAllowlist(string calldata name) external returns (uint120);
    function reassignOwnershipOfOperatorWhitelist(uint120 id, address newOwner) external;
    function reassignOwnershipOfPermittedContractReceiverAllowlist(uint120 id, address newOwner) external;
    function renounceOwnershipOfOperatorWhitelist(uint120 id) external;
    function renounceOwnershipOfPermittedContractReceiverAllowlist(uint120 id) external;
    function setTransferSecurityLevelOfCollection(address collection, uint8 level) external;
    function setOperatorWhitelistOfCollection(address collection, uint120 id) external;
    function setPermittedContractReceiverAllowlistOfCollection(address collection, uint120 id) external;
    function addOperatorToWhitelist(uint120 id, address operator) external;
    function addPermittedContractReceiverToAllowlist(uint120 id, address receiver) external;
    function removeOperatorFromWhitelist(uint120 id, address operator) external;
    function removePermittedContractReceiverFromAllowlist(uint120 id, address receiver) external;
    function getCollectionSecurityPolicy(address collection) external view returns (TransferPolicy.CollectionSecurityPolicy memory);
    function getWhitelistedOperators(uint120 id) external view returns (address[] memory);
    function getPermittedContractReceivers(uint120 id) external view returns (address[] memory);
    function isOperatorWhitelisted(uint120 id, address operator) external view returns (bool);
    function isContractReceiverPermitted(uint120 id, address receiver) external view returns (bool);
}