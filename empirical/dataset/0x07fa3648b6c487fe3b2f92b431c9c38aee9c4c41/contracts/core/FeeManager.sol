// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract FeeManager is Ownable {
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    uint256 public globalFeeBps;
    address public feeRecipient;

    mapping(bytes32 => uint256) private _merchantFeeBps;
    mapping(bytes32 => bool)    private _hasMerchantOverride;

    event GlobalFeeUpdated(uint256 oldBps, uint256 newBps);
    event MerchantFeeUpdated(bytes32 indexed merchantId, uint256 bps);
    event MerchantFeeCleared(bytes32 indexed merchantId);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    error FeeTooHigh(uint256 bps, uint256 max);
    error ZeroAddress();

    constructor(uint256 _globalFeeBps, address _feeRecipient) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_globalFeeBps > MAX_FEE_BPS) revert FeeTooHigh(_globalFeeBps, MAX_FEE_BPS);
        globalFeeBps = _globalFeeBps;
        feeRecipient = _feeRecipient;
    }

    function computeFee(
        bytes32 merchantId,
        uint256 amount
    ) external view returns (uint256 fee, uint256 merchantAmount) {
        uint256 bps = _hasMerchantOverride[merchantId]
            ? _merchantFeeBps[merchantId]
            : globalFeeBps;
        fee = (amount * bps) / 10_000;
        merchantAmount = amount - fee;
    }

    function getFeeBps(bytes32 merchantId) external view returns (uint256) {
        return _hasMerchantOverride[merchantId]
            ? _merchantFeeBps[merchantId]
            : globalFeeBps;
    }

    function setGlobalFeeBps(uint256 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh(bps, MAX_FEE_BPS);
        emit GlobalFeeUpdated(globalFeeBps, bps);
        globalFeeBps = bps;
    }

    function setMerchantFeeBps(bytes32 merchantId, uint256 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh(bps, MAX_FEE_BPS);
        _merchantFeeBps[merchantId] = bps;
        _hasMerchantOverride[merchantId] = true;
        emit MerchantFeeUpdated(merchantId, bps);
    }

    function clearMerchantFeeBps(bytes32 merchantId) external onlyOwner {
        delete _merchantFeeBps[merchantId];
        delete _hasMerchantOverride[merchantId];
        emit MerchantFeeCleared(merchantId);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, recipient);
        feeRecipient = recipient;
    }
}
