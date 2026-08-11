// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

/**
 * @title IBridgeMessenger
 * @author Spectra Finance
 * @notice Interface for cross-chain messaging adapters
 * @dev This interface allows swapping out the underlying messaging protocol (Axelar, LayerZero, etc.)
 *      without changing the bridge logic. Implementations must handle:
 *      - Sending messages to other chains
 *      - Receiving messages from other chains
 *      - Gas estimation for cross-chain operations
 *
 * Security considerations:
 * - Implementations should validate message sources
 * - Replay protection is handled by the underlying protocols:
 *     Axelar: validateContractCall() is one-time-use per commandId
 *     LayerZero V2: endpoint nonce tracking with exactly-once delivery
 * - Gas estimation should include safety margins
 *
 * Event observability:
 * - This interface intentionally does not define MessageSent/MessageReceived events.
 *   The underlying protocols already emit events for message lifecycle tracking:
 *     Axelar: ContractCallApproved, MessageExecuted (gateway)
 *     LayerZero: PacketSent, PacketDelivered (endpoint)
 *   Duplicating these at the adapter level would add gas cost with no additional value.
 *
 * @custom:security-contact security@spectra.finance
 */
interface IBridgeMessenger {
    // =============================================================
    //                    MESSAGING FUNCTIONS
    // =============================================================

    /**
     * @notice Sends a cross-chain message to another blockchain
     * @dev Implementations should handle protocol-specific encoding and gas payment.
     *      The msg.value should be used to pay for cross-chain gas costs.
     *
     * @param destinationChain The name of the destination chain (e.g., "stellar-2026-q1-2", "ethereum")
     * @param destinationAddress The address of the destination contract on the target chain
     *        For EVM chains, this is typically a hex string
     *        For Stellar, this is a base32-encoded address
     * @param payload The encoded message payload to send
     * @param refundAddress The address to receive any excess gas refunds
     * @return messageId Unique identifier for tracking this message
     *
     * Requirements:
     * - Caller must be authorized (typically the bridge contract)
     * - Sufficient msg.value for cross-chain gas (use estimateGasCost to determine)
     *
     * Effects:
     * - Sends the message through the underlying cross-chain protocol
     * - May pay gas to a gas service contract
     *
     */
    function sendMessage(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Estimates the gas cost for sending a cross-chain message
     * @dev This is an estimate and actual costs may vary based on:
     *      - Network congestion
     *      - Gas price fluctuations
     *      - Payload complexity
     *
     * It's recommended to add a 10-20% buffer to the estimate.
     *
     * @param destinationChain The name of the destination chain
     * @param destinationAddress The address of the destination contract
     * @param payload The encoded message payload
     * @return gasCost The estimated gas cost in native currency (wei for EVM chains)
     *
     * Note: Returns 0 if estimation is not available or fails
     */
    function estimateGasCost(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload
    ) external view returns (uint256 gasCost);

    /**
     * @notice Returns the name of the messaging protocol
     * @dev Used for identification and logging purposes
     * @return The protocol name (e.g., "Axelar", "LayerZero", "Wormhole")
     */
    function protocolName() external pure returns (string memory);
}
