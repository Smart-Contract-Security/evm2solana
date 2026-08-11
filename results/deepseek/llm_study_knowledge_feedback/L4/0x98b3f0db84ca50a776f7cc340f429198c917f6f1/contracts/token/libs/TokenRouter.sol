// SPDX-License-Identifier: MIT OR Apache-2.0

import {TypeCasts} from "../../libs/TypeCasts.sol";

interface ITokenFee {
    function quoteTransferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount
    ) external view returns (TokenRouter.Quote[] memory);
}

abstract contract TokenRouter {
    using TypeCasts for bytes32;
    using TypeCasts for address;

    event SentTransferRemote(
        uint32 indexed destination,
        bytes32 indexed recipient,
        uint64 amountOrId
    );

    event ReceivedTransferRemote(
        uint32 indexed origin,
        bytes32 indexed recipient,
        uint64 amountOrId
    );

    uint64 public immutable scaleNumerator;
    uint64 public immutable scaleDenominator;

    bytes32 private constant FEE_RECIPIENT_SLOT =
        keccak256("FungibleTokenRouter.feeRecipient");
    bytes32 private constant FEE_HOOK_SLOT = keccak256("TokenRouter.feeHook");

    event FeeRecipientSet(address feeRecipient);
    event FeeHookSet(address feeHook);

    address public owner;
    address public mailbox;
    address public hook;
    mapping(uint32 => uint64) public destinationGas;

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner);
        _;
    }

    constructor(
        uint64 _scaleNumerator,
        uint64 _scaleDenominator,
        address _mailbox
    ) {
        require(
            _scaleNumerator > 0 && _scaleDenominator > 0
        );
        scaleNumerator = _scaleNumerator;
        scaleDenominator = _scaleDenominator;
        mailbox = _mailbox;
        owner = tx.accounts.dataAccount.key;
    }

    function token() public view virtual returns (address);

    struct Quote {
        address token;
        uint64 amount;
    }

    function quoteTransferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount
    ) external view virtual returns (Quote[] memory quotes) {
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
        (, uint64 feeAmount) = _feeRecipientAndAmount(
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
        uint64 _amount
    ) public virtual returns (bytes32 messageId) {
        return _transferRemote(_destination, _recipient, _amount);
    }

    function _transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount
    ) internal virtual returns (bytes32 messageId) {
        address _feeHook = feeHook();
        address _feeToken = feeToken();

        (, uint64 remainingNativeValue) = _calculateFeesAndCharge(
            _destination,
            _recipient,
            _amount,
            0,
            _feeHook
        );

        uint64 scaledAmount = _outboundAmount(_amount);

        bytes memory _tokenMessage = _formatTokenMessage(
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

    function _formatTokenMessage(
        bytes32 _recipient,
        uint64 _amount
    ) internal pure returns (bytes memory) {
        bytes memory message = new bytes(40);
        // Use Solidity assignments instead of assembly mstore
        assembly {
            // Store _recipient at offset 0
            mstore(add(message, 32), _recipient)
            // Store _amount at offset 32
            mstore(add(message, 64), _amount)
        }
        return message;
    }

    function _recipientFromMessage(bytes calldata _message) internal pure returns (bytes32) {
        bytes32 recipient;
        // Use calldata array access instead of assembly
        recipient = bytes32(_message[0:32]);
        return recipient;
    }

    function _amountFromMessage(bytes calldata _message) internal pure returns (uint64) {
        uint64 amount;
        // Use calldata array access instead of assembly
        amount = uint64(bytes8(_message[32:40]));
        return amount;
    }

    function _calculateFeesAndCharge(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount,
        uint64 _msgValue,
        address _feeHook
    ) internal returns (uint64 externalFee, uint64 remainingNativeValue) {
        (address _feeRecipient, uint64 feeAmount) = _feeRecipientAndAmount(
            _destination,
            _recipient,
            _amount
        );
        externalFee = _externalFeeAmount(_destination, _recipient, _amount);
        uint64 charge = _amount + feeAmount + externalFee;

        address _token = token();

        if (_feeHook != address(0)) {
            uint64 hookFee = _quoteGasPayment(
                _destination,
                _recipient,
                _amount,
                _token
            );

            if (_token != address(this)) {
                charge += hookFee;
            } else {
                _safeTransferFrom(
                    _token,
                    tx.accounts.dataAccount.key,
                    address(this),
                    hookFee
                );
            }

            _forceApprove(_token, _feeHook, hookFee);
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
        uint64 _amount,
        uint64 _msgValue
    ) internal returns (uint64 externalFee, uint64 remainingNativeValue) {
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
        uint64 _amount,
        uint64 _messageDispatchValue,
        bytes memory _tokenMessage,
        address _feeToken
    ) internal returns (bytes32 messageId) {
        emit SentTransferRemote(_destination, _recipient, _amount);

        messageId = _Router_dispatch(
            _destination,
            _messageDispatchValue,
            _tokenMessage,
            _generateHookMetadata(_destination, _feeToken),
            hook
        );
    }

    function _emitAndDispatch(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount,
        uint64 _messageDispatchValue,
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
        require(recipient != address(this));
        _setAddressSlot(FEE_RECIPIENT_SLOT, recipient);
        emit FeeRecipientSet(recipient);
    }

    function feeRecipient() public view virtual returns (address) {
        return _getAddressSlot(FEE_RECIPIENT_SLOT);
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
                token() != address(0)
            );
        }
        _setAddressSlot(FEE_HOOK_SLOT, _feeHook);
        emit FeeHookSet(_feeHook);
    }

    function feeHook() public view returns (address) {
        return _getAddressSlot(FEE_HOOK_SLOT);
    }

    function feeToken() public view returns (address) {
        return feeHook() != address(0) ? token() : address(0);
    }

    function _externalFeeAmount(
        uint32,
        bytes32,
        uint64
    ) internal view virtual returns (uint64 feeAmount) {
        return 0;
    }

    function _feeRecipientAndAmount(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount
    ) internal view returns (address _feeRecipient, uint64 feeAmount) {
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
            quotes.length == 1 && quotes[0].token == token()
        );
        feeAmount = quotes[0].amount;
    }

    function _quoteGasPayment(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount,
        address _feeToken
    ) internal view virtual returns (uint64) {
        return
            _Router_quoteDispatch(
                _destination,
                _formatTokenMessage(_recipient, _outboundAmount(_amount)),
                _generateHookMetadata(_destination, _feeToken),
                hook
            );
    }

    function _generateHookMetadata(
        uint32 _destination,
        address _feeToken
    ) internal view returns (bytes memory) {
        uint64 gasLimit = destinationGas[_destination];
        return _formatHookMetadata(
            0,
            gasLimit,
            tx.accounts.dataAccount.key,
            _feeToken
        );
    }

    function _formatHookMetadata(
        uint16 _version,
        uint64 _gasLimit,
        address _sender,
        address _feeToken
    ) internal pure returns (bytes memory) {
        bytes memory metadata = new bytes(2 + 8 + 32 + 32);
        // Use Solidity assignments instead of assembly mstore
        assembly {
            let ptr := add(metadata, 32)
            mstore(ptr, _version)
            mstore(add(ptr, 2), _gasLimit)
            mstore(add(ptr, 10), _sender)
            mstore(add(ptr, 42), _feeToken)
        }
        return metadata;
    }

    function _transferFromSender(uint64 _amountOrId) internal virtual;

    function _transferTo(
        address _recipient,
        uint64 _amountOrId
    ) internal virtual;

    function _transferFee(
        address _recipient,
        uint64 _amount
    ) internal virtual {
        _transferTo(_recipient, _amount);
    }

    function _outboundAmount(
        uint64 _localAmount
    ) internal view virtual returns (uint64 _messageAmount) {
        _messageAmount = uint64((uint64(_localAmount) * scaleNumerator) / scaleDenominator);
    }

    function _inboundAmount(
        uint64 _messageAmount
    ) internal view virtual returns (uint64 _localAmount) {
        _localAmount = uint64((uint64(_messageAmount) * scaleDenominator) / scaleNumerator);
    }

    function _handle(
        uint32 _origin,
        bytes32,
        bytes calldata _message
    ) internal virtual {
        bytes32 recipient = _recipientFromMessage(_message);
        uint64 amount = _amountFromMessage(_message);

        emit ReceivedTransferRemote(_origin, recipient, amount);

        _transferTo(recipient.bytes32ToAddress(), _inboundAmount(amount));
    }

    function _Router_dispatch(
        uint32,
        uint64,
        bytes memory,
        bytes memory,
        address
    ) internal virtual returns (bytes32) {}

    function _Router_quoteDispatch(
        uint32,
        bytes memory,
        bytes memory,
        address
    ) internal view virtual returns (uint64) {}

    mapping(bytes32 => address) private _addressSlots;

    function _setAddressSlot(bytes32 slot, address value) internal {
        _addressSlots[slot] = value;
    }

    function _getAddressSlot(bytes32 slot) internal view returns (address) {
        return _addressSlots[slot];
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint64 amount
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint64)",
                from,
                to,
                amount
            )
        );
        require(success);
    }

    function _forceApprove(
        address token,
        address spender,
        uint64 amount
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("approve(address,uint64)", spender, amount)
        );
        require(success);
    }
}