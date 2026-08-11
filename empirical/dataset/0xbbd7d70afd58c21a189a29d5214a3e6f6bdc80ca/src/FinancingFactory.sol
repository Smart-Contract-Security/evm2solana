// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BaseControl} from "./base/BaseControl.sol";
import {Errors} from "./errors/Errors.sol";
import {FinancingInstance} from "./FinancingInstance.sol";
import {FinancingTypes} from "./FinancingTypes.sol";

contract FinancingFactory is Initializable, BaseControl {
    using SafeERC20 for IERC20;

    /// @notice Default order creation fee, WAD-denominated. Protocol fee can be configured later by COO.
    uint256 public constant DEFAULT_CREATE_FEE_AMOUNT = 0;
    uint256 internal constant WAD = 1e18;

    error InvalidImplementation();
    error InvalidExtension();
    error StorageLayoutMismatch();
    error InstanceAlreadyExists();
    error InvalidReceiver();
    error InvalidPaymentTokenDecimals();

    uint256 public nextOrderId;
    address public financingImplementation;
    address public instanceExtension;
    address public instanceAdmin;
    address public protocolFeeRecipient;
    uint256 public createFeeAmount;

    mapping(uint256 orderId => address instanceAddress) public instanceOf;
    mapping(address instanceAddress => uint256 orderId) public orderIdOf;

    event FinancingImplementationUpdated(address indexed implementation);
    event InstanceExtensionUpdated(address indexed extension);
    event InstanceAdminUpdated(address indexed instanceAdmin);
    event CreateFeeConfigUpdated(address indexed recipient, uint256 feeAmountWad);
    event CreateFeePaid(
        address indexed creator, address indexed paymentToken, address indexed recipient, uint256 amount
    );
    event FinancingInstanceCreated(uint256 indexed orderId, address indexed instanceAddress, address indexed creator);

    function initialize(address admin, address implementation_, address extension_) external initializer {
        _BaseControl_initialize(admin);
        _setImplementation(implementation_);
        _setExtension(extension_);
        _setInstanceAdmin(admin);
        _setCreateFeeConfig(admin, DEFAULT_CREATE_FEE_AMOUNT);
        nextOrderId = 1;
    }

    function setFinancingImplementation(address implementation_) external onlyRole(UPGRADER_ROLE) {
        _setImplementation(implementation_);
    }

    function setInstanceExtension(address extension_) external onlyRole(UPGRADER_ROLE) {
        _setExtension(extension_);
    }

    function setInstanceAdmin(address instanceAdmin_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setInstanceAdmin(instanceAdmin_);
    }

    function setCreateFeeConfig(address recipient, uint256 feeAmount) external onlyRole(COO_ROLE) {
        _setCreateFeeConfig(recipient, feeAmount);
    }

    function getCreateFeeConfig() external view returns (address recipient, uint256 feeAmount) {
        return (protocolFeeRecipient, createFeeAmount);
    }

    function getCreateFeeAmountFor(address paymentToken) external view returns (uint256) {
        return _rawPaymentAmount(paymentToken, createFeeAmount);
    }

    function createFinancingInstance(FinancingTypes.OrderInitParams calldata params)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 orderId, address instanceAddress)
    {
        _collectCreateFee(params.paymentToken);

        orderId = nextOrderId++;

        bytes memory initData = abi.encodeCall(
            FinancingInstance.initialize, (instanceAdmin, address(this), instanceExtension, orderId, msg.sender, params)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(financingImplementation, initData);
        instanceAddress = address(proxy);

        if (instanceOf[orderId] != address(0) || orderIdOf[instanceAddress] != 0) {
            revert InstanceAlreadyExists();
        }

        instanceOf[orderId] = instanceAddress;
        orderIdOf[instanceAddress] = orderId;

        emit FinancingInstanceCreated(orderId, instanceAddress, msg.sender);
    }

    function _setImplementation(address implementation_) internal {
        if (implementation_ == address(0)) revert Errors.ZeroAddress();
        if (implementation_.code.length == 0) revert InvalidImplementation();
        try FinancingInstance(implementation_).STORAGE_LAYOUT_VERSION() returns (uint256 v) {
            if (instanceExtension != address(0) && v != FinancingInstance(instanceExtension).STORAGE_LAYOUT_VERSION()) {
                revert StorageLayoutMismatch();
            }
        } catch {
            revert InvalidImplementation();
        }

        financingImplementation = implementation_;
        emit FinancingImplementationUpdated(implementation_);
    }

    function _setExtension(address extension_) internal {
        if (extension_ == address(0)) revert Errors.ZeroAddress();
        if (extension_.code.length == 0) revert InvalidExtension();
        _requireMatchingLayout(extension_);

        instanceExtension = extension_;
        emit InstanceExtensionUpdated(extension_);
    }

    function _requireMatchingLayout(address target) internal view {
        try FinancingInstance(target).STORAGE_LAYOUT_VERSION() returns (uint256 v) {
            if (v != FinancingInstance(financingImplementation).STORAGE_LAYOUT_VERSION()) {
                revert StorageLayoutMismatch();
            }
        } catch {
            revert StorageLayoutMismatch();
        }
    }

    function _setInstanceAdmin(address instanceAdmin_) internal {
        if (instanceAdmin_ == address(0)) revert Errors.ZeroAddress();
        instanceAdmin = instanceAdmin_;
        emit InstanceAdminUpdated(instanceAdmin_);
    }

    function _setCreateFeeConfig(address recipient, uint256 feeAmount) internal {
        if (recipient == address(0)) revert InvalidReceiver();

        protocolFeeRecipient = recipient;
        createFeeAmount = feeAmount;
        emit CreateFeeConfigUpdated(recipient, feeAmount);
    }

    function _collectCreateFee(address paymentToken) internal {
        uint256 feeAmountWad = createFeeAmount;
        if (feeAmountWad == 0) return;
        if (paymentToken == address(0)) revert Errors.ZeroAddress();

        uint256 feeAmount = _rawPaymentAmount(paymentToken, feeAmountWad);
        IERC20(paymentToken).safeTransferFrom(msg.sender, protocolFeeRecipient, feeAmount);
        emit CreateFeePaid(msg.sender, paymentToken, protocolFeeRecipient, feeAmount);
    }

    function _rawPaymentAmount(address paymentToken, uint256 amountWad) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(paymentToken).decimals();
        if (decimals > 18) revert InvalidPaymentTokenDecimals();

        return Math.ceilDiv(amountWad, 10 ** (18 - decimals));
    }
}
