// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./Base64.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISVGRenderer {
    function render(uint256 tokenId, bool evolved) external view returns (string memory);
}

// IERC20 provided by SafeERC20 import
// 

/**
 * @title   GhostRoot
 * @notice  2000 generative on-chain terminal NFTs.
 * @dev     Owner has elevated privileges. Trust model: owner controls mint phases,
 *          treasury, signer, and reserve release. No timelock implemented.
 *          Front-running: signatures are not bound to msg.sender by design.
 *          First execution claims — hacker ethos intentional.
 *          No mint page. Find the code. Earn your terminal.
 *          Signature-based minting — no on-chain hash storage.
 *          Soulbound until sold out. 80% refund anytime via burn.
 */
contract GhostRoot is ERC721, Ownable, IERC2981, IERC4906 {

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------
    //  CONSTANTS
    // ---------------------------------------------------------------

    uint256 public constant MAX_SUPPLY    = 2000;
    uint256 public constant MINT_PRICE    = 0.0026 ether;
    uint256 public constant TREASURY_CUT  = 0.00052 ether;
    uint256 public constant REFUND_AMOUNT = 0.00208 ether;
    uint256 public constant GRACE_PERIOD  = 5;        // ~1 minute after soldOut
    // ---------------------------------------------------------------
    //  CONFIGURABLE STATE
    // ---------------------------------------------------------------

    uint256 public maxPerWallet  = 1;
    uint256 public burnsRequired = 2;
    uint256 public royaltyBps    = 500;

    // ---------------------------------------------------------------
    //  CORE STATE
    // ---------------------------------------------------------------

    uint256 public totalMinted;
    uint256 public totalBurned;
    uint256 public totalReserveOwed;

    bool public mintingActive      = true;  // global pause — affects both mint types
    bool public signatureMintActive = true;   // Phase 1 — code hunt
    bool public publicMintActive    = false;  // Phase 2 — open mint
    bool public soldOut          = false;
    uint256 public soldOutBlock   = 0;

    address payable public treasury;
    address public signerAddress;        // wallet that signs codes
    ISVGRenderer    public renderer;
    ISVGRenderer    public evolvedRenderer;

    // ---------------------------------------------------------------
    //  MAPPINGS
    // ---------------------------------------------------------------

    mapping(bytes32  => bool)    public usedCodes;   // hash → used
    mapping(address  => uint256) public mintCount;
    mapping(uint256  => bool)    public refunded;
    mapping(uint256  => bool)    public evolved;
    mapping(uint256  => bytes4[]) public terminalHistory;
    mapping(uint256  => uint256)  public saleCount;

    // ---------------------------------------------------------------
    //  TERMINAL HISTORY CONSTANTS
    // ---------------------------------------------------------------

    uint256 public constant MAX_HISTORY = 8;

    // Function selectors
    bytes4 private constant MINT_SEL     = bytes4(keccak256("mint(string,bytes)"));
    bytes4 private constant PUB_MINT_SEL = bytes4(keccak256("publicMint()"));
    bytes4 private constant EVOLVE_SEL   = bytes4(keccak256("evolve(uint256,uint256[])"));

    // Configurable marketplace addresses — owner can add/remove
    mapping(address => bool) public knownMarketplace;

    // ---------------------------------------------------------------
    //  EVENTS
    // ---------------------------------------------------------------

    event CodeUsed(bytes32 indexed codeHash, address indexed minter, uint256 tokenId);
    event TreasuryUpdated(address indexed newTreasury);
    event SignerUpdated(address indexed newSigner);
    event MintingToggled(bool active);
    event SignatureMintToggled(bool active);
    event PublicMintToggled(bool active);
    event PublicMinted(address indexed minter, uint256 tokenId);
    event ReservesReleased(uint256 amount);
    event MaxPerWalletUpdated(uint256 newMax);
    event BurnsRequiredUpdated(uint256 newBurns);
    event RoyaltyUpdated(uint256 newBps);
    event RendererUpdated(address indexed newRenderer);
    event MarketplaceUpdated(address indexed marketplace, bool approved);
    event Evolved(uint256 indexed receiverTokenId, uint256[] burnedTokenIds, address indexed owner);
    event DropSignaled(bytes32 encodedHint, uint256 expiry, uint256 codeCount);
    event Refunded(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event SoldOut(uint256 timestamp);

    // ---------------------------------------------------------------
    //  TERMINAL HISTORY HELPER
    // ---------------------------------------------------------------

    function _pushHistory(uint256 tokenId, bytes4 selector) internal {
        if (terminalHistory[tokenId].length < MAX_HISTORY) {
            terminalHistory[tokenId].push(selector);
        }
    }

    // ---------------------------------------------------------------
    //  CONSTRUCTOR
    // ---------------------------------------------------------------

    constructor(
        address payable _treasury,
        address _signer,
        address _renderer
    )
        ERC721("GHOST_ROOT", "GSTR")
        Ownable(msg.sender)
    {
        require(_treasury != address(0), "zero addr");
        require(_signer   != address(0), "zero addr");
        require(_renderer != address(0), "zero addr");
        treasury      = _treasury;
        signerAddress = _signer;
        renderer      = ISVGRenderer(_renderer);

        // Pre-approve known marketplaces
        knownMarketplace[0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC] = true; // OpenSea Seaport 1.5
        knownMarketplace[0x1E0049783F008A0085193E00003D00cd54003c71] = true; // OpenSea Conduit
        knownMarketplace[0x00000000000111AbE46ff893f3B2fdF1F759a8A8] = true; // Blur Execution Delegate
    }

    // ---------------------------------------------------------------
    //  MINT — signature based
    //  rawCode + signature signed by signerAddress
    //  No pre-loading of hashes needed
    // ---------------------------------------------------------------

    function mint(string calldata rawCode, bytes calldata signature) external payable {
        require(mintingActive,                        "paused");
        require(signatureMintActive,                  "paused");
        require(msg.value == MINT_PRICE,              "wrong ETH");
        require(totalMinted < MAX_SUPPLY,             "sold out");
        require(mintCount[msg.sender] < maxPerWallet, "limit");

        bytes32 codeHash = keccak256(abi.encodePacked(rawCode));

        require(!usedCodes[codeHash], "used");


        // Verify signature — signer must have signed the raw code
        bytes32 msgHash = codeHash.toEthSignedMessageHash();
        address recovered = msgHash.recover(signature);
        require(recovered == signerAddress, "invalid");

        usedCodes[codeHash] = true;
        mintCount[msg.sender]++;

        uint256 tokenId = totalMinted;
        totalMinted++;
        totalReserveOwed += REFUND_AMOUNT;
        _mint(msg.sender, tokenId);

        // 20% to treasury instantly
        (bool sent, ) = treasury.call{value: TREASURY_CUT}("");
        require(sent, "treasury fail");

        if (totalMinted == MAX_SUPPLY) {
            soldOut      = true;
            soldOutBlock = block.number;
            emit SoldOut(block.timestamp);
        }

        _pushHistory(tokenId, MINT_SEL);
        emit CodeUsed(codeHash, msg.sender, tokenId);
    }

    // ---------------------------------------------------------------
    //  REFUND
    // ---------------------------------------------------------------

    function refund(uint256 tokenId) external {
        bool inGrace = soldOut && block.number < soldOutBlock + GRACE_PERIOD;
        require(!soldOut || inGrace, "closed");
        require(ownerOf(tokenId) == msg.sender, "not owner");
        require(!refunded[tokenId],             "refunded");
        require(!evolved[tokenId],              "evolved");

        refunded[tokenId] = true;
        totalBurned++;
        require(totalReserveOwed >= REFUND_AMOUNT, "reserve low");
        totalReserveOwed -= REFUND_AMOUNT;
        _burn(tokenId);

        (bool sent, ) = payable(msg.sender).call{value: REFUND_AMOUNT}("");
        require(sent, "refund fail");

        emit Refunded(tokenId, msg.sender, REFUND_AMOUNT);
    }

    // ---------------------------------------------------------------
    //  RELEASE RESERVES
    // ---------------------------------------------------------------


    // ---------------------------------------------------------------
    //  SOULBOUND
    // ---------------------------------------------------------------

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            require(soldOut, "soulbound");
        }
        address prev = super._update(to, tokenId, auth);
        // Track marketplace sales
        if (from != address(0) && to != address(0)) {
            if (knownMarketplace[msg.sender]) {
                saleCount[tokenId]++;
            }
            // ERC-4906: notify marketplaces when evolved token transfers
            if (evolved[tokenId]) {
                emit MetadataUpdate(tokenId);
            }
        }
        return prev;
    }

    // ---------------------------------------------------------------
    //  BURN TO EVOLVE
    // ---------------------------------------------------------------

    function evolve(uint256 receiverTokenId, uint256[] calldata burnTokenIds) external {
        require(burnTokenIds.length == burnsRequired,   "burns");
        require(ownerOf(receiverTokenId) == msg.sender, "not owner");
        require(!evolved[receiverTokenId],              "evolved");

        for (uint256 i = 0; i < burnTokenIds.length; i++) {
            for (uint256 j = i + 1; j < burnTokenIds.length; j++) {
                require(burnTokenIds[i] != burnTokenIds[j], "dup burn");
            }
        }

        for (uint256 i = 0; i < burnTokenIds.length; i++) {
            uint256 burnId = burnTokenIds[i];
            require(ownerOf(burnId) == msg.sender, "not owner");
            require(burnId != receiverTokenId,     "receiver");
            _burn(burnId);
            totalBurned++;
            // H-01 fix: only deduct reserve if token was NOT already evolved
            // evolved tokens already had their reserve liability cleared
            if (!evolved[burnId]) {
                require(totalReserveOwed >= REFUND_AMOUNT, "reserve low");
                totalReserveOwed -= REFUND_AMOUNT;
            }
        }

        evolved[receiverTokenId] = true;
        require(totalReserveOwed >= REFUND_AMOUNT, "reserve low");
        totalReserveOwed -= REFUND_AMOUNT;

        _pushHistory(receiverTokenId, EVOLVE_SEL);
        emit MetadataUpdate(receiverTokenId);
        emit Evolved(receiverTokenId, burnTokenIds, msg.sender);
    }

    // ---------------------------------------------------------------
    //  SIGNAL DROP
    //  Sets expiry on code hashes + emits encoded hint for hackers
    //  Hashes computed off-chain from raw codes
    // ---------------------------------------------------------------

    function signalDrop(
        bytes32[] calldata codeHashes,
        bytes32 encodedHint
    ) external onlyOwner {
        // No expiry — codes live until used or replaced
        // encodedHint is decoded by hackers watching mempool
        emit DropSignaled(encodedHint, 0, codeHashes.length);
    }

    // ---------------------------------------------------------------
    //  RELEASE RESERVES — callable after 1 min grace period
    // ---------------------------------------------------------------

    function releaseReserves() external onlyOwner {
        require(soldOut, "not sold");
        require(block.number >= soldOutBlock + GRACE_PERIOD, "grace");
        uint256 balance = address(this).balance;
        require(balance > 0, "nothing");
        totalReserveOwed = 0;
        (bool sent, ) = treasury.call{value: balance}("");
        require(sent, "release fail");
        emit ReservesReleased(balance);
    }

    // ---------------------------------------------------------------
    //  WITHDRAW EXCESS
    // ---------------------------------------------------------------

    function withdrawExcess() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > totalReserveOwed, "no excess");
        uint256 excess = balance - totalReserveOwed;
        (bool sent, ) = treasury.call{value: excess}("");
        require(sent, "withdraw fail");
    }

    // ---------------------------------------------------------------
    //  OWNER CONFIG
    // ---------------------------------------------------------------

    function setMaxPerWallet(uint256 _max) external onlyOwner {
        maxPerWallet = _max;
        emit MaxPerWalletUpdated(_max);
    }

    function setBurnsRequired(uint256 _burns) external onlyOwner {
        require(_burns >= 1 && _burns <= 20, "1-20");
        burnsRequired = _burns;
        emit BurnsRequiredUpdated(_burns);
    }

    function setRoyaltyBps(uint256 _bps) external onlyOwner {
        require(_bps <= 1000, "max 10%");
        royaltyBps = _bps;
        emit RoyaltyUpdated(_bps);
    }

    function setTreasury(address payable _t) external onlyOwner {
        require(_t != address(0), "zero addr");
        treasury = _t;
        emit TreasuryUpdated(_t);
    }

    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "zero addr");
        signerAddress = _signer;
        emit SignerUpdated(_signer);
    }

    function setRenderer(address _r) external onlyOwner {
        require(_r != address(0), "zero addr");
        renderer = ISVGRenderer(_r);
        emit RendererUpdated(_r);
    }

    function setEvolvedRenderer(address _r) external onlyOwner {
        require(_r != address(0), "zero addr");
        evolvedRenderer = ISVGRenderer(_r);
        emit RendererUpdated(_r);
        // Notify marketplaces to refresh all evolved token metadata
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setMarketplace(address _marketplace, bool _approved) external onlyOwner {
        require(_marketplace != address(0), "zero addr");
        knownMarketplace[_marketplace] = _approved;
        emit MarketplaceUpdated(_marketplace, _approved);
    }

    // Global pause — stops all minting
    function toggleMinting() external onlyOwner {
        mintingActive = !mintingActive;
        emit MintingToggled(mintingActive);
    }

    // Phase 1 toggle — signature mint on/off
    function toggleSignatureMint() external onlyOwner {
        signatureMintActive = !signatureMintActive;
        if (signatureMintActive) publicMintActive = false;
        emit SignatureMintToggled(signatureMintActive);
    }

    // Phase 2 toggle — public mint on/off
    function togglePublicMint() external onlyOwner {
        publicMintActive = !publicMintActive;
        if (publicMintActive) signatureMintActive = false;
        emit PublicMintToggled(publicMintActive);
    }

    // ── PUBLIC MINT ───────────────────────────────────────────────
    // Phase 2 — no code needed, owner toggles on when ready
    function publicMint() external payable {
        require(publicMintActive,                     "not open");
        require(mintingActive,                        "paused");
        require(msg.value == MINT_PRICE,              "wrong ETH");
        require(totalMinted < MAX_SUPPLY,             "sold out");
        require(mintCount[msg.sender] < maxPerWallet, "limit");

        mintCount[msg.sender]++;
        uint256 tokenId = totalMinted;
        totalMinted++;
        totalReserveOwed += REFUND_AMOUNT;
        _mint(msg.sender, tokenId);

        (bool sent, ) = treasury.call{value: TREASURY_CUT}("");
        require(sent, "treasury fail");

        _pushHistory(tokenId, PUB_MINT_SEL);
        emit PublicMinted(msg.sender, tokenId);

        if (totalMinted == MAX_SUPPLY) {
            soldOut      = true;
            soldOutBlock = block.number;
            emit SoldOut(block.timestamp);
        }
    }

    function rescueERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "bad token");
        IERC20(token).safeTransfer(treasury, amount);
    }

    function rescueETH() external onlyOwner {
        require(soldOut, "not sold out");
        require(block.number >= soldOutBlock + GRACE_PERIOD, "grace");
        require(totalReserveOwed == 0, "release first");
        (bool sent, ) = treasury.call{value: address(this).balance}("");
        require(sent, "rescue fail");
    }

    // ---------------------------------------------------------------
    //  VIEWS
    // ---------------------------------------------------------------

    function totalSupply() public view returns (uint256) {
        return totalMinted - totalBurned;
    }

    function gracePeriodEnds() public view returns (uint256) {
        if (!soldOut) return 0;
        return soldOutBlock + GRACE_PERIOD;
    }

    function remaining() public view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }

    function refundReserve() public view returns (uint256) {
        return totalReserveOwed;
    }

    function isTransferable() public view returns (bool) {
        return soldOut;
    }

    function isCodeUsed(string calldata rawCode) external view returns (bool) {
        return usedCodes[keccak256(abi.encodePacked(rawCode))];
    }

    // ---------------------------------------------------------------
    //  METADATA
    // ---------------------------------------------------------------

    function tokenURI(uint256 tokenId)
        public view override returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "no token");
        if (evolved[tokenId] && address(evolvedRenderer) != address(0)) {
            return evolvedRenderer.render(tokenId, true);
        }
        return renderer.render(tokenId, false);
    }

    function contractURI() public pure returns (string memory) {
        string memory json = string(abi.encodePacked(
            '{"name":"GHOST_ROOT",',
            '"description":"2000 generative on-chain terminal NFTs. No mint page. Find the code. Earn your terminal.",',
            '"image":"",',
            '"external_link":"https://ghost-root.xyz"}'
        ));
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    // ---------------------------------------------------------------
    //  ERC-2981
    // ---------------------------------------------------------------

    function royaltyInfo(uint256, uint256 salePrice)
        external view override returns (address, uint256)
    {
        return (treasury, salePrice * royaltyBps / 10000);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, IERC165) returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId
            || interfaceId == type(IERC4906).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------
    //  SAFETY
    // ---------------------------------------------------------------

    receive() external payable {
        revert("use mint");
    }
}
