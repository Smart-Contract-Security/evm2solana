// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { OAppCore } from "./OAppCore.sol";

abstract contract OAppSender is OAppCore {
    uint64 internal constant SENDER_VERSION = 1;

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

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
        _payNative(_fee.nativeFee);
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);

        return
            endpoint.send(
                MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, _fee.lzTokenFee > 0),
                _refundAddress
            );
    }

    function _payNative(uint256 _nativeFee) internal virtual returns (uint256 nativeFee) {
        if (tx.value != _nativeFee) {
            revert("NotEnoughNative");
        }
        return _nativeFee;
    }

    function _payLzToken(uint256 _lzTokenFee) internal virtual {
        address lzToken = endpoint.lzToken();
        if (lzToken == address(0)) {
            revert("LzTokenUnavailable");
        }

        (bool success, bytes memory returndata) = lzToken.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                tx.origin,
                address(endpoint),
                _lzTokenFee
            )
        );
        require(success, "LZ token transfer failed");
    }
}