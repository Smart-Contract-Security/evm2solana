// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/openzeppelin/token/ERC721/IERC721.sol";
import "./lib/openzeppelin/token/ERC721/IERC721Receiver.sol";
import "./lib/openzeppelin/security/ReentrancyGuard.sol";
import "./lib/openzeppelin/security/Pausable.sol";
import "./lib/openzeppelin/access/Ownable.sol";
import "./lib/openzeppelin/utils/math/SafeMath.sol";

interface IJMarketsV2 {
    function registerVaultOwnership(uint256 vaultId, address owner) external;
    function notifyVaultStatusChange(uint256 vaultId, bool isAbandoned, bool isComplete) external;
}

interface IRevenueDistributor {
    function distribute() external payable;
}

/// @title JVaultV3
/// @notice Mode A self-funded BNPL escrow (APE native). Functionally identical to
///         JVaultV2 EXCEPT every fee/threshold/timing parameter is admin-settable
///         (was `public constant` in V2). All setters are bounded by max caps to
///         prevent admin abuse. JVaultV3_JMY is the ERC20-JMY parallel twin.
contract JVaultV3 is IERC721Receiver, ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;

    // ===== Math invariant (NOT a fee — stays constant) =====
    uint256 public constant BASIS_POINTS = 10000;

    // ===== Admin-bounded caps (immutable invariants on the setters) =====
    uint256 public constant MAX_PLATFORM_FEE_BPS         = 2000;  // 20%
    uint256 public constant MAX_PENALTY_BPS              = 5000;  // 50%
    uint256 public constant MAX_APR_BPS                  = 5000;  // 50%
    uint256 public constant MIN_LIQUIDATION_PERIOD       = 1 days;
    uint256 public constant MAX_LIQUIDATION_PERIOD       = 90 days;

    // ===== Variable fees / thresholds (admin-settable) =====
    uint256 public vaultInitiationFee;
    uint256 public depositPlatformFee;
    uint256 public platformFeeBps;
    uint256 public abandonmentPenaltyBps;
    uint256 public sellerPenaltyShareBps;
    uint256 public platformAprBps;
    uint256 public renouncePenaltyBps;
    uint256 public renounceSellerShareBps;
    uint256 public tradabilityThresholdBps;
    uint256 public expiredPenaltyBps;
    uint256 public liquidationPeriod;
    uint256 public liquidationWarningPeriod;
    uint256 public xpDepositPerEther;
    uint256 public xpCompleteVault;

    IJMarketsV2 public jMarkets;
    IRevenueDistributor public revenueDistributor;

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

    struct NFTListing {
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 listingPrice;
        bool isActive;
        bool hasActiveVault;
        uint256 activeVaultId;
    }

    mapping(uint256 => Vault) public vaults;
    mapping(bytes32 => NFTListing) public nftListings;
    mapping(address => mapping(uint256 => bool)) public nftInVault;
    mapping(address => uint256) public userXP;
    mapping(address => bool) public isAdmin;

    uint256 public nextVaultId = 1;

    // ===== Events =====
    event NFTListed(address indexed nftContract, uint256 indexed tokenId, address indexed seller, uint256 listingPrice);
    event NFTDelisted(address indexed nftContract, uint256 indexed tokenId, address indexed seller);
    event VaultCreated(uint256 indexed vaultId, address indexed buyer, address indexed nftContract, uint256 tokenId, uint256 commitmentAmount, uint256 deadline);
    event VaultDeposit(uint256 indexed vaultId, address indexed depositor, uint256 amount, uint256 totalDeposited);
    event VaultCompleted(uint256 indexed vaultId, address indexed buyer, uint256 totalPaid, uint256 cashBack);
    event VaultAbandoned(uint256 indexed vaultId, address indexed buyer, uint256 penaltyAmount, uint256 refundAmount);
    event VaultTransferabilityEnabled(uint256 indexed vaultId);
    event VaultTransferred(uint256 indexed vaultId, address indexed from, address indexed to);
    event VaultLiquidationWarning(uint256 indexed vaultId, address indexed buyer, uint256 requiredAmount);
    event XPEarned(address indexed user, uint256 amount, string reason);
    event VaultRenounced(uint256 indexed vaultId, address indexed buyer, uint256 penaltyAmount, uint256 refundAmount);

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event EmergencyRecallNFT(uint256 indexed vaultId, address indexed to);
    event EmergencyWithdrawVaultFunds(uint256 indexed vaultId, address indexed to, uint256 amount);
    event EmergencySweepNative(address indexed to, uint256 amount);
    event RevenueDistributorSet(address indexed revenueDistributor);
    event JMarketsSet(address indexed jMarkets);
    event FeeRouted(uint256 indexed vaultId, uint256 amount);

    // Fee setter events (one per parameter for indexer clarity)
    event VaultInitiationFeeSet(uint256 oldValue, uint256 newValue);
    event DepositPlatformFeeSet(uint256 oldValue, uint256 newValue);
    event PlatformFeeBpsSet(uint256 oldValue, uint256 newValue);
    event AbandonmentPenaltyBpsSet(uint256 oldValue, uint256 newValue);
    event SellerPenaltyShareBpsSet(uint256 oldValue, uint256 newValue);
    event PlatformAprBpsSet(uint256 oldValue, uint256 newValue);
    event RenouncePenaltyBpsSet(uint256 oldValue, uint256 newValue);
    event RenounceSellerShareBpsSet(uint256 oldValue, uint256 newValue);
    event TradabilityThresholdBpsSet(uint256 oldValue, uint256 newValue);
    event ExpiredPenaltyBpsSet(uint256 oldValue, uint256 newValue);
    event LiquidationPeriodSet(uint256 oldValue, uint256 newValue);
    event LiquidationWarningPeriodSet(uint256 oldValue, uint256 newValue);
    event XpDepositPerEtherSet(uint256 oldValue, uint256 newValue);
    event XpCompleteVaultSet(uint256 oldValue, uint256 newValue);

    // ===== Modifiers =====
    modifier validVault(uint256 vaultId) {
        require(vaultId > 0 && vaultId < nextVaultId, "Invalid vault ID");
        require(!vaults[vaultId].isComplete, "Vault completed");
        require(!vaults[vaultId].isAbandoned, "Vault abandoned");
        _;
    }

    modifier onlyVaultOwner(uint256 vaultId) {
        require(vaults[vaultId].buyer == msg.sender, "Not vault owner");
        _;
    }

    modifier onlyMarkets() {
        require(msg.sender == address(jMarkets), "Only JMarkets");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == owner() || isAdmin[msg.sender], "Not admin/owner");
        _;
    }

    constructor(address _revenueDistributor, address initialOwner) Ownable() {
        require(_revenueDistributor != address(0), "Zero RD");
        revenueDistributor = IRevenueDistributor(_revenueDistributor);

        // Defaults match deployed V2 economics
        vaultInitiationFee       = 1 ether;
        depositPlatformFee       = 10 ether;
        platformFeeBps           = 400;   // 4%
        abandonmentPenaltyBps    = 1000;  // 10%
        sellerPenaltyShareBps    = 500;   // 5% (of abandonment penalty)
        platformAprBps           = 400;   // 4% APR
        renouncePenaltyBps       = 1000;  // 10%
        renounceSellerShareBps   = 5000;  // 50% of penalty to seller
        tradabilityThresholdBps  = 3500;  // 35%
        expiredPenaltyBps        = 500;   // 5%
        liquidationPeriod        = 7 days;
        liquidationWarningPeriod = 6 days;
        xpDepositPerEther        = 1;
        xpCompleteVault          = 1000;

        if (initialOwner != address(0) && initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
    }

    // ===== Owner / Admin =====
    function setJMarkets(address jMarketsAddress) external onlyOwner {
        jMarkets = IJMarketsV2(jMarketsAddress);
        emit JMarketsSet(jMarketsAddress);
    }

    function setRevenueDistributor(address rd) external onlyOwner {
        require(rd != address(0), "Zero RD");
        revenueDistributor = IRevenueDistributor(rd);
        emit RevenueDistributorSet(rd);
    }

    function addAdmins(address[] calldata admins) external onlyOwner {
        for (uint256 i = 0; i < admins.length; i++) {
            require(admins[i] != address(0), "Zero admin");
            isAdmin[admins[i]] = true;
            emit AdminAdded(admins[i]);
        }
    }

    function removeAdmins(address[] calldata admins) external onlyOwner {
        for (uint256 i = 0; i < admins.length; i++) {
            isAdmin[admins[i]] = false;
            emit AdminRemoved(admins[i]);
        }
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ===== Fee setters (all onlyOwner, all bounded) =====
    function setVaultInitiationFee(uint256 v) external onlyOwner {
        emit VaultInitiationFeeSet(vaultInitiationFee, v);
        vaultInitiationFee = v;
    }

    function setDepositPlatformFee(uint256 v) external onlyOwner {
        emit DepositPlatformFeeSet(depositPlatformFee, v);
        depositPlatformFee = v;
    }

    function setPlatformFeeBps(uint256 v) external onlyOwner {
        require(v <= MAX_PLATFORM_FEE_BPS, "fee > cap");
        emit PlatformFeeBpsSet(platformFeeBps, v);
        platformFeeBps = v;
    }

    function setAbandonmentPenaltyBps(uint256 v) external onlyOwner {
        require(v <= MAX_PENALTY_BPS, "penalty > cap");
        emit AbandonmentPenaltyBpsSet(abandonmentPenaltyBps, v);
        abandonmentPenaltyBps = v;
    }

    function setSellerPenaltyShareBps(uint256 v) external onlyOwner {
        require(v <= BASIS_POINTS, "share > 100%");
        emit SellerPenaltyShareBpsSet(sellerPenaltyShareBps, v);
        sellerPenaltyShareBps = v;
    }

    function setPlatformAprBps(uint256 v) external onlyOwner {
        require(v <= MAX_APR_BPS, "apr > cap");
        emit PlatformAprBpsSet(platformAprBps, v);
        platformAprBps = v;
    }

    function setRenouncePenaltyBps(uint256 v) external onlyOwner {
        require(v <= MAX_PENALTY_BPS, "penalty > cap");
        emit RenouncePenaltyBpsSet(renouncePenaltyBps, v);
        renouncePenaltyBps = v;
    }

    function setRenounceSellerShareBps(uint256 v) external onlyOwner {
        require(v <= BASIS_POINTS, "share > 100%");
        emit RenounceSellerShareBpsSet(renounceSellerShareBps, v);
        renounceSellerShareBps = v;
    }

    function setTradabilityThresholdBps(uint256 v) external onlyOwner {
        require(v <= BASIS_POINTS, "threshold > 100%");
        emit TradabilityThresholdBpsSet(tradabilityThresholdBps, v);
        tradabilityThresholdBps = v;
    }

    function setExpiredPenaltyBps(uint256 v) external onlyOwner {
        require(v <= MAX_PENALTY_BPS, "penalty > cap");
        emit ExpiredPenaltyBpsSet(expiredPenaltyBps, v);
        expiredPenaltyBps = v;
    }

    function setLiquidationPeriod(uint256 v) external onlyOwner {
        require(v >= MIN_LIQUIDATION_PERIOD && v <= MAX_LIQUIDATION_PERIOD, "period oob");
        require(v >= liquidationWarningPeriod, "period < warn");
        emit LiquidationPeriodSet(liquidationPeriod, v);
        liquidationPeriod = v;
    }

    function setLiquidationWarningPeriod(uint256 v) external onlyOwner {
        require(v <= liquidationPeriod, "warn > period");
        emit LiquidationWarningPeriodSet(liquidationWarningPeriod, v);
        liquidationWarningPeriod = v;
    }

    function setXpDepositPerEther(uint256 v) external onlyOwner {
        emit XpDepositPerEtherSet(xpDepositPerEther, v);
        xpDepositPerEther = v;
    }

    function setXpCompleteVault(uint256 v) external onlyOwner {
        emit XpCompleteVaultSet(xpCompleteVault, v);
        xpCompleteVault = v;
    }

    // ===== Internal helpers =====
    function _sendValue(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Native send failed");
    }

    /// @dev Single batched route to RevenueDistributor for all fees collected in one tx.
    function _routeFee(uint256 vaultId, uint256 amount) internal {
        if (amount == 0) return;
        revenueDistributor.distribute{value: amount}();
        emit FeeRouted(vaultId, amount);
    }

    // ===== Listings =====
    function listNFT(address nftContract, uint256 tokenId, uint256 listingPrice)
        external
        nonReentrant
        whenNotPaused
    {
        require(listingPrice > 0, "Listing price = 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Not approved"
        );

        bytes32 nftKey = keccak256(abi.encodePacked(nftContract, tokenId));
        require(!nftListings[nftKey].isActive, "Already listed");

        nftListings[nftKey] = NFTListing({
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            listingPrice: listingPrice,
            isActive: true,
            hasActiveVault: false,
            activeVaultId: 0
        });

        uint256 listingXP = listingPrice.div(1 ether);
        if (listingXP > 0) {
            userXP[msg.sender] = userXP[msg.sender].add(listingXP);
            emit XPEarned(msg.sender, listingXP, "List NFT");
        }

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        emit NFTListed(nftContract, tokenId, msg.sender, listingPrice);
    }

    function delistNFT(address nftContract, uint256 tokenId) external nonReentrant {
        bytes32 nftKey = keccak256(abi.encodePacked(nftContract, tokenId));
        NFTListing storage listing = nftListings[nftKey];
        require(listing.isActive, "Not listed");
        require(!listing.hasActiveVault, "Active vault exists");
        require(listing.seller == msg.sender, "Not seller");

        delete nftListings[nftKey];
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
        emit NFTDelisted(nftContract, tokenId, msg.sender);
    }

    // ===== Vaults =====
    function _minCommitment(uint256 listingPrice, uint256 durationSecs) internal view returns (uint256) {
        if (durationSecs == 0) return listingPrice;
        uint256 aprFee = listingPrice * platformAprBps * durationSecs / BASIS_POINTS / 365 days;
        return listingPrice + aprFee;
    }

    function calculateMinCommitment(uint256 listingPrice, uint256 durationSecs) external view returns (uint256) {
        return _minCommitment(listingPrice, durationSecs);
    }

    function createVault(
        address nftContract,
        uint256 tokenId,
        uint256 commitmentAmount,
        uint256 duration
    ) external payable nonReentrant whenNotPaused {
        require(msg.value >= vaultInitiationFee, "initiation fee unmet");

        bytes32 nftKey = keccak256(abi.encodePacked(nftContract, tokenId));
        NFTListing storage listing = nftListings[nftKey];

        require(listing.isActive, "NFT not listed");
        require(!listing.hasActiveVault, "Has active vault");
        require(duration > 0, "Duration = 0");

        uint256 minCommit = _minCommitment(listing.listingPrice, duration);
        require(commitmentAmount >= minCommit, "Commitment < min");

        uint256 vaultId = nextVaultId++;
        uint256 vaultDeadline = block.timestamp + duration;
        uint256 initialDeposit = msg.value.sub(vaultInitiationFee);
        uint256 feesThisTx = vaultInitiationFee;

        if (initialDeposit > 0) {
            require(initialDeposit > depositPlatformFee, "Deposit <= platform fee");
            feesThisTx = feesThisTx.add(depositPlatformFee);
            initialDeposit = initialDeposit.sub(depositPlatformFee);
        }

        uint256 tradabilityThreshold = listing.listingPrice.mul(tradabilityThresholdBps).div(BASIS_POINTS);
        bool isInitiallyTransferable = initialDeposit >= tradabilityThreshold;

        vaults[vaultId] = Vault({
            vaultId: vaultId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: listing.seller,
            buyer: msg.sender,
            listingPrice: listing.listingPrice,
            commitmentAmount: commitmentAmount,
            totalDeposited: initialDeposit,
            createdAt: block.timestamp,
            lastDepositAt: block.timestamp,
            deadline: vaultDeadline,
            isComplete: false,
            isAbandoned: false,
            isTransferable: isInitiallyTransferable
        });

        listing.hasActiveVault = true;
        listing.activeVaultId = vaultId;
        nftInVault[nftContract][tokenId] = true;

        if (msg.sender != listing.seller) {
            uint256 vaultXP = commitmentAmount.div(1 ether);
            if (vaultXP > 0) {
                userXP[msg.sender] = userXP[msg.sender].add(vaultXP);
                emit XPEarned(msg.sender, vaultXP, "Create Vault");
            }
        }

        if (address(jMarkets) != address(0)) {
            jMarkets.registerVaultOwnership(vaultId, msg.sender);
        }

        emit VaultCreated(vaultId, msg.sender, nftContract, tokenId, commitmentAmount, vaultDeadline);

        if (initialDeposit > 0) {
            emit VaultDeposit(vaultId, msg.sender, initialDeposit, initialDeposit);
            if (isInitiallyTransferable) emit VaultTransferabilityEnabled(vaultId);
        }

        _routeFee(vaultId, feesThisTx);
    }

    function deposit(uint256 vaultId)
        external
        payable
        validVault(vaultId)
        onlyVaultOwner(vaultId)
        nonReentrant
        whenNotPaused
    {
        require(msg.value > 0, "Deposit = 0");
        require(block.timestamp <= vaults[vaultId].deadline, "Expired");
        require(msg.value > depositPlatformFee, "Deposit <= platform fee");

        Vault storage vault = vaults[vaultId];
        uint256 netAmount = msg.value.sub(depositPlatformFee);

        vault.totalDeposited = vault.totalDeposited.add(netAmount);
        vault.lastDepositAt = block.timestamp;

        if (!vault.isTransferable) {
            uint256 tradabilityThreshold = vault.listingPrice.mul(tradabilityThresholdBps).div(BASIS_POINTS);
            if (vault.totalDeposited >= tradabilityThreshold) {
                vault.isTransferable = true;
                emit VaultTransferabilityEnabled(vaultId);
            }
        }

        uint256 depositXP = netAmount.mul(xpDepositPerEther).div(1 ether);
        if (depositXP > 0) {
            userXP[msg.sender] = userXP[msg.sender].add(depositXP);
            emit XPEarned(msg.sender, depositXP, "Deposit");
        }

        emit VaultDeposit(vaultId, msg.sender, netAmount, vault.totalDeposited);

        _routeFee(vaultId, depositPlatformFee);
    }

    function completeVault(uint256 vaultId)
        external
        validVault(vaultId)
        onlyVaultOwner(vaultId)
        nonReentrant
    {
        Vault storage vault = vaults[vaultId];
        require(vault.totalDeposited >= vault.commitmentAmount, "Commitment not reached");
        require(block.timestamp <= vault.deadline, "Expired");
        _completeVault(vaultId);
    }

    function _completeVault(uint256 vaultId) internal {
        Vault storage vault = vaults[vaultId];

        uint256 platformFee = vault.commitmentAmount.mul(platformFeeBps).div(BASIS_POINTS);
        uint256 sellerPayment = vault.listingPrice;
        uint256 totalRequired = sellerPayment.add(platformFee);
        require(vault.totalDeposited >= totalRequired, "Insufficient funds");

        uint256 buyerCashBack = vault.totalDeposited.sub(totalRequired);

        vault.isComplete = true;
        bytes32 nftKey = keccak256(abi.encodePacked(vault.nftContract, vault.tokenId));
        delete nftListings[nftKey];
        nftInVault[vault.nftContract][vault.tokenId] = false;
        userXP[vault.buyer] = userXP[vault.buyer].add(xpCompleteVault);

        IERC721(vault.nftContract).safeTransferFrom(address(this), vault.buyer, vault.tokenId);
        _sendValue(payable(vault.seller), sellerPayment);
        _sendValue(payable(vault.buyer), buyerCashBack);

        if (address(jMarkets) != address(0)) {
            try jMarkets.notifyVaultStatusChange(vaultId, false, true) {} catch {}
        }

        emit VaultCompleted(vaultId, vault.buyer, vault.totalDeposited, buyerCashBack);
        emit XPEarned(vault.buyer, xpCompleteVault, "Complete Vault");

        _routeFee(vaultId, platformFee);
    }

    function abandonVault(uint256 vaultId)
        external
        validVault(vaultId)
        onlyVaultOwner(vaultId)
        nonReentrant
    {
        _liquidateVault(vaultId);
    }

    function renounceVault(uint256 vaultId)
        external
        validVault(vaultId)
        onlyVaultOwner(vaultId)
        nonReentrant
    {
        Vault storage vault = vaults[vaultId];

        uint256 totalPenalty = vault.totalDeposited.mul(renouncePenaltyBps).div(BASIS_POINTS);
        uint256 sellerPenalty = vault.totalDeposited.mul(renouncePenaltyBps).mul(renounceSellerShareBps).div(BASIS_POINTS).div(BASIS_POINTS);
        uint256 platformPenalty = totalPenalty.sub(sellerPenalty);
        uint256 refundAmount = vault.totalDeposited.sub(totalPenalty);

        vault.isAbandoned = true;
        bytes32 nftKey = keccak256(abi.encodePacked(vault.nftContract, vault.tokenId));
        delete nftListings[nftKey];
        nftInVault[vault.nftContract][vault.tokenId] = false;

        // M-1: collateral return to seller uses transferFrom (not safe) so a seller
        // that cannot receive ERC721 cannot block the buyer's refund/exit.
        IERC721(vault.nftContract).transferFrom(address(this), vault.seller, vault.tokenId);
        _sendValue(payable(vault.seller), sellerPenalty);
        _sendValue(payable(vault.buyer), refundAmount);

        if (address(jMarkets) != address(0)) {
            try jMarkets.notifyVaultStatusChange(vaultId, true, false) {} catch {}
        }

        emit VaultRenounced(vaultId, vault.buyer, totalPenalty, refundAmount);

        _routeFee(vaultId, platformPenalty);
    }

    function liquidateUnprofitableVault(uint256 vaultId) external validVault(vaultId) nonReentrant {
        Vault storage vault = vaults[vaultId];
        uint256 sinceLastDeposit = block.timestamp.sub(vault.lastDepositAt);

        if (sinceLastDeposit >= liquidationWarningPeriod && sinceLastDeposit < liquidationPeriod) {
            emit VaultLiquidationWarning(vaultId, vault.buyer, 0);
            return;
        }

        require(sinceLastDeposit >= liquidationPeriod, "Too early");
        _liquidateVault(vaultId);
    }

    function adminRevokeInactive(uint256 vaultId)
        external
        nonReentrant
        onlyAdminOrOwner
    {
        Vault storage vault = vaults[vaultId];
        require(!vault.isComplete && !vault.isAbandoned, "Vault not active");
        require(block.timestamp >= vault.lastDepositAt + liquidationPeriod, "Too early");
        _liquidateVault(vaultId);
    }

    function _liquidateVault(uint256 vaultId) internal {
        Vault storage vault = vaults[vaultId];

        uint256 penaltyAmount = vault.totalDeposited.mul(abandonmentPenaltyBps).div(BASIS_POINTS);
        uint256 sellerShare = vault.totalDeposited.mul(abandonmentPenaltyBps).mul(sellerPenaltyShareBps).div(BASIS_POINTS).div(BASIS_POINTS);
        uint256 platformShare = penaltyAmount.sub(sellerShare);
        uint256 refundAmount = vault.totalDeposited.sub(penaltyAmount);

        vault.isAbandoned = true;
        bytes32 nftKey = keccak256(abi.encodePacked(vault.nftContract, vault.tokenId));
        delete nftListings[nftKey];
        nftInVault[vault.nftContract][vault.tokenId] = false;

        // M-1: collateral return to seller uses transferFrom (not safe) so a seller
        // that cannot receive ERC721 cannot block the buyer's refund/exit.
        IERC721(vault.nftContract).transferFrom(address(this), vault.seller, vault.tokenId);
        _sendValue(payable(vault.seller), sellerShare);
        _sendValue(payable(vault.buyer), refundAmount);

        if (address(jMarkets) != address(0)) {
            try jMarkets.notifyVaultStatusChange(vaultId, true, false) {} catch {}
        }

        emit VaultAbandoned(vaultId, vault.buyer, penaltyAmount, refundAmount);

        _routeFee(vaultId, platformShare);
    }

    function claimExpiredVault(uint256 vaultId) external validVault(vaultId) nonReentrant {
        Vault storage vault = vaults[vaultId];
        require(block.timestamp > vault.deadline, "Not expired");
        require(vault.totalDeposited < vault.commitmentAmount, "Still completable");

        if (vault.totalDeposited >= vault.listingPrice && msg.sender == vault.buyer) {
            uint256 platformFee = vault.listingPrice.mul(platformFeeBps).div(BASIS_POINTS);
            uint256 sellerPayment = vault.listingPrice;
            uint256 totalRequired = sellerPayment.add(platformFee);
            require(vault.totalDeposited >= totalRequired, "Insufficient funds");

            uint256 buyerCashBack = vault.totalDeposited.sub(totalRequired);

            vault.isComplete = true;
            bytes32 nftKey = keccak256(abi.encodePacked(vault.nftContract, vault.tokenId));
            delete nftListings[nftKey];
            nftInVault[vault.nftContract][vault.tokenId] = false;

            IERC721(vault.nftContract).safeTransferFrom(address(this), vault.buyer, vault.tokenId);
            _sendValue(payable(vault.seller), sellerPayment);
            _sendValue(payable(vault.buyer), buyerCashBack);

            if (address(jMarkets) != address(0)) {
                try jMarkets.notifyVaultStatusChange(vaultId, false, true) {} catch {}
            }

            emit VaultCompleted(vaultId, vault.buyer, vault.totalDeposited, buyerCashBack);

            _routeFee(vaultId, platformFee);
        } else {
            uint256 penaltyAmount = vault.totalDeposited.mul(expiredPenaltyBps).div(BASIS_POINTS);
            uint256 sellerShare = vault.totalDeposited.mul(expiredPenaltyBps).mul(sellerPenaltyShareBps).div(BASIS_POINTS).div(BASIS_POINTS);
            uint256 platformShare = penaltyAmount.sub(sellerShare);
            uint256 refundAmount = vault.totalDeposited.sub(penaltyAmount);

            vault.isAbandoned = true;
            bytes32 nftKey = keccak256(abi.encodePacked(vault.nftContract, vault.tokenId));
            delete nftListings[nftKey];
            nftInVault[vault.nftContract][vault.tokenId] = false;

            // M-1: collateral return to seller uses transferFrom (not safe) so a seller
        // that cannot receive ERC721 cannot block the buyer's refund/exit.
        IERC721(vault.nftContract).transferFrom(address(this), vault.seller, vault.tokenId);
            _sendValue(payable(vault.seller), sellerShare);
            _sendValue(payable(vault.buyer), refundAmount);

            if (address(jMarkets) != address(0)) {
                try jMarkets.notifyVaultStatusChange(vaultId, true, false) {} catch {}
            }

            emit VaultAbandoned(vaultId, vault.buyer, penaltyAmount, refundAmount);

            _routeFee(vaultId, platformShare);
        }
    }

    function transferVault(uint256 vaultId, address newBuyer)
        external
        validVault(vaultId)
        onlyVaultOwner(vaultId)
        nonReentrant
    {
        require(newBuyer != address(0), "Zero newBuyer");
        require(newBuyer != msg.sender, "Self transfer");
        require(vaults[vaultId].isTransferable, "Not transferable");

        Vault storage vault = vaults[vaultId];
        address oldBuyer = vault.buyer;

        vault.buyer = newBuyer;

        if (address(jMarkets) != address(0)) {
            jMarkets.registerVaultOwnership(vaultId, newBuyer);
        }

        emit VaultTransferred(vaultId, oldBuyer, newBuyer);
    }

    function transferVaultFromMarket(uint256 vaultId, address newBuyer)
        external
        validVault(vaultId)
        onlyMarkets
    {
        require(newBuyer != address(0), "Zero newBuyer");
        Vault storage vault = vaults[vaultId];
        require(vault.isTransferable, "Not transferable");

        address oldBuyer = vault.buyer;
        if (oldBuyer == newBuyer) return;

        vault.buyer = newBuyer;

        if (address(jMarkets) != address(0)) {
            jMarkets.registerVaultOwnership(vaultId, newBuyer);
        }

        emit VaultTransferred(vaultId, oldBuyer, newBuyer);
    }

    function awardXPFromMarkets(address user, uint256 amount, string calldata reason) external {
        require(msg.sender == address(jMarkets), "Only JMarkets");
        require(address(jMarkets) != address(0), "JMarkets not set");
        if (amount > 0) {
            userXP[user] = userXP[user].add(amount);
            emit XPEarned(user, amount, reason);
        }
    }

    // ===== Views =====
    function calculateRenounceCost(uint256 vaultId) external view returns (uint256 totalPenalty, uint256 sellerPenalty, uint256 platformPenalty, uint256 refundAmount) {
        require(vaultId > 0 && vaultId < nextVaultId, "Invalid vault ID");
        Vault storage vault = vaults[vaultId];
        require(!vault.isComplete && !vault.isAbandoned, "Vault not active");

        totalPenalty = vault.totalDeposited.mul(renouncePenaltyBps).div(BASIS_POINTS);
        sellerPenalty = vault.totalDeposited.mul(renouncePenaltyBps).mul(renounceSellerShareBps).div(BASIS_POINTS).div(BASIS_POINTS);
        platformPenalty = totalPenalty.sub(sellerPenalty);
        refundAmount = vault.totalDeposited.sub(totalPenalty);
    }

    function getInactivityCountdown(uint256 vaultId) external view returns (uint256 secondsRemaining) {
        require(vaultId > 0 && vaultId < nextVaultId, "Invalid vault ID");
        Vault storage v = vaults[vaultId];
        if (v.isComplete || v.isAbandoned) return 0;
        uint256 end = v.lastDepositAt + liquidationPeriod;
        if (block.timestamp >= end) return 0;
        return end - block.timestamp;
    }

    function getUserXP(address user) external view returns (uint256) { return userXP[user]; }
    function getVault(uint256 vaultId) external view returns (Vault memory) { return vaults[vaultId]; }
    function getNFTListing(address nftContract, uint256 tokenId) external view returns (NFTListing memory) {
        bytes32 nftKey = keccak256(abi.encodePacked(nftContract, tokenId));
        return nftListings[nftKey];
    }
    function isVaultTransferable(uint256 vaultId) external view returns (bool) { return vaults[vaultId].isTransferable; }

    function isVaultLiquidationEligible(uint256 vaultId) external view returns (bool, uint256) {
        Vault storage vault = vaults[vaultId];
        if (vault.isComplete || vault.isAbandoned) return (false, 0);
        if (block.timestamp >= vault.lastDepositAt + liquidationPeriod) {
            return (true, 0);
        }
        return (false, 0);
    }

    // ===== Emergency (multisig owner or admins). Must be paused. =====
    function emergencyRecallNFT(uint256 vaultId, address to)
        external
        nonReentrant
        whenPaused
        onlyAdminOrOwner
        validVault(vaultId)
    {
        require(to != address(0), "Zero to");
        Vault storage vault = vaults[vaultId];

        vault.isAbandoned = true;
        bytes32 nftKey = keccak256(abi.encodePacked(vault.nftContract, vault.tokenId));
        delete nftListings[nftKey];
        nftInVault[vault.nftContract][vault.tokenId] = false;

        // M-1: use transferFrom so a non-receiving destination can't block the rescue.
        IERC721(vault.nftContract).transferFrom(address(this), to, vault.tokenId);

        if (address(jMarkets) != address(0)) {
            try jMarkets.notifyVaultStatusChange(vaultId, true, false) {} catch {}
        }

        emit EmergencyRecallNFT(vaultId, to);
    }

    function emergencyWithdrawVaultFunds(uint256 vaultId, address to, uint256 amount)
        external
        nonReentrant
        whenPaused
        onlyAdminOrOwner
        validVault(vaultId)
    {
        require(to != address(0), "Zero to");
        Vault storage vault = vaults[vaultId];
        require(amount <= vault.totalDeposited, "Amount > deposited");

        vault.totalDeposited = vault.totalDeposited.sub(amount);
        _sendValue(payable(to), amount);

        emit EmergencyWithdrawVaultFunds(vaultId, to, amount);
    }

    function emergencySweepNative(address to, uint256 amount)
        external
        nonReentrant
        whenPaused
        onlyAdminOrOwner
    {
        require(to != address(0), "Zero to");
        _sendValue(payable(to), amount);
        emit EmergencySweepNative(to, amount);
    }

    // ===== ERC721 Receiver & Fallbacks =====
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
    fallback() external payable {}
}
