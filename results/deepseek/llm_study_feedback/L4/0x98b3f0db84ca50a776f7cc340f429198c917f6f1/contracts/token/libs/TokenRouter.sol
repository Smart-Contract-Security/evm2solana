// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============ Internal Imports ============
import {TypeCasts} from "../../libs/TypeCasts.sol";
import {GasRouter} from "../../client/GasRouter.sol";
import {TokenMessage} from "./TokenMessage.sol";
import {Quote, ITokenBridge, ITokenFee} from "../../interfaces/ITokenBridge.sol";
import {Quotes} from "./Quotes.sol";
import {StandardHookMetadata} from "../../hooks/libs/StandardHookMetadata.sol";

// ============ External Imports ============
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract TokenRouter is GasRouter, ITokenBridge {
    using TypeCasts for bytes32;
    using TypeCasts for address;
    using TokenMessage for bytes;
    using StandardHookMetadata for bytes;
    using StorageSlot for bytes32;
    using Quotes for Quote[];
    using Math for uint256;
    using SafeERC20 for IERC20;

    event SentTransferRemote(
        uint32 indexed destination,
        bytes32 indexed recipient,
        uint256 amountOrId
    );

    event ReceivedTransferRemote(
        uint32 indexed origin,
        bytes32 indexed recipient,
        uint256 amountOrId
    );

    uint256 public immutable scaleNumerator;
    uint256 public immutable scaleDenominator;

    bytes32 private constant FEE_RECIPIENT_SLOT =
        keccak256("FungibleTokenRouter.feeRecipient");
    bytes32 private constant FEE_HOOK_SLOT = keccak256("TokenRouter.feeHook");

    event FeeRecipientSet(address feeRecipient);
    event FeeHookSet(address feeHook);

    constructor(
        uint256 _scaleNumerator,
        uint256 _scaleDenominator,
        address _mailbox
    ) GasRouter(_mailbox) {
        require(
            _scaleNumerator > 0 && _scaleDenominator > 0,
            "TokenRouter: scale cannot be 0"
        );
        scaleNumerator = _scaleNumerator;
        scaleDenominator = _scaleDenominator;
    }

    function token() public view virtual returns (address);

    function quoteTransferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount
    ) external view virtual override returns (Quote[] memory quotes) {
        address _feeToken = feeToken();
        quotes = new Quote[](3);
        quotes[0] = Quote({
            token: _feeToken,
            amount: _quoteGasPayment(
                _destination,
                _recipient,
                _amount,
                _feeToken
            )
        });
        (, uint256 feeAmount) = _feeRecipientAndAmount(
            _destination,
            _recipient,
            _amount
        );
        quotes[1] = Quote({token: token(), amount: _amount + feeAmount});
        quotes[2] = Quote({
            token: token(),
            amount: _externalFeeAmount(_destination, _recipient, _amount)
        });
    }

    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount
    ) public payable virtual returns (bytes32 messageId) {
        return _transferRemote(_destination, _recipient, _amount);
    }

    function _transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount
    ) internal virtual returns (bytes32 messageId) {
        address _feeHook = feeHook();
        address _feeToken = feeToken();

        (, uint256 remainingNativeValue) = _calculateFeesAndCharge(
            _destination,
            _recipient,
            _amount,
            msg.value,
            _feeHook
        );

        uint256 scaledAmount = _outboundAmount(_amount);

        bytes memory _tokenMessage = TokenMessage.format(
            _recipient,
            scaledAmount
        );

        messageId = _emitAndDispatch(
            _destination,
            _recipient,
            scaledAmount,
            remainingNativeValue,
            _tokenMessage,
            _feeToken
        );
    }

    function _calculateFeesAndCharge(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        uint256 _msgValue,
        address _feeHook
    ) internal returns (uint256 externalFee, uint256 remainingNativeValue) {
        (address _feeRecipient, uint256 feeAmount) = _feeRecipientAndAmount(
            _destination,
            _recipient,
            _amount
        );
        externalFee = _externalFeeAmount(_destination, _recipient, _amount);
        uint256 charge = _amount + feeAmount + externalFee;

        address _token = token();

        if (_feeHook != address(0)) {
            uint256 hookFee = _quoteGasPayment(
                _destination,
                _recipient,
                _amount,
                _token
            );

            if (_token != address(this)) {
                charge += hookFee;
            } else {
                IERC20(_token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    hookFee
                );
            }

            IERC20(_token).forceApprove(_feeHook, hookFee);
        }

        _transferFromSender(charge);

        if (feeAmount > 0) {
            _transferFee(_feeRecipient, feeAmount);
        }

        remainingNativeValue = _token != address(0)
            ? _msgValue
            : _msgValue - charge;
    }

    function _calculateFeesAndCharge(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        uint256 _msgValue
    ) internal returns (uint256 externalFee, uint256 remainingNativeValue) {
        return
            _calculateFeesAndCharge(
                _destination,
                _recipient,
                _amount,
                _msgValue,
                feeHook()
            );
    }

    function _emitAndDispatch(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        uint256 _messageDispatchValue,
        bytes memory _tokenMessage,
        address _feeToken
    ) internal returns (bytes32 messageId) {
        emit SentTransferRemote(_destination, _recipient, _amount);

        messageId = _Router_dispatch(
            _destination,
            _messageDispatchValue,
            _tokenMessage,
            _generateHookMetadata(_destination, _feeToken),
            address(hook)
        );
    }

    function _emitAndDispatch(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        uint256 _messageDispatchValue,
        bytes memory _tokenMessage
    ) internal returns (bytes32 messageId) {
        address _feeToken = feeToken();
        return
            _emitAndDispatch(
                _destination,
                _recipient,
                _amount,
                _messageDispatchValue,
                _tokenMessage,
                _feeToken
            );
    }

    function setFeeRecipient(address recipient) public onlyOwner {
        require(recipient != address(this), "Fee recipient cannot be self");
        FEE_RECIPIENT_SLOT.getAddressSlot().value = recipient;
        emit FeeRecipientSet(recipient);
    }

    function feeRecipient() public view virtual returns (address) {
        return FEE_RECIPIENT_SLOT.getAddressSlot().value;
    }

    function _TokenRouter_initialize(address _feeHook) internal {
        _setFeeHook(_feeHook);
    }

    function setFeeHook(address _feeHook) external onlyOwner {
        _setFeeHook(_feeHook);
    }

    function _setFeeHook(address _feeHook) internal {
        if (_feeHook != address(0)) {
            require(
                token() != address(0),
                "TokenRouter: fee hook requires ERC20 token"
            );
        }
        FEE_HOOK_SLOT.getAddressSlot().value = _feeHook;
        emit FeeHookSet(_feeHook);
    }

    function feeHook() public view returns (address) {
        return FEE_HOOK_SLOT.getAddressSlot().value;
    }

    function feeToken() public view returns (address) {
        return feeHook() != address(0) ? token() : address(0);
    }

    function _externalFeeAmount(
        uint32,
        bytes32,
        uint256
    ) internal view virtual returns (uint256 feeAmount) {
        return 0;
    }

    function _feeRecipientAndAmount(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount
    ) internal view returns (address _feeRecipient, uint256 feeAmount) {
        _feeRecipient = feeRecipient();
        if (_feeRecipient == address(0)) {
            return (_feeRecipient, 0);
        }

        Quote[] memory quotes = ITokenFee(_feeRecipient).quoteTransferRemote(
            _destination,
            _recipient,
            _amount
        );
        if (quotes.length == 0) {
            return (_feeRecipient, 0);
        }

        require(
            quotes.length == 1 && quotes[0].token == token(),
            "FungibleTokenRouter: fee must match token"
        );
        feeAmount = quotes[0].amount;
    }

    function _quoteGasPayment(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        address _feeToken
    ) internal view virtual returns (uint256) {
        return
            _Router_quoteDispatch(
                _destination,
                TokenMessage.format(_recipient, _outboundAmount(_amount)),
                _generateHookMetadata(_destination, _feeToken),
                address(hook)
            );
    }

    function _generateHookMetadata(
        uint32 _destination,
        address _feeToken
    ) internal view returns (bytes memory) {
        uint256 gasLimit = destinationGas[_destination];
        return
            StandardHookMetadata.formatWithFeeToken(
                0,
                gasLimit,
                msg.sender,
                _feeToken
            );
    }

    function _transferFromSender(uint256 _amountOrId) internal virtual;

    function _transferTo(
        address _recipient,
        uint256 _amountOrId
    ) internal virtual;

    function _transferFee(
        address _recipient,
        uint256 _amount
    ) internal virtual {
        _transferTo(_recipient, _amount);
    }

    function _outboundAmount(
        uint256 _localAmount
    ) internal view virtual returns (uint256 _messageAmount) {
        _messageAmount = _localAmount.mulDiv(
            scaleNumerator,
            scaleDenominator,
            Math.Rounding.Down
        );
    }

    function _inboundAmount(
        uint256 _messageAmount
    ) internal view virtual returns (uint256 _localAmount) {
        _localAmount = _messageAmount.mulDiv(
            scaleDenominator,
            scaleNumerator,
            Math.Rounding.Down
        );
    }

    function _handle(
        uint32 _origin,
        bytes32,
        bytes calldata _message
    ) internal virtual override {
        bytes32 recipient = _message.recipient();
        uint256 amount = _message.amount();

        emit ReceivedTransferRemote(_origin, recipient, amount);

        _transferTo(recipient.bytes32ToAddress(), _inboundAmount(amount));
    }
}