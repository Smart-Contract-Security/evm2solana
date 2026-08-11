// SPDX-License-Identifier: MIT OR Apache-2.0

interface IInterchainSecurityModule {
    enum Types {
        UNUSED,
        ROUTING,
        AGGREGATION,
        LEGACY_MULTISIG,
        MERKLE_ROOT_MULTISIG,
        MESSAGE_ID_MULTISIG,
        NULL,
        CCIP_READ,
        ARB_L2_TO_L1,
        WEIGHTED_MERKLE_ROOT_MULTISIG,
        WEIGHTED_MESSAGE_ID_MULTISIG,
        OP_L2_TO_L1
    }

    function moduleType() external view returns (uint8);

    function verify(
        bytes calldata _metadata,
        bytes calldata _message
    ) external returns (bool);
}

interface ISpecifiesInterchainSecurityModule {
    function interchainSecurityModule()
        external
        view
        returns (address);
}