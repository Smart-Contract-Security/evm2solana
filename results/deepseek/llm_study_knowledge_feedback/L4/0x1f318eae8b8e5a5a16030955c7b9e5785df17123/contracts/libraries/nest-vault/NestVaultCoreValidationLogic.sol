// SPDX-License-Identifier: AGPL-3.0-only

import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {IERC7540Operator} from "contracts/interfaces/IERC7540.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";
import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {Errors} from "contracts/types/Errors.sol";

library NestVaultCoreValidationLogic {
    function validateRequestRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint64 _shares,
        address _controller,
        address _owner,
        address _caller,
        address /*shareToken*/
    ) external view {
        _validateCaller($, _owner, _caller);
        if (_controller == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_shares == 0) {
            revert Errors.ZeroShares();
        }
    }

    function validateFulfillRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _controller,
        uint64 _shares,
        uint64 _assets
    ) external view {
        uint64 pendingShares = $.pendingRedeem[_controller].shares;
        if (pendingShares == 0) {
            revert Errors.NoPendingRedeem();
        }
        if (_shares > pendingShares) {
            revert Errors.InsufficientBalance();
        }
        if (_assets == 0) {
            revert Errors.ZeroAssets();
        }
    }

    function validateInstantRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint64 _shares,
        address _receiver,
        address _owner,
        address _caller,
        address /*shareToken*/
    ) external view {
        _validateCaller($, _owner, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_shares == 0) {
            revert Errors.ZeroShares();
        }
    }

    function validateUpdateRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint64 _newShares,
        address _controller,
        address _receiver,
        address _caller,
        uint64 _oldShares
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_oldShares == 0) {
            revert Errors.NoPendingRedeem();
        }
        if (_oldShares < _newShares) {
            revert Errors.InsufficientBalance();
        }
    }

    function validateWithdraw(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint64 _assets,
        address _receiver,
        address _controller,
        address _caller
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_assets == 0) {
            revert Errors.ZeroAssets();
        }
        uint64 claimableAssets = $.claimableRedeem[_controller].assets;
        if (claimableAssets < _assets) {
            revert Errors.InsufficientClaimable();
        }
    }

    function validateRedeem(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        uint64 _shares,
        address _controller,
        address _receiver,
        address _caller
    ) external view {
        _validateCaller($, _controller, _caller);
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_shares == 0) {
            revert Errors.ZeroShares();
        }
        uint64 claimableShares = $.claimableRedeem[_controller].shares;
        if (claimableShares < _shares) {
            revert Errors.InsufficientClaimable();
        }
    }

    function validateAuthorizeOperator(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bytes32 _nonce,
        uint64 _deadline
    ) external view {
        if (_controller == address(0)) revert Errors.ZeroAddress();
        if (_operator == address(0)) revert Errors.ZeroAddress();
        if (_controller == _operator) {
            revert Errors.ERC7540SelfOperatorNotAllowed();
        }
        if (block.timestamp > _deadline) {
            revert Errors.ERC7540Expired();
        }
        if ($.authorizations[_controller][_nonce]) {
            revert Errors.ERC7540UsedAuthorization();
        }
    }

    function validateSetOperator(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        address _operator,
        address _caller
    ) external pure {
        if (_operator == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_caller == _operator) {
            revert Errors.ERC7540SelfOperatorNotAllowed();
        }
    }

    function validateDeposit(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        bool _isAuthorized,
        uint64 _assets,
        uint64 _shares
    ) external pure {
        if (!_isAuthorized) {
            revert Errors.Unauthorized();
        }
        if (_assets > 0 && _shares == 0) {
            revert Errors.ZeroShares();
        }
    }

    function validateSetAccountant(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        address _accountant,
        address _asset
    ) external view {
        if (_accountant.code.length == 0) {
            revert Errors.IncompatibleAccountant();
        }
        (bool success, bytes memory returnData) =
            _accountant.staticcall(abi.encodeWithSelector(NestHubAccountant.getRateInQuoteSafe.selector, _asset));
        bool validResponse = success && returnData.length >= 32;
        bool revertedPaused = !success && returnData.length >= 4 && bytes4(returnData) == Errors.Paused.selector;

        if (!validResponse && !revertedPaused) {
            revert Errors.IncompatibleAccountant();
        }
    }

    function validateSetFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        NestVaultCoreTypes.Fee calldata _fee
    ) external view {
        NestVaultCoreTypes.Fee storage maxFee = $.maxFees[_f];
        if (_fee.rate > maxFee.rate) revert Errors.InvalidFee();
        if (_fee.flat > maxFee.flat) revert Errors.InvalidFee();
    }

    function validateSetMaxFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        NestVaultCoreTypes.Fee calldata _maxFee
    ) external view {
        if (_maxFee.rate > NestVaultCoreTypes.FEE_CAP) revert Errors.InvalidFee();
        NestVaultCoreTypes.Fee storage currentFee = $.fees[_f];
        if (_maxFee.rate < currentFee.rate) revert Errors.InvalidFee();
        if (_maxFee.flat < currentFee.flat) revert Errors.InvalidFee();
    }

    function validateClaimFee(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        NestVaultCoreTypes.Fees _f,
        address _receiver
    ) external view {
        if (_receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if ($.claimableFees[_f] == 0) {
            revert Errors.ZeroFeesOwed();
        }
    }

    function validateRedeemPayout(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        uint64 _assets,
        uint64 _shares,
        uint64 _claimableShares
    ) external pure {
        if (_assets == 0 && _shares != _claimableShares) {
            revert Errors.ERC7540ZeroPayout();
        }
    }

    function validateOperatorRegistry(
        NestVaultCoreTypes.NestVaultCoreStorage storage,
        /*$*/
        address _operatorRegistry
    )
        internal
        view
    {
        if (_operatorRegistry == address(0)) return;

        (bool success, bytes memory data) = _operatorRegistry.staticcall(
            abi.encodeWithSelector(IERC7540Operator.isOperator.selector, address(0), address(0))
        );
        if (!success || data.length < 32) {
            revert Errors.IncompatibleOperatorRegistry();
        }
    }

    function isOperator(NestVaultCoreTypes.NestVaultCoreStorage storage $, address _controller, address _operator)
        internal
        view
        returns (bool)
    {
        bool _approved = $.isVaultOperator[_controller][_operator];
        OperatorRegistry registry = $.operatorRegistry;
        if (address(registry) == address(0)) return _approved;
        return _approved || registry.isOperator(_controller, _operator);
    }

    function _validateCaller(NestVaultCoreTypes.NestVaultCoreStorage storage $, address _account, address _caller)
        private
        view
    {
        if (_account != _caller && !isOperator($, _account, _caller)) {
            revert Errors.Unauthorized();
        }
    }
}