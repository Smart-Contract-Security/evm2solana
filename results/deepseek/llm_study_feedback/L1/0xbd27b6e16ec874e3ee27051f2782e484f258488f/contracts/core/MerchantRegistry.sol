// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import 'solana';

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        address initialOwner = tx.accounts.owner.key;
        if (initialOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        require(owner() == tx.accounts.owner.key, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

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

    constructor() {}

    function registerMerchant(bytes32 merchantId, address settlementWallet) external onlyOwner {
        require(settlementWallet != address(0), "Zero address");
        require(_merchants[merchantId].registeredAt == 0, "Merchant already registered");
        _merchants[merchantId] = Merchant({
            settlementWallet: settlementWallet,
            active: true,
            registeredAt: block.timestamp
        });
        emit MerchantRegistered(merchantId, settlementWallet);
    }

    function updateMerchantWallet(bytes32 merchantId, address newWallet) external onlyOwner {
        require(newWallet != address(0), "Zero address");
        Merchant storage m = _merchants[merchantId];
        require(m.registeredAt != 0, "Merchant not found");
        emit MerchantWalletUpdated(merchantId, m.settlementWallet, newWallet);
        m.settlementWallet = newWallet;
    }

    function suspendMerchant(bytes32 merchantId) external onlyOwner {
        require(_merchants[merchantId].registeredAt != 0, "Merchant not found");
        _merchants[merchantId].active = false;
        emit MerchantSuspended(merchantId);
    }

    function reactivateMerchant(bytes32 merchantId) external onlyOwner {
        require(_merchants[merchantId].registeredAt != 0, "Merchant not found");
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