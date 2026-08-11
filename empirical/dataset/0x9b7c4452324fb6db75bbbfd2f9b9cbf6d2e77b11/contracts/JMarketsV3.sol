// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/openzeppelin/security/ReentrancyGuard.sol";
import "./lib/openzeppelin/security/Pausable.sol";
import "./lib/openzeppelin/access/Ownable.sol";
import "./lib/openzeppelin/utils/math/SafeMath.sol";

interface IJVault {
    struct Vault {
        uint256 vaultId;
        address nftContract;
        uint256 tokenId;
        address seller;
        address buyer;
        uint256 listingPrice;
        uint256 commitmentAmount;
        uint256 totalDeposited;
        uint256 createdAt;
        uint256 lastDepositAt;
        uint256 deadline;
        bool isComplete;
        bool isAbandoned;
        bool isTransferable;
    }

    function getVault(uint256 vaultId) external view returns (Vault memory);
    function isVaultTransferable(uint256 vaultId) external view returns (bool);
    function getUserXP(address user) external view returns (uint256);
    function awardXPFromMarkets(address user, uint256 amount, string calldata reason) external;
    function nextVaultId() external view returns (uint256);
    function transferVaultFromMarket(uint256 vaultId, address newBuyer) external;
    function isVaultLiquidationEligible(uint256 vaultId) external view returns (bool, uint256);
}

/// @title JMarketsV3
/// @notice APE-priced secondary market for JVaultV3 vault positions. Same logic as
///         the original JMarkets except TRADING_FEE_BPS, MAX_BATCH_SIZE, and
///         XP_BUY_VAULT are admin-settable (bounded by caps).
contract JMarketsV3 is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;

    uint256 public constant BASIS_POINTS = 10000;

    uint256 public constant MAX_TRADING_FEE_BPS = 1000;  // 10%
    uint256 public constant MAX_BATCH_SIZE_CAP  = 200;

    uint256 public tradingFeeBps;
    uint256 public maxBatchSize;
    uint256 public xpBuyVault;

    struct VaultListing {
        uint256 vaultId;
        address seller;
        uint256 askingPrice;
        uint256 listedAt;
        bool isActive;
    }

    struct VaultSale {
        uint256 vaultId;
        address seller;
        address buyer;
        uint256 salePrice;
        uint256 soldAt;
        uint256 tradingFee;
    }

    IJVault public immutable jVault;

    mapping(uint256 => VaultListing) public vaultListings;
    mapping(uint256 => address) public vaultOwners;
    mapping(address => uint256[]) public userVaults;

    VaultSale[] public vaultSales;
    uint256 public totalTradingFees;

    uint256[] public activeListingIds;
    mapping(uint256 => uint256) public activeListingIndex;

    event VaultListedForSale(uint256 indexed vaultId, address indexed seller, uint256 askingPrice);
    event VaultSaleCancelled(uint256 indexed vaultId, address indexed seller);
    event VaultSold(uint256 indexed vaultId, address indexed seller, address indexed buyer, uint256 salePrice, uint256 tradingFee);
    event VaultOwnershipTransferred(uint256 indexed vaultId, address indexed previousOwner, address indexed newOwner);
    event TradingFeesWithdrawn(address indexed owner, uint256 amount);
    event VaultOwnershipSynced(uint256 indexed vaultId, address indexed owner);
    event VaultAutoDelisted(uint256 indexed vaultId, address indexed seller, string reason);
    event VaultPriceUpdated(uint256 indexed vaultId, uint256 newPrice);

    event TradingFeeBpsSet(uint256 oldValue, uint256 newValue);
    event MaxBatchSizeSet(uint256 oldValue, uint256 newValue);
    event XpBuyVaultSet(uint256 oldValue, uint256 newValue);

    modifier onlyVaultOwner(uint256 vaultId) {
        address marketOwner = vaultOwners[vaultId];
        address vaultBuyer = jVault.getVault(vaultId).buyer;

        bool isOwner = (marketOwner != address(0) ? marketOwner == msg.sender : vaultBuyer == msg.sender);
        require(isOwner, "Not vault owner");

        if (marketOwner == address(0) && vaultBuyer == msg.sender) {
            vaultOwners[vaultId] = msg.sender;
            if (!_userOwnsVault(msg.sender, vaultId)) {
                userVaults[msg.sender].push(vaultId);
            }
            emit VaultOwnershipSynced(vaultId, msg.sender);
        }
        _;
    }

    modifier validVaultForTrading(uint256 vaultId) {
        IJVault.Vault memory vault = jVault.getVault(vaultId);
        require(!vault.isComplete, "Vault completed");
        require(!vault.isAbandoned, "Vault abandoned");
        require(jVault.isVaultTransferable(vaultId), "Vault not transferable");
        _;
    }

    modifier onlyJVault() {
        require(msg.sender == address(jVault), "Only JVault");
        _;
    }

    constructor(address jVaultAddress, address initialOwner) Ownable() {
        require(jVaultAddress != address(0), "Invalid JVault");
        jVault = IJVault(jVaultAddress);

        tradingFeeBps = 100;  // 1%
        maxBatchSize  = 50;
        xpBuyVault    = 100;

        if (initialOwner != address(0) && initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
    }

    // --- Admin ---
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function setTradingFeeBps(uint256 v) external onlyOwner {
        require(v <= MAX_TRADING_FEE_BPS, "fee > cap");
        emit TradingFeeBpsSet(tradingFeeBps, v);
        tradingFeeBps = v;
    }

    function setMaxBatchSize(uint256 v) external onlyOwner {
        require(v > 0 && v <= MAX_BATCH_SIZE_CAP, "batch oob");
        emit MaxBatchSizeSet(maxBatchSize, v);
        maxBatchSize = v;
    }

    function setXpBuyVault(uint256 v) external onlyOwner {
        emit XpBuyVaultSet(xpBuyVault, v);
        xpBuyVault = v;
    }

    function notifyVaultStatusChange(uint256 vaultId, bool isAbandoned, bool isComplete) external onlyJVault {
        if ((isAbandoned || isComplete) && vaultListings[vaultId].isActive) {
            address seller = vaultListings[vaultId].seller;
            vaultListings[vaultId].isActive = false;
            _removeActiveListing(vaultId);
            emit VaultAutoDelisted(vaultId, seller, isAbandoned ? "Vault abandoned/renounced" : "Vault completed");
        }
    }

    function registerVaultOwnership(uint256 vaultId, address newOwner) external {
        require(msg.sender == address(jVault), "Only JVault");
        require(newOwner != address(0), "Zero owner");
        address previousOwner = vaultOwners[vaultId];

        if (previousOwner != address(0) && previousOwner != newOwner) {
            _removeVaultFromUser(previousOwner, vaultId);
        }
        if (previousOwner != newOwner) {
            vaultOwners[vaultId] = newOwner;
            if (!_userOwnsVault(newOwner, vaultId)) {
                userVaults[newOwner].push(vaultId);
            }
            emit VaultOwnershipTransferred(vaultId, previousOwner, newOwner);
        }
    }

    // --- Ownership sync ---
    function batchSyncVaultOwnership(uint256[] calldata vaultIds) external onlyOwner {
        require(vaultIds.length <= maxBatchSize, "Batch too large");
        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];
            if (vaultId == 0) continue;
            try jVault.getVault(vaultId) returns (IJVault.Vault memory vault) {
                if (!vault.isComplete && !vault.isAbandoned && vault.buyer != address(0)) {
                    _syncVaultOwnership(vaultId, vault.buyer);
                }
            } catch { continue; }
        }
    }

    function syncVaultOwnership(uint256 startId, uint256 endId) external onlyOwner {
        require(startId <= endId, "Invalid range");
        require(endId.sub(startId) <= maxBatchSize, "Range too large");
        for (uint256 vaultId = startId; vaultId <= endId; vaultId++) {
            try jVault.getVault(vaultId) returns (IJVault.Vault memory vault) {
                if (!vault.isComplete && !vault.isAbandoned && vault.buyer != address(0)) {
                    _syncVaultOwnership(vaultId, vault.buyer);
                }
            } catch { continue; }
        }
    }

    function _syncVaultOwnership(uint256 vaultId, address newOwner) internal {
        address previousOwner = vaultOwners[vaultId];
        if (previousOwner != address(0) && previousOwner != newOwner) {
            _removeVaultFromUser(previousOwner, vaultId);
        }
        if (previousOwner != newOwner) {
            vaultOwners[vaultId] = newOwner;
            if (!_userOwnsVault(newOwner, vaultId)) {
                userVaults[newOwner].push(vaultId);
            }
            emit VaultOwnershipTransferred(vaultId, previousOwner, newOwner);
            emit VaultOwnershipSynced(vaultId, newOwner);
        }
    }

    // --- Trading ---
    function listVaultForSale(uint256 vaultId, uint256 askingPrice)
        external
        nonReentrant
        validVaultForTrading(vaultId)
        onlyVaultOwner(vaultId)
        whenNotPaused
    {
        require(askingPrice > 0, "Price = 0");
        require(!vaultListings[vaultId].isActive, "Already listed");

        vaultListings[vaultId] = VaultListing({
            vaultId: vaultId,
            seller: msg.sender,
            askingPrice: askingPrice,
            listedAt: block.timestamp,
            isActive: true
        });

        activeListingIndex[vaultId] = activeListingIds.length;
        activeListingIds.push(vaultId);

        emit VaultListedForSale(vaultId, msg.sender, askingPrice);
    }

    function cancelVaultListing(uint256 vaultId) external onlyVaultOwner(vaultId) whenNotPaused {
        require(vaultListings[vaultId].isActive, "Not listed");
        vaultListings[vaultId].isActive = false;
        _removeActiveListing(vaultId);
        emit VaultSaleCancelled(vaultId, msg.sender);
    }

    function buyVault(uint256 vaultId)
        external
        payable
        nonReentrant
        validVaultForTrading(vaultId)
        whenNotPaused
    {
        VaultListing storage listing = vaultListings[vaultId];
        require(listing.isActive, "Not for sale");
        require(msg.value >= listing.askingPrice, "Insufficient payment");
        require(msg.sender != listing.seller, "Self purchase");

        uint256 tradingFee = listing.askingPrice.mul(tradingFeeBps).div(BASIS_POINTS);
        uint256 sellerPayment = listing.askingPrice.sub(tradingFee);
        uint256 refundAmount = msg.value > listing.askingPrice ? msg.value.sub(listing.askingPrice) : 0;

        address previousOwner = listing.seller;

        vaultOwners[vaultId] = msg.sender;
        _removeVaultFromUser(previousOwner, vaultId);
        if (!_userOwnsVault(msg.sender, vaultId)) {
            userVaults[msg.sender].push(vaultId);
        }
        listing.isActive = false;
        _removeActiveListing(vaultId);

        vaultSales.push(VaultSale({
            vaultId: vaultId,
            seller: previousOwner,
            buyer: msg.sender,
            salePrice: listing.askingPrice,
            soldAt: block.timestamp,
            tradingFee: tradingFee
        }));
        totalTradingFees = totalTradingFees.add(tradingFee);

        jVault.transferVaultFromMarket(vaultId, msg.sender);

        _sendValue(payable(previousOwner), sellerPayment);
        if (refundAmount > 0) {
            _sendValue(payable(msg.sender), refundAmount);
        }

        try jVault.awardXPFromMarkets(msg.sender, xpBuyVault, "Buy Vault") {} catch {}
        emit VaultSold(vaultId, previousOwner, msg.sender, listing.askingPrice, tradingFee);
        emit VaultOwnershipTransferred(vaultId, previousOwner, msg.sender);
    }

    function updateVaultPrice(uint256 vaultId, uint256 newPrice) external onlyVaultOwner(vaultId) whenNotPaused {
        require(vaultListings[vaultId].isActive, "Not listed");
        require(newPrice > 0, "Price = 0");
        vaultListings[vaultId].askingPrice = newPrice;
        emit VaultPriceUpdated(vaultId, newPrice);
    }

    function removeExpiredListings(uint256[] calldata vaultIds) external {
        require(vaultIds.length <= maxBatchSize, "Batch too large");
        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];
            if (!vaultListings[vaultId].isActive) continue;
            try jVault.getVault(vaultId) returns (IJVault.Vault memory vault) {
                bool shouldRemove = (block.timestamp > vault.deadline && !vault.isComplete && !vault.isAbandoned)
                    || vault.isAbandoned
                    || vault.isComplete;
                if (shouldRemove) {
                    vaultListings[vaultId].isActive = false;
                    _removeActiveListing(vaultId);
                    emit VaultSaleCancelled(vaultId, vaultListings[vaultId].seller);
                }
            } catch { continue; }
        }
    }

    function removeLiquidationEligibleListings(uint256[] calldata vaultIds) external {
        require(vaultIds.length <= maxBatchSize, "Batch too large");
        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];
            if (!vaultListings[vaultId].isActive) continue;
            try jVault.isVaultLiquidationEligible(vaultId) returns (bool isEligible, uint256) {
                if (isEligible) {
                    vaultListings[vaultId].isActive = false;
                    _removeActiveListing(vaultId);
                    emit VaultSaleCancelled(vaultId, vaultListings[vaultId].seller);
                }
            } catch { continue; }
        }
    }

    // --- Views ---
    function getUserVaults(address user) external view returns (uint256[] memory) {
        return userVaults[user];
    }

    function getVaultListing(uint256 vaultId) external view returns (VaultListing memory) {
        return vaultListings[vaultId];
    }

    function getVaultSalesHistory() external view returns (VaultSale[] memory) {
        return vaultSales;
    }

    function getVaultSale(uint256 index) external view returns (VaultSale memory) {
        require(index < vaultSales.length, "Bad index");
        return vaultSales[index];
    }

    function getTotalSales() external view returns (uint256) {
        return vaultSales.length;
    }

    function getVaultOwner(uint256 vaultId) external view returns (address) {
        return vaultOwners[vaultId];
    }

    function getActiveListings(uint256 limit, uint256 offset) external view returns (VaultListing[] memory) {
        uint256 totalActive = activeListingIds.length;
        if (offset >= totalActive) return new VaultListing[](0);

        uint256 end = offset + limit;
        if (end > totalActive) end = totalActive;
        uint256 resultCount = end - offset;

        VaultListing[] memory results = new VaultListing[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 vaultId = activeListingIds[offset + i];
            results[i] = vaultListings[vaultId];
        }
        return results;
    }

    function calculatePotentialProfit(uint256 vaultId, uint256 askingPrice) external view returns (uint256) {
        IJVault.Vault memory vault = jVault.getVault(vaultId);
        require(askingPrice > vault.totalDeposited, "No profit");
        uint256 tradingFee = askingPrice.mul(tradingFeeBps).div(BASIS_POINTS);
        return askingPrice.sub(vault.totalDeposited).sub(tradingFee);
    }

    // --- Internals ---
    function _userOwnsVault(address user, uint256 vaultId) internal view returns (bool) {
        uint256[] storage list = userVaults[user];
        for (uint256 i = 0; i < list.length; i++)
            if (list[i] == vaultId) return true;
        return false;
    }

    function _removeVaultFromUser(address user, uint256 vaultId) internal {
        if (user == address(0)) return;
        uint256[] storage list = userVaults[user];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == vaultId) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }

    function _removeActiveListing(uint256 vaultId) internal {
        uint256 total = activeListingIds.length;
        if (total == 0) return;
        uint256 index = activeListingIndex[vaultId];
        require(index < total, "Idx OOB");
        uint256 lastId = activeListingIds[total - 1];
        activeListingIds[index] = lastId;
        activeListingIndex[lastId] = index;
        activeListingIds.pop();
        delete activeListingIndex[vaultId];
    }

    function _sendValue(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH send failed");
    }

    // --- Owner withdrawals ---
    function withdrawTradingFees() external onlyOwner nonReentrant {
        uint256 amount = totalTradingFees;
        require(amount > 0, "No fees");
        totalTradingFees = 0;
        _sendValue(payable(owner()), amount);
        emit TradingFeesWithdrawn(owner(), amount);
    }

    function emergencyWithdraw() external onlyOwner nonReentrant {
        _sendValue(payable(owner()), address(this).balance);
    }

    receive() external payable {}
    fallback() external payable {}
}
