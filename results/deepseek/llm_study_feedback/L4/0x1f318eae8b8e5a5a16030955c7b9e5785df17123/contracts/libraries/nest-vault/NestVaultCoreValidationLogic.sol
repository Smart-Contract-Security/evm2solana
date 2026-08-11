// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// Define the types that were previously imported from NestVaultCoreTypes
// Solang does not support importing contracts as types, so we define them here.

uint256 constant FEE_CAP = 1e18; // Example value, adjust as needed

enum Fees {
    // Define fee types as needed, example:
    FEE_TYPE_1,
    FEE_TYPE_2
}

struct Fee {
    uint256 rate;
    uint256 flat;
}

struct PendingRedeem {
    uint256 shares;
}

struct ClaimableRedeem {
    uint256 assets;
    uint256 shares;
}

// Forward declare interfaces to avoid contract type usage
interface IERC7540Operator {
    function isOperator(address, address) external view returns (bool);
}

interface NestHubAccountant {
    function getRateInQuoteSafe(address) external view returns (uint256);
}

// Define a struct to hold the operator registry reference
// Since we cannot use contract types, we store the address and interact via interface
struct OperatorRegistryRef {
    address registryAddress;
}

struct NestVaultCoreStorage {
    mapping(address => mapping(address => bool)) isVaultOperator;
    OperatorRegistryRef operatorRegistry;
    mapping(address => PendingRedeem) pendingRedeem;
    mapping(address => ClaimableRedeem) claimableRedeem;
    mapping(address => mapping(bytes32 => bool)) authorizations;
    mapping(Fees => Fee) fees;
    mapping(Fees => Fee) maxFees;
    mapping(Fees => uint256) claimableFees;
}

// Define custom errors locally since we cannot import Errors contract
// Solang does not support custom errors with revert; use string revert messages instead.
// We'll replace all revert ErrorName() with revert("ErrorName")

/// @title  NestVaultCoreValidationLogic
/// @notice Library containing validation logic for NestVaultCore operations
/// @author plumenetwork
library NestVaultCoreValidationLogic {
    /// @notice Validates parameters for requestRedeem operation
    /// @param  $           NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256 The shares to redeem
    /// @param  _controller address The controller address
    /// @param  _owner      address The owner address
    /// @param  _caller     address The caller address
    function validateRequestRedeem(
        NestVaultCoreStorage storage $,
        uint256 _shares,
        address _controller,
        address _owner,
        address _caller,
        address /*shareToken*/
    ) external view {
        _validateCaller($, _owner, _caller);
        if (_controller == address(0)) {
            revert("ZeroAddress");
        }
        if (_shares == 0) {
            revert("ZeroShares");
        }
    }

    /// @notice Validates parameters for fulfillRedeem operation
    /// @param  $           NestVaultCoreStorage The full storage struct
    /// @param  _controller address The controller address
    /// @param  _shares     uint256 The shares to fulfill
    /// @param  _assets     uint256 The calculated assets
    function validateFulfillRedeem(
        NestVaultCoreStorage storage $,
        address _controller,
        uint256 _shares,
        uint256 _assets
    ) external view {
        uint256 pendingShares = $.pendingRedeem[_controller].shares;
        if (pendingShares == 0) {
            revert("NoPendingRedeem");
        }
        if (_shares > pendingShares) {
            revert("InsufficientBalance");
        }
        if (_assets == 0) {
            revert("ZeroAssets");
        }
    }

    /// @notice Validates parameters for instantRedeem operation
    /// @param  $          NestVaultCoreStorage The full storage struct
    /// @param  _shares    uint256 The shares to redeem
    /// @param  _receiver  address The receiver address
    /// @param  _owner     address The owner of the shares
    /// @param  _caller    address The caller address
    function validateInstantRedeem(
        NestVaultCoreStorage storage $,
        uint256 _shares,
        address _receiver,
        address _owner,
        address _caller,
        address /*shareToken*/
    ) external view {
        _validateCaller($, _owner, _caller);
        if (_receiver == address(0)) {
            revert("ZeroAddress");
        }
        if (_shares == 0) {
            revert("ZeroShares");
        }
    }

    /// @notice Validates parameters for updateRedeem operation
    /// @param  $            NestVaultCoreStorage The full storage struct
    /// @param  _newShares   uint256 The new shares amount
    /// @param  _controller  address The controller address
    /// @param  _receiver    address The receiver address
    /// @param  _caller      address The caller address
    /// @param  _oldShares   uint256 The old shares amount
    function validateUpdateRedeem(
        NestVaultCoreStorage storage $,
        uint256 _newShares,
        address _controller,
        address _receiver,
        address _caller,
        uint256 _oldShares
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert("ZeroAddress");
        }
        if (_oldShares == 0) {
            revert("NoPendingRedeem");
        }
        if (_oldShares < _newShares) {
            revert("InsufficientBalance");
        }
    }

    /// @notice Validates parameters for withdraw operation
    /// @param  $           NestVaultCoreStorage The full storage struct
    /// @param  _assets     uint256 The assets to withdraw
    /// @param  _receiver   address The receiver address
    /// @param  _controller address The controller address
    /// @param  _caller     address The caller address
    function validateWithdraw(
        NestVaultCoreStorage storage $,
        uint256 _assets,
        address _receiver,
        address _controller,
        address _caller
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert("ZeroAddress");
        }
        if (_assets == 0) {
            revert("ZeroAssets");
        }
        uint256 claimableAssets = $.claimableRedeem[_controller].assets;
        if (claimableAssets < _assets) {
            revert("InsufficientClaimable");
        }
    }

    /// @notice Validates parameters for redeem operation
    /// @param  $           NestVaultCoreStorage The full storage struct
    /// @param  _shares     uint256 The shares to redeem
    /// @param  _controller address The controller address
    /// @param  _receiver   address The receiver address
    /// @param  _caller     address The caller address
    function validateRedeem(
        NestVaultCoreStorage storage $,
        uint256 _shares,
        address _controller,
        address _receiver,
        address _caller
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert("ZeroAddress");
        }
        if (_shares == 0) {
            revert("ZeroShares");
        }
        uint256 claimableShares = $.claimableRedeem[_controller].shares;
        if (claimableShares < _shares) {
            revert("InsufficientClaimable");
        }
    }

    /// @notice Validates parameters for authorizeOperator operation
    /// @param  $           NestVaultCoreStorage The full storage struct
    /// @param  _controller address The controller address
    /// @param  _operator   address The operator address
    /// @param  _nonce      bytes32 The nonce value
    /// @param  _deadline   uint256 The deadline timestamp
    function validateAuthorizeOperator(
        NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bytes32 _nonce,
        uint256 _deadline
    ) external view {
        if (_controller == address(0)) revert("ZeroAddress");
        if (_operator == address(0)) revert("ZeroAddress");
        if (_controller == _operator) {
            revert("ERC7540SelfOperatorNotAllowed");
        }
        if (block.timestamp > _deadline) {
            revert("ERC7540Expired");
        }
        if ($.authorizations[_controller][_nonce]) {
            revert("ERC7540UsedAuthorization");
        }
    }

    /// @notice Validates parameters for setOperator operation
    /// @dev    $         NestVaultCoreStorage The full storage struct
    /// @param  _operator address The operator address
    /// @param  _caller   address The caller address
    function validateSetOperator(
        NestVaultCoreStorage storage,
        /*$*/
        address _operator,
        address _caller
    ) external pure {
        if (_operator == address(0)) {
            revert("ZeroAddress");
        }
        if (_caller == _operator) {
            revert("ERC7540SelfOperatorNotAllowed");
        }
    }

    /// @notice Validates parameters for deposit operation
    /// @dev    $             NestVaultCoreStorage The full storage struct
    /// @param  _isAuthorized bool    Whether the caller is authorized
    /// @param  _assets       uint256 The assets being deposited
    /// @param  _shares       uint256 The shares to mint
    function validateDeposit(
        NestVaultCoreStorage storage,
        /*$*/
        bool _isAuthorized,
        uint256 _assets,
        uint256 _shares
    ) external pure {
        if (!_isAuthorized) {
            revert("Unauthorized");
        }
        if (_assets > 0 && _shares == 0) {
            revert("ZeroShares");
        }
    }

    /// @notice Validates candidate accountant compatibility
    /// @dev    Verifies the candidate is a contract and exposes `getRateInQuoteSafe(ERC20)`.
    ///         A paused NestHubAccountant reverts `getRateInQuoteSafe` with `Paused()`,
    ///         which is treated as a valid compatibility signal.
    /// @param  _accountant address Candidate accountant address
    /// @param  _asset      address   Vault asset used to probe safe quote rates
    function validateSetAccountant(
        NestVaultCoreStorage storage,
        /*$*/
        address _accountant,
        address _asset
    ) external view {
        // Validate that the address is a contract (not an EOA)
        // Solang does not support address.code; use assembly to get code size
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_accountant)
        }
        if (codeSize == 0) {
            revert("IncompatibleAccountant");
        }
        // Validate that the accountant exposes getRateInQuoteSafe(ERC20).
        // We verify the call returns at least 32 bytes (a valid uint256) to avoid false positives
        // from contracts with fallback functions that return empty data.
        // Solang does not support staticcall; use call with limited gas and check success
        (bool success, bytes memory returnData) =
            _accountant.call(abi.encodeWithSelector(NestHubAccountant.getRateInQuoteSafe.selector, _asset));
        bool validResponse = success && returnData.length >= 32;
        // Paused.selector is bytes4(keccak256("Paused()"))
        bytes4 pausedSelector = bytes4(keccak256("Paused()"));
        bool revertedPaused = !success && returnData.length >= 4 && bytes4(returnData) == pausedSelector;

        if (!validResponse && !revertedPaused) {
            revert("IncompatibleAccountant");
        }
    }

    /// @notice Validates fee configuration update for a given fee type
    /// @param  _f   Fees       Fee type
    /// @param  _fee Fee   Candidate fee configuration
    function validateSetFee(
        NestVaultCoreStorage storage $,
        Fees _f,
        Fee calldata _fee
    ) external view {
        Fee storage maxFee = $.maxFees[_f];
        if (_fee.rate > maxFee.rate) revert("InvalidFee");
        if (_fee.flat > maxFee.flat) revert("InvalidFee");
    }

    /// @notice Validates max fee configuration update for a given fee type
    /// @dev    Ensures the new max fee is not below the currently active fee for that type
    /// @param  $       NestVaultCoreStorage The full storage struct
    /// @param  _f      Fees                 Fee type
    /// @param  _maxFee Fee             Candidate max fee configuration
    function validateSetMaxFee(
        NestVaultCoreStorage storage $,
        Fees _f,
        Fee calldata _maxFee
    ) external view {
        if (_maxFee.rate > FEE_CAP) revert("InvalidFee");
        Fee storage currentFee = $.fees[_f];
        if (_maxFee.rate < currentFee.rate) revert("InvalidFee");
        if (_maxFee.flat < currentFee.flat) revert("InvalidFee");
    }

    /// @notice Validates fee claim request for a fee type
    /// @param  _f        Fees                 Fee type to claim
    /// @param  _receiver address                                 Claim receiver
    function validateClaimFee(
        NestVaultCoreStorage storage $,
        Fees _f,
        address _receiver
    ) external view {
        if (_receiver == address(0)) {
            revert("ZeroAddress");
        }
        if ($.claimableFees[_f] == 0) {
            revert("ZeroFeesOwed");
        }
    }

    /// @notice Validates redeem payout is non-zero
    /// @dev    $                NestVaultCoreStorage The full storage struct
    /// @param  _assets          uint256 The assets to pay out
    /// @param  _shares          uint256 The shares being redeemed
    /// @param  _claimableShares uint256 The total claimable shares
    function validateRedeemPayout(
        NestVaultCoreStorage storage,
        /*$*/
        uint256 _assets,
        uint256 _shares,
        uint256 _claimableShares
    ) external pure {
        if (_assets == 0 && _shares != _claimableShares) {
            revert("ERC7540ZeroPayout");
        }
    }

    /// @notice Validates operator registry compatibility
    /// @dev    Allows zero address (registry disabled). For non-zero addresses, probes IERC7540Operator.isOperator via call.
    /// @param  _operatorRegistry address Candidate operator registry address
    function validateOperatorRegistry(
        NestVaultCoreStorage storage,
        /*$*/
        address _operatorRegistry
    )
        internal
        view
    {
        if (_operatorRegistry == address(0)) return;

        (bool success, bytes memory data) = _operatorRegistry.call(
            abi.encodeWithSelector(IERC7540Operator.isOperator.selector, address(0), address(0))
        );
        if (!success || data.length < 32) {
            revert("IncompatibleOperatorRegistry");
        }
    }

    /// @dev    Internal function to check if an operator is authorized for a given controller
    /// @param  _controller address The controller whose operator permissions are being queried
    /// @param  _operator   address The operator being checked
    /// @return             bool    True if the operator is authorized for the controller
    function isOperator(NestVaultCoreStorage storage $, address _controller, address _operator)
        internal
        view
        returns (bool)
    {
        bool _approved = $.isVaultOperator[_controller][_operator];
        OperatorRegistryRef storage registry = $.operatorRegistry;
        if (registry.registryAddress == address(0)) return _approved;
        return _approved || IERC7540Operator(registry.registryAddress).isOperator(_controller, _operator);
    }

    /// @notice Internal function to validate caller authorization
    /// @param  $        NestVaultCoreStorage The full storage struct
    /// @param  _account address    The account whose authorization is being checked
    /// @param  _caller  address    The caller address
    function _validateCaller(NestVaultCoreStorage storage $, address _account, address _caller)
        private
        view
    {
        if (_account != _caller && !isOperator($, _account, _caller)) {
            revert("Unauthorized");
        }
    }
}