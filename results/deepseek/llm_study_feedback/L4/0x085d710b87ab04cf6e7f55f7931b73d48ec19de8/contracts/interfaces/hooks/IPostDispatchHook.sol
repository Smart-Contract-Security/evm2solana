// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/

library PostDispatchHookTypes {
    uint8 constant UNUSED = 0;
    uint8 constant ROUTING = 1;
    uint8 constant AGGREGATION = 2;
    uint8 constant MERKLE_TREE = 3;
    uint8 constant INTERCHAIN_GAS_PAYMASTER = 4;
    uint8 constant FALLBACK_ROUTING = 5;
    uint8 constant ID_AUTH_ISM = 6;
    uint8 constant PAUSABLE = 7;
    uint8 constant PROTOCOL_FEE = 8;
    uint8 constant LAYER_ZERO_V1 = 9;
    uint8 constant RATE_LIMITED = 10;
    uint8 constant ARB_L2_TO_L1 = 11;
    uint8 constant OP_L2_TO_L1 = 12;
    uint8 constant MAILBOX_DEFAULT_HOOK = 13;
    uint8 constant AMOUNT_ROUTING = 14;
}

interface IPostDispatchHook {
    /**
     * @notice Returns an enum that represents the type of hook
     */
    function hookType() external view returns (uint8);

    /**
     * @notice Returns whether the hook supports metadata
     * @param metadata metadata
     * @return Whether the hook supports metadata
     */
    function supportsMetadata(
        bytes calldata metadata
    ) external view returns (bool);

    /**
     * @notice Post action after a message is dispatched via the Mailbox
     * @param metadata The metadata required for the hook
     * @param message The message passed from the Mailbox.dispatch() call
     */
    function postDispatch(
        bytes calldata metadata,
        bytes calldata message
    ) external payable;

    /**
     * @notice Compute the payment required by the postDispatch call
     * @param metadata The metadata required for the hook
     * @param message The message passed from the Mailbox.dispatch() call
     * @return Quoted payment for the postDispatch call
     */
    function quoteDispatch(
        bytes calldata metadata,
        bytes calldata message
    ) external view returns (uint256);
}