// SPDX-License-Identifier: MIT

enum AllowlistTypes {
    Operators,
    PermittedContractReceivers
}

enum ReceiverConstraints {
    None,
    NoCode,
    EOA
}

enum CallerConstraints {
    None,
    OperatorWhitelistEnableOTC,
    OperatorWhitelistDisableOTC
}

enum StakerConstraints {
    None,
    CallerIsTxOrigin,
    EOA
}

enum TransferSecurityLevels {
    Zero,
    One,
    Two,
    Three,
    Four,
    Five,
    Six
}

struct TransferSecurityPolicy {
    CallerConstraints callerConstraints;
    ReceiverConstraints receiverConstraints;
}

struct CollectionSecurityPolicy {
    TransferSecurityLevels transferSecurityLevel;
    uint64 operatorWhitelistId;
    uint64 permittedContractReceiversId;
}