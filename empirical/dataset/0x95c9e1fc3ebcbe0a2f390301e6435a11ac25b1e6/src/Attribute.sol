// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
/*
  ____       ____              _
 |  _ \  ___|  _ \ _   _ _ __ | | _____
 | | | |/ _ \ |_) | | | | '_ \| |/ / __|
 | |_| |  __/  __/| |_| | | | |   <\__ \
 |____/ \___|_|    \__,_|_| |_|_|\_\___/

*/

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./LibPRNG.sol";
import "./interfaces/ICreatorToken.sol";
import "./interfaces/ITransferValidator.sol";
import "./interfaces/IVRFCoordinatorV2_5.sol";
import "./lib/AttributeFixedSaleLib.sol";
import "./lib/AttributePackMintLib.sol";

/// @dev Pending VRF mint request (2 slots)
struct MintRequest {
    address minter; // 20 bytes ─┐
    uint64 requestTime; //  8 bytes  │ slot 1 (28 bytes)
    uint32 numberOfTokens; //  4 bytes ─┘
    uint256 ticketId; // 32 bytes   slot 2
}

/// @dev Claimable mint data (stored when VRF callback delivery fails)
struct ClaimableMint {
    address minter;
    uint256[] ids;
    uint256[] amounts;
}

/// @dev Fixed-price sale configuration for token IDs outside the shuffled pool.
struct FixedSaleConfig {
    address artist;
    uint96 unitPrice;
    uint32 saleSupply;
    uint32 minted;
    uint64 saleStart;
    uint64 saleEnd;
    uint16 artistPoints;
    uint16 artistFreeClaimAllowance;
    uint16 treasuryFreeClaimAllowance;
    bool active;
    bool exists;
}

/// @dev Free allocations claimed for a fixed-sale token ID.
struct FixedSaleClaimed {
    uint16 artist;
    uint16 treasury;
}

/// @title DePunks Attribute NFTs
/// @notice ERC1155 upgradeable contract for DePunks attributes with Chainlink VRF v2.5 for verifiable random minting
contract Attribute is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ICreatorToken
{
    using Strings for uint256;
    using SafeERC20 for IERC20;

    address internal constant OPENSEA_CONDUIT = 0x1E0049783F008A0085193E00003D00cd54003c71;
    address internal constant OPENSEA_SEAPORT_1_6 = 0x0000000000000068F116a894984e2DB1123eB395;
    address internal constant OPENSEA_SEAPORT_1_1 = 0x00000000006c3852cbEf3e08E8dF289169EdE581;
    address internal constant OPENSEA_TRANSFER_HELPER = 0x0000000000c2d145a2526bD8C716263bFeBe1A72;

    string public name;
    string public symbol;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @notice Royalty fee percentage (5%)
    uint96 public constant ROYALTY_FEE = 500; // 5% in basis points

    /// @notice Base points for percentage calculations (10000 = 100%)
    uint16 public constant BASE_POINTS = 10000;

    /// @notice Default fixed-sale duration when no explicit end time is provided.
    uint64 public constant DEFAULT_FIXED_SALE_DURATION = 24 hours;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice LazyShuffler for fair random attribute distribution
    LibPRNG.LazyShuffler private shuffler;

    /// @notice Total number of attributes available for minting
    uint256 private totalAttributeSupply;

    /// @notice Cumulative supply upper-bounds used to map shuffled index to token ID
    uint256[] private cumulativeSupplies;

    /// @notice First wallet address for fee distribution
    address public feeWallet1;

    /// @notice Second wallet address for fee distribution
    address public feeWallet2;

    /// @notice Third wallet address for fee distribution (receives remainder)
    address public feeWallet3;

    /// @notice Base points for wallet1 (out of 10000)
    uint16 public wallet1Points;

    /// @notice Base points for wallet2 (out of 10000)
    uint16 public wallet2Points;

    /// @notice Address authorized to sign mint tickets
    address public signerAddress;

    /// @notice Mapping to track used ticket IDs to prevent replay attacks
    mapping(uint256 => bool) public usedTickets;

    /// @notice Address of the DePunk contract authorized to burn attributes for upgrading
    address public dePunkContract;

    /// @notice Mapping from tokenId to max supply for that attribute type
    mapping(uint256 => uint256) public maxSupplies;

    /// @notice Mapping from tokenId to remaining supply for that attribute type
    mapping(uint256 => uint256) public remainingSupplyPerToken;

    /// @notice Array to track all tokenIds that have been added
    uint256[] private addedTokenIds;

    /// @notice Timestamp after which contract operations are locked
    uint256 public lockTime;

    /// @notice Address of the transfer validator for royalty enforcement
    address private _transferValidator;

    /// @notice Default royalty receiver used by ERC2981; this is the DePunks Team recipient.
    address public royaltyReceiver;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event AttributeTypeAdded(uint256 indexed typeId, uint256 tokenCount);
    event AttributeMinted(address indexed to, uint256 indexed typeId, uint256 randomValue);
    event TicketUsed(uint256 indexed ticketId, address indexed minter, uint256 numberOfTokens, uint256 totalPrice);
    event LockTimeSet(uint256 lockTime);
    event AttributesBurnedAfterLock(
        uint256 indexed tokenId, address indexed previousOwner, address indexed burner, uint256 amount
    );
    event RoyaltyReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event VRFMintRequested(uint256 indexed requestId, address indexed minter, uint256 numberOfTokens, uint256 ticketId);
    event VRFMintFulfilled(uint256 indexed requestId, address indexed minter, uint256 numberOfTokens);
    event VRFTimedOut(uint256 indexed oldRequestId, uint256 indexed newRequestId, address indexed minter);
    event VRFMintCancelled(uint256 indexed requestId, address indexed minter, uint256 numberOfTokens);
    event VRFMintClaimable(uint256 indexed requestId, address indexed minter, uint256 numberOfTokens);
    event VRFMintClaimed(uint256 indexed requestId, address indexed minter, address indexed to, uint256 numberOfTokens);
    event FixedSaleTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FixedSaleTokenConfigured(
        uint256 indexed tokenId,
        address indexed artist,
        uint96 unitPrice,
        uint32 saleSupply,
        uint64 saleStart,
        uint64 saleEnd,
        uint16 artistPoints,
        uint16 artistFreeClaimAllowance,
        uint16 treasuryFreeClaimAllowance,
        bool active
    );
    event FixedSaleMinted(
        address indexed buyer,
        uint256 indexed tokenId,
        uint32 quantity,
        uint256 indexed eligibleDePunkTokenId,
        uint256 totalPrice,
        uint256 artistAmount,
        uint256 treasuryAmount
    );
    event FixedSaleAllocationClaimed(
        address indexed claimer, uint256 indexed tokenId, uint32 quantity, bool artistAllocation
    );

    // =============================================================
    //                           ERRORS
    // =============================================================

    error ExceedsMaxBatchSize();
    error InsufficientPayment();
    error InsufficientRemainingSupply();
    error TypeAlreadyExists();
    error InvalidTypeId();
    error InvalidFeeWallet();
    error ContractLocked();
    error InvalidLockTime();
    error InvalidPaymentDistribution();
    error InvalidTransferValidator();
    error TransferValidatorNotSet();
    error InvalidRoyaltyReceiver();
    error OnlyCoordinatorCanFulfill();
    error VRFNotTimedOut();
    error InvalidAttributeContract();
    error InvalidFixedSaleTreasury();
    error InvalidFixedSaleConfig();
    error FixedSaleInactive();
    error FixedSaleNotStarted();
    error FixedSaleEnded();
    error FixedSaleSoldOut();
    error InvalidFixedSaleSignature();
    error FixedSaleTicketExpired();
    error NotEligibleUpgradedHolder();
    error FixedSaleAllocationExceeded();
    error ExactPaymentRequired();
    error InvalidSignerAddress();
    error InvalidBaseURI();
    error ContractNotYetLocked();
    error OnlySelf();
    error NoClaimableMint();
    error NotAuthorized();
    error OnlyDePunkCanBurnForUpgrade();
    error BurnFromZeroAddress();
    error BurnAmountExceedsBalance();
    error MissingAttributeSupplies();
    error InvalidTokenCount();
    error TokenIdExceedsUint16Max();
    error InvalidCoordinator();
    error InvalidSubscription();
    error InvalidKeyHash();
    error InvalidGasLimit();
    error InvalidMaxTokens();
    error LockAlreadyExpired();
    error InvalidDePunkAddress();
    error FeeTransferFailed();
    error NoETHToWithdraw();
    error InvalidTokenAddress();
    error NoTokensToWithdraw();
    error InvalidTreasury();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the Attribute contract (replaces constructor for proxy pattern)
    function initialize(
        string memory _uri,
        address _feeWallet1,
        uint16 _wallet1Points,
        address _feeWallet2,
        uint16 _wallet2Points,
        address _feeWallet3,
        address _signerAddress,
        uint16[] memory attributeSupplies,
        address initialOwner
    ) external initializer {
        if (_feeWallet1 == address(0) || _feeWallet2 == address(0) || _feeWallet3 == address(0)) {
            revert InvalidFeeWallet();
        }
        if (_signerAddress == address(0)) revert InvalidSignerAddress();
        if (_wallet1Points + _wallet2Points > BASE_POINTS) {
            revert InvalidPaymentDistribution();
        }
        if (bytes(_uri).length > 0 && bytes(_uri)[bytes(_uri).length - 1] != bytes1("/")) {
            revert InvalidBaseURI();
        }

        __ERC1155_init(_uri);
        __ERC1155Burnable_init();
        __ERC2981_init();
        __Ownable_init(initialOwner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        name = "DePunks Attributes";
        symbol = "DEPNKATTR";

        feeWallet1 = _feeWallet1;
        feeWallet2 = _feeWallet2;
        feeWallet3 = _feeWallet3;
        signerAddress = _signerAddress;
        wallet1Points = _wallet1Points;
        wallet2Points = _wallet2Points;

        royaltyReceiver = address(this);
        _setDefaultRoyalty(royaltyReceiver, ROYALTY_FEE);
        treasury = _feeWallet1;

        _initializeAttributeInventory(attributeSupplies);
    }

    // =============================================================
    //                           MODIFIERS
    // =============================================================

    /// @notice Modifier to ensure operations happen before lock time
    modifier beforeLock() {
        if (lockTime != 0 && block.timestamp >= lockTime) {
            revert ContractLocked();
        }
        _;
    }

    /// @notice Modifier to ensure operations happen after lock time
    modifier afterLock() {
        if (lockTime == 0 || block.timestamp < lockTime) {
            revert ContractNotYetLocked();
        }
        _;
    }

    // =============================================================
    //                        MINTING LOGIC
    // =============================================================

    /// @notice Mint attribute tokens with signature verification (Phase 1: request VRF randomness)
    /// @dev Tokens are minted asynchronously in rawFulfillRandomWords callback
    function mintTokensWithSignature(
        uint256 numberOfTokens,
        uint256 ticketId,
        uint256 totalPrice,
        bytes calldata signature
    ) external payable whenNotPaused beforeLock nonReentrant {
        uint256 shufflerSlot;
        uint256 pendingReservedTokensSlot;
        uint256 usedTicketsSlot;
        uint256 pendingMintRequestsSlot;
        assembly {
            shufflerSlot := shuffler.slot
            pendingReservedTokensSlot := pendingReservedTokens.slot
            usedTicketsSlot := usedTickets.slot
            pendingMintRequestsSlot := pendingMintRequests.slot
        }
        AttributePackMintLib.requestMint(
            AttributePackMintLib.RequestSlots({
                shufflerSlot: shufflerSlot,
                pendingReservedTokensSlot: pendingReservedTokensSlot,
                usedTicketsSlot: usedTicketsSlot,
                pendingMintRequestsSlot: pendingMintRequestsSlot
            }),
            AttributePackMintLib.RequestConfig({
                totalAttributeSupply: totalAttributeSupply,
                signerAddress: signerAddress,
                maxTokensPerMint: maxTokensPerMint,
                vrfCoordinator: vrfCoordinator,
                vrfSubscriptionId: vrfSubscriptionId,
                vrfKeyHash: vrfKeyHash,
                vrfCallbackGasLimit: vrfCallbackGasLimit,
                vrfRequestConfirmations: vrfRequestConfirmations,
                team: royaltyReceiver
            }),
            AttributePackMintLib.RequestInput({
                numberOfTokens: numberOfTokens, ticketId: ticketId, totalPrice: totalPrice
            }),
            signature
        );
    }

    /// @notice VRF callback — called by Chainlink coordinator with verified randomness (Phase 2: mint tokens)
    /// @dev Tries direct delivery; on receiver revert, stores tokens for pull-based claiming
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        if (msg.sender != vrfCoordinator) revert OnlyCoordinatorCanFulfill();

        MintRequest memory req = pendingMintRequests[requestId];
        if (req.minter == address(0)) return; // stale/unknown — silent no-op

        // CEI: delete before side effects
        delete pendingMintRequests[requestId];
        pendingReservedTokens -= req.numberOfTokens;

        uint256 n = req.numberOfTokens;
        uint256 shufflerSlot;
        uint256 cumulativeSuppliesSlot;
        uint256 addedTokenIdsSlot;
        uint256 remainingSupplyPerTokenSlot;
        assembly {
            shufflerSlot := shuffler.slot
            cumulativeSuppliesSlot := cumulativeSupplies.slot
            addedTokenIdsSlot := addedTokenIds.slot
            remainingSupplyPerTokenSlot := remainingSupplyPerToken.slot
        }
        (uint256[] memory ids, uint256[] memory amounts) = AttributePackMintLib.drawMint(
            shufflerSlot,
            cumulativeSuppliesSlot,
            addedTokenIdsSlot,
            remainingSupplyPerTokenSlot,
            req.minter,
            n,
            randomWords[0]
        );

        // Try direct delivery; fall back to claimable on receiver revert
        try this.deliverMint(req.minter, ids, amounts) {
            emit VRFMintFulfilled(requestId, req.minter, n);
        } catch {
            _storeClaimable(requestId, req.minter, ids, amounts);
            emit VRFMintClaimable(requestId, req.minter, n);
        }
    }

    /// @notice Deliver minted tokens — only callable by this contract via try/catch in VRF callback
    function deliverMint(address to, uint256[] calldata ids, uint256[] calldata amounts) external {
        if (msg.sender != address(this)) revert OnlySelf();
        _mintBatch(to, ids, amounts, "");
    }

    /// @notice Claim tokens that failed direct delivery (e.g. contract wallet receiver revert)
    /// @param requestId The VRF request ID
    /// @param to Recipient address (use address(0) to send to original minter)
    function claimMint(uint256 requestId, address to) external nonReentrant {
        ClaimableMint storage claim = claimableMints[requestId];
        if (claim.minter == address(0)) revert NoClaimableMint();
        if (msg.sender != claim.minter && msg.sender != owner()) revert NotAuthorized();

        address recipient = to == address(0) ? claim.minter : to;

        // Copy to memory before deleting
        uint256[] memory ids = claim.ids;
        uint256[] memory amounts = claim.amounts;
        address minter = claim.minter;
        uint256 numTokens = ids.length;

        delete claimableMints[requestId];

        _mintBatch(recipient, ids, amounts, "");

        emit VRFMintClaimed(requestId, minter, recipient, numTokens);
    }

    function _storeClaimable(uint256 requestId, address minter, uint256[] memory ids, uint256[] memory amounts)
        private
    {
        ClaimableMint storage claim = claimableMints[requestId];
        claim.minter = minter;
        for (uint256 i = 0; i < ids.length;) {
            claim.ids.push(ids[i]);
            claim.amounts.push(amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    // =============================================================
    //                    FIXED-PRICE SALE LOGIC
    // =============================================================

    function mintFixedSaleToken(
        uint256 tokenId,
        uint32 quantity,
        uint256 eligibleDePunkTokenId,
        uint256 ticketId,
        uint256 totalPrice,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused beforeLock nonReentrant {
        uint256 fixedSaleConfigsSlot;
        uint256 usedTicketsSlot;
        assembly {
            fixedSaleConfigsSlot := fixedSaleConfigs.slot
            usedTicketsSlot := usedTickets.slot
        }
        AttributeFixedSaleLib.mintFixedSaleToken(
            fixedSaleConfigsSlot,
            usedTicketsSlot,
            dePunkContract,
            signerAddress,
            treasury,
            tokenId,
            quantity,
            eligibleDePunkTokenId,
            ticketId,
            totalPrice,
            deadline,
            signature
        );

        _mint(msg.sender, tokenId, quantity, "");
    }

    function claimFixedSaleAllocation(uint256 tokenId, uint32 quantity) external whenNotPaused beforeLock nonReentrant {
        uint256 fixedSaleConfigsSlot;
        uint256 fixedSaleClaimedSlot;
        assembly {
            fixedSaleConfigsSlot := fixedSaleConfigs.slot
            fixedSaleClaimedSlot := fixedSaleClaimed.slot
        }
        AttributeFixedSaleLib.claimFixedSaleAllocation(
            fixedSaleConfigsSlot, fixedSaleClaimedSlot, treasury, tokenId, quantity
        );
        _mint(msg.sender, tokenId, quantity, "");
    }

    /// @notice Admin recovery for timed-out VRF requests (re-requests VRF)
    function recoverFromVRFTimeout(uint256 oldRequestId) external onlyOwner {
        uint256 pendingMintRequestsSlot;
        assembly {
            pendingMintRequestsSlot := pendingMintRequests.slot
        }
        AttributePackMintLib.recoverFromVRFTimeout(
            pendingMintRequestsSlot,
            vrfCoordinator,
            vrfSubscriptionId,
            vrfKeyHash,
            vrfCallbackGasLimit,
            vrfRequestConfirmations,
            oldRequestId
        );
    }

    /// @notice Admin emergency cancel for permanently-failing VRF mints
    /// @dev Use when a contract wallet's onERC1155Received always reverts, making the callback unfulfillable.
    ///      Releases the reserved supply. Payment is NOT refunded (already distributed).
    function emergencyCancelMintRequest(uint256 requestId) external onlyOwner {
        uint256 pendingMintRequestsSlot;
        uint256 pendingReservedTokensSlot;
        assembly {
            pendingMintRequestsSlot := pendingMintRequests.slot
            pendingReservedTokensSlot := pendingReservedTokens.slot
        }
        AttributePackMintLib.emergencyCancelMintRequest(pendingMintRequestsSlot, pendingReservedTokensSlot, requestId);
    }

    /// @notice View pending mint request
    function getPendingMintRequest(uint256 requestId) external view returns (MintRequest memory) {
        return pendingMintRequests[requestId];
    }

    /// @notice View claimable mint data for a failed delivery
    function getClaimableMint(uint256 requestId)
        external
        view
        returns (address minter, uint256[] memory ids, uint256[] memory amounts)
    {
        ClaimableMint storage claim = claimableMints[requestId];
        return (claim.minter, claim.ids, claim.amounts);
    }

    // =============================================================
    //                      UPGRADE BURN LOGIC
    // =============================================================

    function burnForUpgrade(address from, uint256 id, uint256 amount) external whenNotPaused beforeLock {
        if (msg.sender != dePunkContract) revert OnlyDePunkCanBurnForUpgrade();
        if (from == address(0)) revert BurnFromZeroAddress();
        if (balanceOf(from, id) < amount) revert BurnAmountExceedsBalance();

        _burn(from, id, amount);
    }

    /// @notice Intentional public post-lock cleanup for leftover attribute supply.
    function burnRemaining(address from, uint256 id, uint256 amount) external afterLock {
        if (from == address(0)) revert BurnFromZeroAddress();
        if (balanceOf(from, id) < amount) revert BurnAmountExceedsBalance();

        _burn(from, id, amount);
        emit AttributesBurnedAfterLock(id, from, msg.sender, amount);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    function _initializeAttributeInventory(uint16[] memory attributeSupplies) internal {
        uint256 supplyCount = attributeSupplies.length;
        if (supplyCount == 0) revert MissingAttributeSupplies();

        for (uint256 i = 0; i < supplyCount;) {
            uint256 tokenId = i + 1;
            _addAttributeType(tokenId, attributeSupplies[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _addAttributeType(uint256 tokenId, uint256 tokenCount) internal {
        if (tokenCount == 0) revert InvalidTokenCount();
        if (maxSupplies[tokenId] > 0) {
            revert TypeAlreadyExists();
        }
        if (tokenId > type(uint16).max) revert TokenIdExceedsUint16Max();

        maxSupplies[tokenId] = tokenCount;
        remainingSupplyPerToken[tokenId] = tokenCount;
        addedTokenIds.push(tokenId);

        uint256 newTotalSupply = totalAttributeSupply + tokenCount;
        if (totalAttributeSupply == 0) {
            LibPRNG.initialize(shuffler, newTotalSupply);
        } else {
            LibPRNG.grow(shuffler, newTotalSupply);
        }
        cumulativeSupplies.push(newTotalSupply);
        totalAttributeSupply = newTotalSupply;

        emit AttributeTypeAdded(tokenId, tokenCount);
    }

    /// @notice Initialize VRF v2.5 configuration (called via upgradeToAndCall)
    function initializeVRF(
        address _vrfCoordinator,
        uint256 _vrfSubscriptionId,
        bytes32 _vrfKeyHash,
        uint32 _vrfCallbackGasLimit,
        uint16 _vrfRequestConfirmations,
        uint8 _maxTokensPerMint
    ) external reinitializer(2) {
        if (_vrfCoordinator == address(0)) revert InvalidCoordinator();
        if (_vrfSubscriptionId == 0) revert InvalidSubscription();
        if (_vrfKeyHash == bytes32(0)) revert InvalidKeyHash();
        if (_vrfCallbackGasLimit < 100_000 || _vrfCallbackGasLimit > 2_500_000) revert InvalidGasLimit();
        if (_maxTokensPerMint == 0) revert InvalidMaxTokens();

        vrfCoordinator = _vrfCoordinator;
        vrfSubscriptionId = _vrfSubscriptionId;
        vrfKeyHash = _vrfKeyHash;
        vrfCallbackGasLimit = _vrfCallbackGasLimit;
        vrfRequestConfirmations = _vrfRequestConfirmations;
        maxTokensPerMint = _maxTokensPerMint;
    }

    function setVRFCoordinator(address _vrfCoordinator) external onlyOwner {
        if (_vrfCoordinator == address(0)) revert InvalidCoordinator();
        vrfCoordinator = _vrfCoordinator;
    }

    function setVRFSubscription(uint256 _vrfSubscriptionId) external onlyOwner {
        if (_vrfSubscriptionId == 0) revert InvalidSubscription();
        vrfSubscriptionId = _vrfSubscriptionId;
    }

    function setVRFKeyHash(bytes32 _vrfKeyHash) external onlyOwner {
        if (_vrfKeyHash == bytes32(0)) revert InvalidKeyHash();
        vrfKeyHash = _vrfKeyHash;
    }

    function setVRFCallbackGasLimit(uint32 _vrfCallbackGasLimit) external onlyOwner {
        if (_vrfCallbackGasLimit < 100_000 || _vrfCallbackGasLimit > 2_500_000) revert InvalidGasLimit();
        vrfCallbackGasLimit = _vrfCallbackGasLimit;
    }

    function setMaxTokensPerMint(uint8 _maxTokensPerMint) external onlyOwner {
        if (_maxTokensPerMint == 0) revert InvalidMaxTokens();
        maxTokensPerMint = _maxTokensPerMint;
    }

    function setSignerAddress(address _signerAddress) external onlyOwner {
        if (_signerAddress == address(0)) revert InvalidSignerAddress();
        signerAddress = _signerAddress;
    }

    function setLockTime(uint256 _lockTime) external onlyOwner {
        if (lockTime != 0 && block.timestamp >= lockTime) {
            revert LockAlreadyExpired();
        }
        if (_lockTime <= block.timestamp) {
            revert InvalidLockTime();
        }
        lockTime = _lockTime;
        emit LockTimeSet(_lockTime);
    }

    function setDePunkContract(address _dePunkContract) external onlyOwner {
        if (_dePunkContract == address(0)) revert InvalidDePunkAddress();
        dePunkContract = _dePunkContract;
    }

    function setBaseURI(string memory newURI) external onlyOwner {
        if (bytes(newURI).length > 0 && bytes(newURI)[bytes(newURI).length - 1] != bytes1("/")) {
            revert InvalidBaseURI();
        }
        _setURI(newURI);
    }

    function setFixedSaleTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidFixedSaleTreasury();
        emit FixedSaleTreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function configureFixedSaleToken(
        uint256 tokenId,
        address artist,
        uint96 unitPrice,
        uint32 saleSupply,
        uint64 saleStart,
        uint64 saleEnd,
        uint16 artistPoints,
        uint16 artistFreeClaimAllowance,
        uint16 treasuryFreeClaimAllowance,
        bool active
    ) external onlyOwner {
        uint256 fixedSaleConfigsSlot;
        uint256 fixedSaleTokenIdsSlot;
        uint256 maxSuppliesSlot;
        uint256 fixedSaleClaimedSlot;
        assembly {
            fixedSaleConfigsSlot := fixedSaleConfigs.slot
            fixedSaleTokenIdsSlot := fixedSaleTokenIds.slot
            maxSuppliesSlot := maxSupplies.slot
            fixedSaleClaimedSlot := fixedSaleClaimed.slot
        }
        AttributeFixedSaleLib.configureFixedSaleToken(
            fixedSaleConfigsSlot,
            fixedSaleTokenIdsSlot,
            maxSuppliesSlot,
            fixedSaleClaimedSlot,
            tokenId,
            artist,
            unitPrice,
            saleSupply,
            saleStart,
            saleEnd,
            artistPoints,
            artistFreeClaimAllowance,
            treasuryFreeClaimAllowance,
            active
        );
    }

    function _distributePayment(uint256 totalAmount) internal {
        if (totalAmount == 0) return;
        if (treasury == address(0)) revert InvalidTreasury();
        _sendETH(treasury, totalAmount);
    }

    function _sendETH(address recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert FeeTransferFailed();
    }

    function _distributeERC20(address token, uint256 totalAmount) internal {
        if (totalAmount == 0) return;
        if (treasury == address(0)) revert InvalidTreasury();
        IERC20(token).safeTransfer(treasury, totalAmount);
    }

    function setFeeWallets(address _feeWallet1, address _feeWallet2, address _feeWallet3) external onlyOwner {
        if (_feeWallet1 == address(0) || _feeWallet2 == address(0) || _feeWallet3 == address(0)) {
            revert InvalidFeeWallet();
        }
        feeWallet1 = _feeWallet1;
        feeWallet2 = _feeWallet2;
        feeWallet3 = _feeWallet3;
    }

    function team() external view returns (address) {
        return royaltyReceiver;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidTreasury();
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    function setTeam(address _team) external onlyOwner {
        _setRoyaltyReceiver(_team);
    }

    /// @notice Set default royalty receiver address, normally the DePunks Team
    function setRoyaltyReceiver(address _royaltyReceiver) external onlyOwner {
        _setRoyaltyReceiver(_royaltyReceiver);
    }

    function _setRoyaltyReceiver(address _royaltyReceiver) internal {
        if (_royaltyReceiver == address(0)) revert InvalidRoyaltyReceiver();
        emit RoyaltyReceiverUpdated(royaltyReceiver, _royaltyReceiver);
        royaltyReceiver = _royaltyReceiver;
        _setDefaultRoyalty(royaltyReceiver, ROYALTY_FEE);
    }

    function setPaymentDistribution(uint16 _wallet1Points, uint16 _wallet2Points) external onlyOwner {
        if (_wallet1Points + _wallet2Points > BASE_POINTS) {
            revert InvalidPaymentDistribution();
        }
        wallet1Points = _wallet1Points;
        wallet2Points = _wallet2Points;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoETHToWithdraw();
        _distributePayment(balance);
    }

    /// @notice Emergency withdraw ERC-20 tokens sent to this contract
    function withdrawERC20(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidTokenAddress();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoTokensToWithdraw();
        _distributeERC20(token, balance);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================
    //                   CREATOR TOKEN (ROYALTY ENFORCEMENT)
    // =============================================================

    /// @inheritdoc ICreatorToken
    function getTransferValidator() external view override returns (address) {
        return _transferValidator;
    }

    /// @inheritdoc ICreatorToken
    function setTransferValidator(address validator) external override onlyOwner {
        if (validator == address(0)) revert InvalidTransferValidator();
        emit TransferValidatorUpdated(_transferValidator, validator);
        _transferValidator = validator;
    }

    /// @notice Auto-approve OpenSea operators so ERC1155 orders remain fillable
    ///         even when OpenSea uses a direct Seaport path instead of the conduit.
    function isApprovedForAll(address account, address operator) public view override returns (bool) {
        if (_isOpenSeaOperator(operator)) {
            return true;
        }
        return super.isApprovedForAll(account, operator);
    }

    /// @inheritdoc ICreatorToken
    function getTransferValidationFunction()
        external
        pure
        override
        returns (bytes4 functionSignature, bool isViewFunction)
    {
        functionSignature = ITransferValidator1155.validateTransfer.selector;
        isViewFunction = false;
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    function getAvailablePoolSize() external view returns (uint256) {
        return totalAttributeSupply - LibPRNG.numShuffled(shuffler) - pendingReservedTokens;
    }

    function getAttributeTypeMaxSupply(uint256 tokenId) external view returns (uint256) {
        uint256 _maxSupply = maxSupplies[tokenId];
        if (_maxSupply == 0) revert InvalidTypeId();
        return _maxSupply;
    }

    function getRemainingSupplyForAllTokens()
        external
        view
        returns (uint256[] memory tokenIds, uint256[] memory remainingSupplies)
    {
        uint256 length = addedTokenIds.length;
        tokenIds = new uint256[](length);
        remainingSupplies = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            tokenIds[i] = addedTokenIds[i];
            remainingSupplies[i] = remainingSupplyPerToken[addedTokenIds[i]];
        }

        return (tokenIds, remainingSupplies);
    }

    function getFixedSaleTokenIds() external view returns (uint256[] memory) {
        uint256 fixedSaleTokenIdsSlot;
        assembly {
            fixedSaleTokenIdsSlot := fixedSaleTokenIds.slot
        }
        return AttributeFixedSaleLib.getFixedSaleTokenIds(fixedSaleTokenIdsSlot);
    }

    function getFixedSaleConfig(uint256 tokenId) external view returns (AttributeFixedSaleLib.FixedSaleConfig memory) {
        uint256 fixedSaleConfigsSlot;
        assembly {
            fixedSaleConfigsSlot := fixedSaleConfigs.slot
        }
        return AttributeFixedSaleLib.getFixedSaleConfig(fixedSaleConfigsSlot, tokenId);
    }

    function getFixedSaleRemainingSupply(uint256 tokenId) external view returns (uint256) {
        uint256 fixedSaleConfigsSlot;
        assembly {
            fixedSaleConfigsSlot := fixedSaleConfigs.slot
        }
        return AttributeFixedSaleLib.getFixedSaleRemainingSupply(fixedSaleConfigsSlot, tokenId);
    }

    function getFixedSaleClaimed(uint256 tokenId) external view returns (uint16 artistClaimed, uint16 treasuryClaimed) {
        uint256 fixedSaleConfigsSlot;
        uint256 fixedSaleClaimedSlot;
        assembly {
            fixedSaleConfigsSlot := fixedSaleConfigs.slot
            fixedSaleClaimedSlot := fixedSaleClaimed.slot
        }
        return AttributeFixedSaleLib.getFixedSaleClaimed(fixedSaleConfigsSlot, fixedSaleClaimedSlot, tokenId);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory baseURI = super.uri(tokenId);
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : "";
    }

    // =============================================================
    //                    REQUIRED OVERRIDES
    // =============================================================

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable)
    {
        // Validate transfers (skip mints and burns)
        if (from != address(0) && to != address(0)) {
            if (_transferValidator == address(0)) revert TransferValidatorNotSet();
            for (uint256 i = 0; i < ids.length; i++) {
                ITransferValidator1155(_transferValidator).validateTransfer(msg.sender, from, to, ids[i], values[i]);
            }
        }
        super._update(from, to, ids, values);
    }

    receive() external payable {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return interfaceId == type(ICreatorToken).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Authorize upgrade (only owner)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _isOpenSeaOperator(address operator) private pure returns (bool) {
        return operator == OPENSEA_CONDUIT || operator == OPENSEA_SEAPORT_1_6 || operator == OPENSEA_SEAPORT_1_1
            || operator == OPENSEA_TRANSFER_HELPER;
    }

    // =============================================================
    //                      VRF V2.5 STORAGE (V3)
    // =============================================================

    /// @notice Chainlink VRF v2.5 coordinator address
    address public vrfCoordinator;
    /// @notice VRF callback gas limit
    uint32 public vrfCallbackGasLimit;
    /// @notice VRF request confirmations
    uint16 public vrfRequestConfirmations;
    /// @notice Maximum tokens per single mint request
    uint8 public maxTokensPerMint;

    /// @notice Chainlink VRF subscription ID
    uint256 public vrfSubscriptionId;

    /// @notice Chainlink VRF key hash (gas lane)
    bytes32 public vrfKeyHash;

    /// @notice Pending VRF mint requests by requestId
    mapping(uint256 => MintRequest) public pendingMintRequests;

    /// @notice Number of tokens reserved by pending VRF requests
    uint256 public pendingReservedTokens;

    /// @notice Claimable mints for failed deliveries (contract wallet receiver reverts)
    mapping(uint256 => ClaimableMint) private claimableMints;

    // =============================================================
    //                    FIXED-PRICE SALE STORAGE (V4)
    // =============================================================

    /// @notice Current mint and protocol fee recipient.
    /// @dev Added in the first available reserved gap slot for upgrade safety.
    address public treasury;

    /// @notice Fixed-price sale configs keyed by ERC1155 token ID.
    mapping(uint256 => FixedSaleConfig) private fixedSaleConfigs;

    /// @notice Token IDs configured for fixed-price sales.
    uint256[] private fixedSaleTokenIds;

    /// @notice Free allocation claim counts keyed by ERC1155 token ID.
    mapping(uint256 => FixedSaleClaimed) private fixedSaleClaimed;

    // =============================================================
    //                        STORAGE GAP
    // =============================================================

    uint256[37] private __gap;
}
