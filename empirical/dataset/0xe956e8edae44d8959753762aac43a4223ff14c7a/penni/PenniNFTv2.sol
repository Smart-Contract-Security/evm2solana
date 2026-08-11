// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721AC} from "@limitbreak/creator-token-standards/src/erc721c/ERC721AC.sol";
import {BasicRoyalties} from "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title PenniNFTv2
/// @notice ERC-721C collection for Penni. 2,500 max supply. 1,750 minted in one
///         shot by the team wallet, 750 mintable through the public flow
///         (GTD / FCFS / Public). Transfers are locked at deploy and unlocked
///         once via `enableTrading()` — irreversibly. 5% on-chain enforced
///         royalties via ERC-721C.
contract PenniNFTv2 is ERC721AC, BasicRoyalties, Ownable, ReentrancyGuard, Pausable {
    using Strings for uint256;

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    uint256 public constant MAX_SUPPLY       = 2500;
    uint256 public constant MINTABLE_SUPPLY  = 750;
    uint256 public constant TEAM_ALLOCATION  = 1750;

    uint8 public constant PHASE_CLOSED = 0;
    uint8 public constant PHASE_GTD    = 1;
    uint8 public constant PHASE_FCFS   = 2;
    uint8 public constant PHASE_PUBLIC = 3;

    uint256 public constant PRICE_FEED_STALENESS = 1 hours;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------
    struct PhaseConfig {
        uint16 supplyCap;       // 0 = unbounded within MINTABLE_SUPPLY
        uint8  walletCap;
        uint32 duration;        // seconds
        uint64 priceUsdCents;
    }

    AggregatorV3Interface public immutable ethUsdFeed;
    address public immutable treasury;     // immutable: receives mint funds + royalties forever
    address public immutable deployer;     // immutable: only wallet that can call freeze*()
    address public stakingContract;
    address public teamWallet;

    uint256 public publicMinted;          // GTD+FCFS+Public combined (0..750)
    bool    public teamMinted;            // one-shot
    bool    public tradingEnabled;        // one-way switch
    bool    public metadataFrozen;        // one-way: blocks setBaseURI/setNotRevealedURI
    bool    public supplyFrozen;          // one-way: locks max supply at _totalMinted()
    uint256 public frozenSupplyCap;       // set when supplyFrozen flips to true

    uint256 public mintStartTime;
    bytes32 public gtdMerkleRoot;
    bytes32 public fcfsMerkleRoot;

    string private _baseTokenURI;
    string public  notRevealedURI;
    bool   public  revealed;

    mapping(uint256 => bool) public locked;
    mapping(address => mapping(uint8 => uint8)) public mintedByPhase;
    mapping(uint8 => uint16) public mintedByPhaseSupply;
    mapping(uint8 => PhaseConfig) public phaseConfig;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event MintStarted(uint256 startTime);
    event MerkleRootUpdated(uint8 phase, bytes32 root);
    event StakingContractUpdated(address indexed staking);
    event TeamWalletUpdated(address indexed wallet);
    event TeamMinted(address indexed to, uint256 qty);
    event TradingEnabled();
    event MetadataFrozen();
    event SupplyFrozen(uint256 cap);
    event PhaseConfigUpdated(uint8 indexed phase, uint16 supplyCap, uint8 walletCap, uint32 duration, uint64 priceUsdCents);
    event TokenLocked(uint256 indexed tokenId);
    event TokenUnlocked(uint256 indexed tokenId);
    event Revealed();
    event Withdrawn(address indexed to, uint256 amount);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error MintNotStarted();
    error WrongPhase();
    error InvalidProof();
    error CapExceeded();
    error PhaseSupplyExceeded();
    error SupplyExceeded();
    error InsufficientPayment();
    error RefundFailed();
    error TokenIsLocked();
    error OnlyStaking();
    error OnlyTeamWallet();
    error PriceFeedStale();
    error InvalidPrice();
    error LengthMismatch();
    error NoContracts();
    error TradingLocked();
    error AlreadyDone();
    error TeamWalletUnset();
    error InvalidConfig();
    error MetadataIsFrozen();
    error SupplyIsFrozen();
    error OnlyDeployer();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    constructor(address _treasury, address _ethUsdFeed, string memory _notRevealedURI)
        ERC721AC("Penni", "PENNI")
        BasicRoyalties(_treasury, 500)
    {
        require(_treasury != address(0), "treasury=0");
        require(_ethUsdFeed != address(0), "feed=0");
        treasury = _treasury;
        deployer = msg.sender;
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        notRevealedURI = _notRevealedURI;

        // Sensible defaults — admin can tune via setPhaseConfig before startMint.
        phaseConfig[PHASE_GTD]    = PhaseConfig({ supplyCap: 0, walletCap: 1, duration: 3 hours, priceUsdCents: 4000  });
        phaseConfig[PHASE_FCFS]   = PhaseConfig({ supplyCap: 0, walletCap: 1, duration: 5 hours, priceUsdCents: 5000  });
        phaseConfig[PHASE_PUBLIC] = PhaseConfig({ supplyCap: 0, walletCap: 2, duration: 0,       priceUsdCents: 10000 });
    }

    modifier onlyDeployer() {
        if (msg.sender != deployer) revert OnlyDeployer();
        _;
    }

    // ---------------------------------------------------------------------
    // Mint
    // ---------------------------------------------------------------------
    function mint(uint8 phase, uint8 qty, bytes32[] calldata proof)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        if (msg.sender != tx.origin) revert NoContracts();
        if (qty == 0) revert CapExceeded();
        if (supplyFrozen) revert SupplyIsFrozen();
        if (mintStartTime == 0) revert MintNotStarted();
        if (phase != currentPhase()) revert WrongPhase();

        PhaseConfig memory cfg = phaseConfig[phase];

        uint8 already = mintedByPhase[msg.sender][phase];
        if (already + qty > cfg.walletCap) revert CapExceeded();

        if (publicMinted + qty > MINTABLE_SUPPLY) revert SupplyExceeded();
        if (_totalMinted() + qty > MAX_SUPPLY) revert SupplyExceeded();

        if (cfg.supplyCap != 0 && mintedByPhaseSupply[phase] + qty > cfg.supplyCap) {
            revert PhaseSupplyExceeded();
        }

        if (phase == PHASE_GTD || phase == PHASE_FCFS) {
            bytes32 root = phase == PHASE_GTD ? gtdMerkleRoot : fcfsMerkleRoot;
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            if (!MerkleProof.verifyCalldata(proof, root, leaf)) revert InvalidProof();
        }

        uint256 required = _priceInWeiFromCents(cfg.priceUsdCents) * qty;
        if (msg.value < required) revert InsufficientPayment();

        mintedByPhase[msg.sender][phase] = already + qty;
        mintedByPhaseSupply[phase] += qty;
        publicMinted += qty;

        _mint(msg.sender, qty);

        uint256 refund = msg.value - required;
        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundFailed();
        }
    }

    // ---------------------------------------------------------------------
    // Team mint — one-shot, must happen before public mint starts
    // ---------------------------------------------------------------------
    function teamMint() external nonReentrant {
        if (teamWallet == address(0)) revert TeamWalletUnset();
        if (msg.sender != teamWallet) revert OnlyTeamWallet();
        if (teamMinted) revert AlreadyDone();
        if (supplyFrozen) revert SupplyIsFrozen();
        if (mintStartTime != 0) revert AlreadyDone(); // must be before public mint
        if (_totalMinted() + TEAM_ALLOCATION > MAX_SUPPLY) revert SupplyExceeded();

        teamMinted = true;
        _mint(teamWallet, TEAM_ALLOCATION);
        emit TeamMinted(teamWallet, TEAM_ALLOCATION);
    }

    // ---------------------------------------------------------------------
    // Phase / price helpers
    // ---------------------------------------------------------------------
    function currentPhase() public view returns (uint8) {
        if (mintStartTime == 0) return PHASE_CLOSED;
        if (publicMinted >= MINTABLE_SUPPLY) return PHASE_CLOSED; // sold out
        uint256 elapsed = block.timestamp - mintStartTime;
        uint256 gtdEnd = phaseConfig[PHASE_GTD].duration;
        uint256 fcfsEnd = gtdEnd + phaseConfig[PHASE_FCFS].duration;
        if (elapsed < gtdEnd) return PHASE_GTD;
        if (elapsed < fcfsEnd) return PHASE_FCFS;
        return PHASE_PUBLIC;
    }

    function phaseStartTime(uint8 phase) external view returns (uint256) {
        if (mintStartTime == 0) return 0;
        if (phase == PHASE_GTD) return mintStartTime;
        if (phase == PHASE_FCFS) return mintStartTime + phaseConfig[PHASE_GTD].duration;
        if (phase == PHASE_PUBLIC) return mintStartTime + phaseConfig[PHASE_GTD].duration + phaseConfig[PHASE_FCFS].duration;
        return 0;
    }

    function priceInWei(uint8 phase) public view returns (uint256) {
        return _priceInWeiFromCents(phaseConfig[phase].priceUsdCents);
    }

    function _priceInWeiFromCents(uint256 usdCents) internal view returns (uint256) {
        if (usdCents == 0) revert InvalidPrice();
        (, int256 answer, , uint256 updatedAt, ) = ethUsdFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > PRICE_FEED_STALENESS) revert PriceFeedStale();
        uint8 feedDecimals = ethUsdFeed.decimals();
        return (usdCents * 1e18 * (10 ** feedDecimals)) / (uint256(answer) * 100);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------
    function startMint() external onlyOwner {
        require(mintStartTime == 0, "already started");
        mintStartTime = block.timestamp;
        emit MintStarted(block.timestamp);
    }

    function setPhaseConfig(
        uint8 phase,
        uint16 supplyCap,
        uint8 walletCap,
        uint32 duration,
        uint64 priceUsdCents
    ) external onlyOwner {
        if (phase != PHASE_GTD && phase != PHASE_FCFS && phase != PHASE_PUBLIC) revert InvalidConfig();
        if (walletCap == 0) revert InvalidConfig();
        if (priceUsdCents == 0) revert InvalidConfig();
        // Cannot lower supply cap below what's already minted in this phase.
        if (supplyCap != 0 && supplyCap < mintedByPhaseSupply[phase]) revert InvalidConfig();
        phaseConfig[phase] = PhaseConfig({
            supplyCap: supplyCap,
            walletCap: walletCap,
            duration: duration,
            priceUsdCents: priceUsdCents
        });
        emit PhaseConfigUpdated(phase, supplyCap, walletCap, duration, priceUsdCents);
    }

    function setTeamWallet(address _wallet) external onlyOwner {
        if (teamMinted) revert AlreadyDone();
        require(_wallet != address(0), "wallet=0");
        teamWallet = _wallet;
        emit TeamWalletUpdated(_wallet);
    }

    function setMerkleRoots(bytes32 _gtd, bytes32 _fcfs) external onlyOwner {
        gtdMerkleRoot = _gtd;
        fcfsMerkleRoot = _fcfs;
        emit MerkleRootUpdated(PHASE_GTD, _gtd);
        emit MerkleRootUpdated(PHASE_FCFS, _fcfs);
    }

    // Treasury is IMMUTABLE — no setter. Receives mint funds + 5% royalties forever.

    function setStakingContract(address _staking) external onlyOwner {
        stakingContract = _staking;
        emit StakingContractUpdated(_staking);
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        if (metadataFrozen) revert MetadataIsFrozen();
        _baseTokenURI = uri;
    }
    function setNotRevealedURI(string calldata uri) external onlyOwner {
        if (metadataFrozen) revert MetadataIsFrozen();
        notRevealedURI = uri;
    }

    function reveal() external onlyOwner {
        revealed = true;
        emit Revealed();
    }

    /// @notice Irreversibly unlock secondary trading. Once on, cannot be undone.
    function enableTrading() external onlyOwner {
        if (tradingEnabled) revert AlreadyDone();
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /// @notice Irreversibly freeze metadata. Only the original deployer wallet can call.
    ///         After this, setBaseURI / setNotRevealedURI revert forever.
    function freezeMetadata() external onlyDeployer {
        if (metadataFrozen) revert AlreadyDone();
        metadataFrozen = true;
        emit MetadataFrozen();
    }

    /// @notice Irreversibly cap supply at the current _totalMinted(). Only the
    ///         original deployer wallet can call. Blocks all further mints
    ///         (public mint, team mint, ownerAirdrop) forever.
    function freezeSupply() external onlyDeployer {
        if (supplyFrozen) revert AlreadyDone();
        supplyFrozen = true;
        frozenSupplyCap = _totalMinted();
        emit SupplyFrozen(frozenSupplyCap);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Airdrop tokens to arbitrary recipients. DEPLOYER-ONLY — not callable
    ///         by owner, team wallet, or any future wallet (including from Etherscan).
    function ownerAirdrop(address[] calldata recipients, uint256[] calldata qtys)
        external
        onlyDeployer
    {
        if (supplyFrozen) revert SupplyIsFrozen();
        if (recipients.length != qtys.length) revert LengthMismatch();
        uint256 total;
        for (uint256 i; i < qtys.length; ++i) total += qtys[i];
        if (_totalMinted() + total > MAX_SUPPLY) revert SupplyExceeded();
        for (uint256 i; i < recipients.length; ++i) {
            _mint(recipients[i], qtys[i]);
        }
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        (bool ok, ) = treasury.call{value: bal}("");
        require(ok, "withdraw failed");
        emit Withdrawn(treasury, bal);
    }

    // ---------------------------------------------------------------------
    // Staking lock hooks
    // ---------------------------------------------------------------------
    modifier onlyStaking() {
        if (msg.sender != stakingContract) revert OnlyStaking();
        _;
    }

    function lock(uint256 tokenId) external onlyStaking {
        locked[tokenId] = true;
        emit TokenLocked(tokenId);
    }

    function unlock(uint256 tokenId) external onlyStaking {
        locked[tokenId] = false;
        emit TokenUnlocked(tokenId);
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        // Mints always allowed (from == 0). Burns blocked implicitly above too.
        if (from != address(0) && to != address(0)) {
            // Block all peer-to-peer / marketplace transfers until trading enabled,
            // EXCEPT: (1) staking lock/unlock (non-custodial, no transfer occurs),
            // and (2) transfers where the original deployer is either the sender
            // or the tx initiator. This lets the deployer pre-distribute the 1,750
            // team allocation (e.g. from the team wallet) before public trading
            // is unlocked. Locked (staked) tokens still cannot move.
            if (!tradingEnabled && from != deployer && tx.origin != deployer) {
                revert TradingLocked();
            }
            for (uint256 i; i < quantity; ++i) {
                if (locked[startTokenId + i]) revert TokenIsLocked();
            }
        }
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }

    // ---------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert OwnerQueryForNonexistentToken();
        if (!revealed) return notRevealedURI;
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ---------------------------------------------------------------------
    // Interface support
    // ---------------------------------------------------------------------
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721AC, ERC2981)
        returns (bool)
    {
        return ERC721AC.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    // setRoyaltyInfo REMOVED — royalty receiver and rate are locked at 5% to the
    // immutable treasury wallet for the life of the contract.

    function _requireCallerIsContractOwner() internal view virtual override {
        require(owner() == _msgSender(), "caller not owner");
    }
}