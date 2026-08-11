// SPDX-License-Identifier: MIT

import { OAppCore } from "./OAppCore.sol";

// Define MessagingFee and MessagingReceipt structs locally since they are not available
struct MessagingFee {
    uint64 nativeFee;
    uint64 lzTokenFee;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    // Add other fields as needed based on the actual definition
}

struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

abstract contract OAppSender is OAppCore {
    error NotEnoughNative(uint64 msgValue);
    error LzTokenUnavailable();

    uint64 internal constant SENDER_VERSION = 1;

    function oAppVersion() public view virtual returns (uint64 senderVersion, uint64 receiverVersion) {
        return (SENDER_VERSION, 0);
    }

    function _quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) internal view virtual returns (MessagingFee memory fee) {
        return
            endpoint.quote(
                MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, _payInLzToken),
                address(this)
            );
    }

    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory receipt) {
        uint64 messageValue = _payNative(_fee.nativeFee);
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);

        return
            endpoint.send(
                MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, _fee.lzTokenFee > 0),
                _refundAddress
            );
    }

    function _payNative(uint64 _nativeFee) internal virtual returns (uint64 nativeFee) {
        return _nativeFee;
    }

    function _payLzToken(uint64 _lzTokenFee) internal virtual {
        address lzToken = endpoint.lzToken();
        if (lzToken == address(0)) revert LzTokenUnavailable();
    }
}