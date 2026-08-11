// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IBridgeMessenger} from "../interfaces/IBridgeMessenger.sol";
import {IPTBridge} from "../interfaces/IPTBridge.sol";
import {IAxelarGateway} from "@axelar-network/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/contracts/interfaces/IAxelarGasService.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

/**
 * @title IAxelarGasEstimator
 * @notice Interface for Axelar gas estimation (if available on-chain)
 */
interface IAxelarGasEstimator {
    function estimateGasFee(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload
    ) external view returns (uint256);
}

/**
 * @title AxelarMessenger
 * @author Spectra Finance
 * @notice Axelar implementation of the bridge messenger interface
 * @dev Handles cross-chain messaging via Axelar's General Message Passing (GMP).
 *      Uses Transparent proxy pattern and AccessManager for permissions.
 *
 * @custom:security-contact security@spectra.finance
 */
contract AxelarMessenger is
    IBridgeMessenger,
    Initializable,
    AccessManagedUpgradeable
{
    // =============================================================
    //                           STORAGE
    // =============================================================

    IAxelarGateway public gateway;
    IAxelarGasService public gasService;
    address public bridge;
    address public gasEstimator;

    uint256 private _messageNonce;
    mapping(string => uint256) public baseGasCost;
    uint256 public gasPerByte;

    uint256 public constant DEFAULT_GAS_COST = 0.005 ether;
    uint256 public constant DEFAULT_GAS_PER_BYTE = 100 gwei;

    // =============================================================
    //                           ERRORS
    // =============================================================

    error OnlyBridge();
    error BridgeNotSet();

    // =============================================================
    //                           EVENTS
    // =============================================================

    event GasEstimatorUpdated(address indexed oldEstimator, address indexed newEstimator);
    event BaseGasCostUpdated(string indexed chain, uint256 cost);
    event GasPerByteUpdated(uint256 oldValue, uint256 newValue);
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    // =============================================================
    //                       INITIALIZATION
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the AxelarMessenger contract
     * @param gateway_ The Axelar gateway contract address
     * @param gasService_ The Axelar gas service contract address
     * @param authority_ The AccessManager contract address
     */
    function initialize(
        address gateway_,
        address gasService_,
        address authority_
    ) external initializer {
        __AccessManaged_init(authority_);

        gateway = IAxelarGateway(gateway_);
        gasService = IAxelarGasService(gasService_);
        gasPerByte = DEFAULT_GAS_PER_BYTE;
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    function setBridge(address bridge_) external restricted {
        emit BridgeUpdated(bridge, bridge_);
        bridge = bridge_;
    }

    function setGasEstimator(address gasEstimator_) external restricted {
        emit GasEstimatorUpdated(gasEstimator, gasEstimator_);
        gasEstimator = gasEstimator_;
    }

    function setBaseGasCost(string calldata chainName, uint256 cost) external restricted {
        baseGasCost[chainName] = cost;
        emit BaseGasCostUpdated(chainName, cost);
    }

    function setGasPerByte(uint256 cost) external restricted {
        emit GasPerByteUpdated(gasPerByte, cost);
        gasPerByte = cost;
    }

    // =============================================================
    //                    MESSAGING FUNCTIONS
    // =============================================================

    /// @inheritdoc IBridgeMessenger
    function sendMessage(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable onlyBridge returns (bytes32 messageId) {
        messageId = bytes32(_messageNonce++);

        if (msg.value > 0) {
            gasService.payNativeGasForContractCall{value: msg.value}(
                address(this),
                destinationChain,
                destinationAddress,
                payload,
                refundAddress
            );
        }

        gateway.callContract(destinationChain, destinationAddress, payload);
    }

    /// @inheritdoc IBridgeMessenger
    function estimateGasCost(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload
    ) external view returns (uint256) {
        if (gasEstimator != address(0)) {
            try IAxelarGasEstimator(gasEstimator).estimateGasFee(
                destinationChain, destinationAddress, payload
            ) returns (uint256 estimate) {
                if (estimate > 0) return estimate;
            } catch {}
        }

        uint256 baseCost = baseGasCost[destinationChain];
        if (baseCost == 0) baseCost = DEFAULT_GAS_COST;

        return baseCost + payload.length * gasPerByte;
    }

    /// @inheritdoc IBridgeMessenger
    function protocolName() external pure returns (string memory) {
        return "Axelar";
    }

    // =============================================================
    //                    RECEIVE FUNCTIONS
    // =============================================================

    /**
     * @notice Called by Axelar gateway when a cross-chain message is received
     * @dev Validates the message and forwards it to the bridge contract via typed call
     */
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        bytes32 payloadHash;
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, payload.offset, payload.length)
            payloadHash := keccak256(ptr, payload.length)
        }
        if (!gateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash)) {
            revert("NOT_APPROVED_BY_GATEWAY");
        }

        if (bridge == address(0)) revert BridgeNotSet();


        IPTBridge(bridge).receiveMessage(sourceChain, sourceAddress, payload);
    }

}
