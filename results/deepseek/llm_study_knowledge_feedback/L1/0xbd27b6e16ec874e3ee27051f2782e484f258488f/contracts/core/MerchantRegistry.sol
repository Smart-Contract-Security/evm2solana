import 'solana';

contract MerchantRegistry {
    struct Merchant {
        address settlementWallet;
        bool    active;
        uint64 registeredAt;
    }

    mapping(bytes32 => Merchant) private _merchants;
    address private _owner;

    event MerchantRegistered(bytes32 merchantId, address settlementWallet);
    event MerchantWalletUpdated(bytes32 merchantId, address oldWallet, address newWallet);
    event MerchantSuspended(bytes32 merchantId);
    event MerchantReactivated(bytes32 merchantId);

    @payer(payer)
    @space(2048)
    constructor(address payer) {
        _owner = tx.accounts.dataAccount.key;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    function registerMerchant(bytes32 merchantId, address settlementWallet) external onlyOwner {
        require(settlementWallet != address(0), "Zero address");
        require(_merchants[merchantId].registeredAt == 0, "Already registered");
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
        require(m.registeredAt != 0, "Not found");
        emit MerchantWalletUpdated(merchantId, m.settlementWallet, newWallet);
        m.settlementWallet = newWallet;
    }

    function suspendMerchant(bytes32 merchantId) external onlyOwner {
        require(_merchants[merchantId].registeredAt != 0, "Not found");
        _merchants[merchantId].active = false;
        emit MerchantSuspended(merchantId);
    }

    function reactivateMerchant(bytes32 merchantId) external onlyOwner {
        require(_merchants[merchantId].registeredAt != 0, "Not found");
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