import "solana";

interface ICreatorTokenTransferValidator {
    function validateTransfer(address caller, address from, address to) external view returns (bool);
}

struct CollectionSecurityPolicy {
    bool transferSecurityEnabled;
    bool operatorWhitelistEnabled;
    bool receiverWhitelistEnabled;
}

interface ICreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);

    function getTransferValidator() external view returns (address);
    function getSecurityPolicy() external view returns (CollectionSecurityPolicy memory);
    function getWhitelistedOperators() external view returns (address[] memory);
    function getPermittedContractReceivers() external view returns (address[] memory);
    function isOperatorWhitelisted(address operator) external view returns (bool);
    function isContractReceiverPermitted(address receiver) external view returns (bool);
    function isTransferAllowed(address caller, address from, address to) external view returns (bool);
}