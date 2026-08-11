// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MerchantRegistry is Ownable {
    struct Merchant {
        address settlementWallet;
        bool    active;
        uint256 registeredAt;
    }

    mapping(bytes32 => Merchant) private _merchants;

    event MerchantRegistered(bytes32 indexed merchantId, address settlementWallet);
    event MerchantWalletUpdated(bytes32 indexed merchantId, address oldWallet, address newWallet);
    event MerchantSuspended(bytes32 indexed merchantId);
    event MerchantReactivated(bytes32 indexed merchantId);

    error MerchantAlreadyRegistered(bytes32 merchantId);
    error MerchantNotFound(bytes32 merchantId);
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    function registerMerchant(bytes32 merchantId, address settlementWallet) external onlyOwner {
        if (settlementWallet == address(0)) revert ZeroAddress();
        if (_merchants[merchantId].registeredAt != 0) revert MerchantAlreadyRegistered(merchantId);
        _merchants[merchantId] = Merchant({
            settlementWallet: settlementWallet,
            active: true,
            registeredAt: block.timestamp
        });
        emit MerchantRegistered(merchantId, settlementWallet);
    }

    function updateMerchantWallet(bytes32 merchantId, address newWallet) external onlyOwner {
        if (newWallet == address(0)) revert ZeroAddress();
        Merchant storage m = _merchants[merchantId];
        if (m.registeredAt == 0) revert MerchantNotFound(merchantId);
        emit MerchantWalletUpdated(merchantId, m.settlementWallet, newWallet);
        m.settlementWallet = newWallet;
    }

    function suspendMerchant(bytes32 merchantId) external onlyOwner {
        if (_merchants[merchantId].registeredAt == 0) revert MerchantNotFound(merchantId);
        _merchants[merchantId].active = false;
        emit MerchantSuspended(merchantId);
    }

    function reactivateMerchant(bytes32 merchantId) external onlyOwner {
        if (_merchants[merchantId].registeredAt == 0) revert MerchantNotFound(merchantId);
        _merchants[merchantId].active = true;
        emit MerchantReactivated(merchantId);
    }

    function getMerchant(bytes32 merchantId) external view returns (Merchant memory) {
        return _merchants[merchantId];
    }

    function getMerchantWallet(bytes32 merchantId) external view returns (address) {
        return _merchants[merchantId].settlementWallet;
    }

    function isMerchantActive(bytes32 merchantId) external view returns (bool) {
        return _merchants[merchantId].active;
    }
}