// SPDX-License-Identifier: MIT

import "../utils/TransferPolicy.sol";

interface ITransferSecurityRegistry {
    event AddedToAllowlist(AllowlistTypes kind, uint64 id, address account);
    event CreatedAllowlist(AllowlistTypes kind, uint64 id, string name);
    event ReassignedAllowlistOwnership(AllowlistTypes kind, uint64 id, address newOwner);
    event RemovedFromAllowlist(AllowlistTypes kind, uint64 id, address account);
    event SetAllowlist(AllowlistTypes kind, address collection, uint64 id);
    event SetTransferSecurityLevel(address collection, TransferSecurityLevels level);

    function createOperatorWhitelist(string calldata name) external returns (uint64);
    function createPermittedContractReceiverAllowlist(string calldata name) external returns (uint64);
    function reassignOwnershipOfOperatorWhitelist(uint64 id, address newOwner) external;
    function reassignOwnershipOfPermittedContractReceiverAllowlist(uint64 id, address newOwner) external;
    function renounceOwnershipOfOperatorWhitelist(uint64 id) external;
    function renounceOwnershipOfPermittedContractReceiverAllowlist(uint64 id) external;
    function setTransferSecurityLevelOfCollection(address collection, TransferSecurityLevels level) external;
    function setOperatorWhitelistOfCollection(address collection, uint64 id) external;
    function setPermittedContractReceiverAllowlistOfCollection(address collection, uint64 id) external;
    function addOperatorToWhitelist(uint64 id, address operator) external;
    function addPermittedContractReceiverToAllowlist(uint64 id, address receiver) external;
    function removeOperatorFromWhitelist(uint64 id, address operator) external;
    function removePermittedContractReceiverFromAllowlist(uint64 id, address receiver) external;
    function getCollectionSecurityPolicy(address collection) external view returns (CollectionSecurityPolicy memory);
    function getWhitelistedOperators(uint64 id) external view returns (address[] memory);
    function getPermittedContractReceivers(uint64 id) external view returns (address[] memory);
    function isOperatorWhitelisted(uint64 id, address operator) external view returns (bool);
    function isContractReceiverPermitted(uint64 id, address receiver) external view returns (bool);
}