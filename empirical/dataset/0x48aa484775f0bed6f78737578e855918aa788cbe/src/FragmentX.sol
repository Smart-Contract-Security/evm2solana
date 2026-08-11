// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC721Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external returns (bytes4);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external view returns (address receiver, uint256 royaltyAmount);
}

interface IFragmentXRenderer {
    function tokenURI(uint256 tokenId, uint8 tier, bytes32 seed) external pure returns (string memory);
}

/// @title  FragmentX
/// @notice Fully on-chain ERC-721. 2,000 supply, 1 mint/wallet.
///         Tier dağılımı: Common 1500 | Rare 400 | Legendary 100
///         %10 ERC-2981 royalty.
contract FragmentX is IERC721, IERC721Metadata, IERC165, IERC2981 {

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string public constant name   = "FragmentX";
    string public constant symbol = "FRGX";

    uint16 public constant MAX_SUPPLY          = 10000;
    uint8  public constant MINT_CAP_PER_WALLET = 5;
    uint256 public constant MINT_PRICE         = 0.00015 ether;

    // Tier caps — sum = 2000
    uint16 public constant CAP_COMMON     = 7500;
    uint16 public constant CAP_RARE       = 2000;
    uint16 public constant CAP_LEGENDARY  = 500;

    // %10 royalty
    uint96 public constant ROYALTY_BPS = 500;
    uint96 private constant BPS_DENOM  = 10_000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Minted(address indexed to, uint256 indexed tokenId, uint8 tier, bytes32 seed);
    event RendererSet(address indexed renderer);
    event RendererFrozen();
    event RoyaltyReceiverSet(address indexed receiver);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event OwnerTransferred(address indexed from, address indexed to);
    event MintOpenSet(bool open);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error InvalidAddress();
    error MintClosed();
    error SoldOut();
    error WrongPrice();
    error WalletCapReached();
    error NonexistentToken();
    error NotAuthorized();
    error TransferToZero();
    error TransferFromWrong();
    error UnsafeRecipient();
    error RendererIsFrozen();
    error WithdrawFailed();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public owner;
    address public treasury;
    address public royaltyReceiver;

    IFragmentXRenderer public renderer;
    bool public rendererFrozen;
    bool public mintOpen;

    uint16 public totalSupply;
    uint16 public countCommon;
    uint16 public countRare;
    uint16 public countLegendary;

    mapping(address => uint8) public mintedBy;

    struct Commitment {
        bytes32 seed;
        uint64  mintBlock;
        uint8   tier; // 0=Common 1=Rare 2=Legendary
    }

    mapping(uint256 => Commitment) private _commitments;
    mapping(uint256 => address)    private _ownerOf;
    mapping(address => uint256)    private _balanceOf;
    mapping(uint256 => address)    private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address renderer_, address treasury_) {
        if (renderer_ == address(0)) revert InvalidAddress();
        if (treasury_ == address(0)) revert InvalidAddress();
        owner           = msg.sender;
        renderer        = IFragmentXRenderer(renderer_);
        treasury        = treasury_;
        royaltyReceiver = treasury_;
        emit OwnerTransferred(address(0), msg.sender);
        emit RendererSet(renderer_);
        emit RoyaltyReceiverSet(treasury_);
    }

    /*//////////////////////////////////////////////////////////////
                                AUTH
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintOpenSet(open);
    }

    function setRenderer(address renderer_) external onlyOwner {
        if (rendererFrozen) revert RendererIsFrozen();
        if (renderer_ == address(0)) revert InvalidAddress();
        renderer = IFragmentXRenderer(renderer_);
        emit RendererSet(renderer_);
    }

    function freezeRenderer() external onlyOwner {
        rendererFrozen = true;
        emit RendererFrozen();
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert InvalidAddress();
        treasury = treasury_;
    }

    function setRoyaltyReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert InvalidAddress();
        royaltyReceiver = receiver;
        emit RoyaltyReceiverSet(receiver);
    }

    /*//////////////////////////////////////////////////////////////
                                MINT
    //////////////////////////////////////////////////////////////*/

    function mint() external payable returns (uint256 tokenId, uint8 tier) {
        return _mintTo(msg.sender);
    }

    function mintTo(address to) external payable returns (uint256 tokenId, uint8 tier) {
        if (to == address(0)) revert TransferToZero();
        return _mintTo(to);
    }

    function _mintTo(address to) internal returns (uint256 tokenId, uint8 tier) {
        if (!mintOpen)                          revert MintClosed();
        if (msg.value != MINT_PRICE)            revert WrongPrice();
        if (totalSupply >= MAX_SUPPLY)          revert SoldOut();
        if (mintedBy[to] >= MINT_CAP_PER_WALLET) revert WalletCapReached();

        unchecked {
            totalSupply  += 1;
            mintedBy[to] += 1;
        }
        tokenId = totalSupply;

        bytes32 seed = keccak256(abi.encode(
            block.prevrandao,
            blockhash(block.number - 1),
            to,
            tokenId
        ));

        tier = _rollTier(seed);

        _commitments[tokenId] = Commitment({
            seed:      seed,
            mintBlock: uint64(block.number),
            tier:      tier
        });

        unchecked { _balanceOf[to] += 1; }
        _ownerOf[tokenId] = to;

        emit Minted(to, tokenId, tier, seed);
        emit Transfer(address(0), to, tokenId);
    }

    function _rollTier(bytes32 seed) internal returns (uint8) {
        uint16 roll = uint16(uint256(keccak256(abi.encode(seed, "tier"))) % MAX_SUPPLY);

        // Legendary: 0..99 (100 adet)
        // Rare:      100..499 (400 adet)
        // Common:    500..1999 (1500 adet)
        uint8 desired;
        if      (roll < CAP_LEGENDARY)                    desired = 2;
        else if (roll < CAP_LEGENDARY + CAP_RARE)         desired = 1;
        else                                              desired = 0;

        // İstenen tier doluysa bir alt tier'a in
        while (true) {
            if (_incrementIfRoom(desired)) return desired;
            if (desired == 0) {
                // Common da doluysa diğerlerine bak (teorik olarak olmamalı)
                for (uint8 t = 1; t <= 2; t++) {
                    if (_incrementIfRoom(t)) return t;
                }
                revert SoldOut();
            }
            unchecked { desired -= 1; }
        }
        revert SoldOut();
    }

    function _incrementIfRoom(uint8 tier) internal returns (bool) {
        if (tier == 0 && countCommon    < CAP_COMMON)    { unchecked { countCommon++;    } return true; }
        if (tier == 1 && countRare      < CAP_RARE)      { unchecked { countRare++;      } return true; }
        if (tier == 2 && countLegendary < CAP_LEGENDARY) { unchecked { countLegendary++; } return true; }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                              FEES
    //////////////////////////////////////////////////////////////*/

    function withdrawFees() external {
        uint256 bal = address(this).balance;
        if (bal == 0) return;
        (bool ok, ) = treasury.call{value: bal}("");
        if (!ok) revert WithdrawFailed();
        emit FeesWithdrawn(treasury, bal);
    }

    /*//////////////////////////////////////////////////////////////
                              READS
    //////////////////////////////////////////////////////////////*/

    function commitmentOf(uint256 tokenId) external view returns (Commitment memory) {
        if (_ownerOf[tokenId] == address(0)) revert NonexistentToken();
        return _commitments[tokenId];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_ownerOf[tokenId] == address(0)) revert NonexistentToken();
        Commitment memory c = _commitments[tokenId];
        return renderer.tokenURI(tokenId, c.tier, c.seed);
    }

    function remainingOf(uint8 tier) external view returns (uint16) {
        if (tier == 0) return CAP_COMMON    - countCommon;
        if (tier == 1) return CAP_RARE      - countRare;
        if (tier == 2) return CAP_LEGENDARY - countLegendary;
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-2981
    //////////////////////////////////////////////////////////////*/

    function royaltyInfo(uint256, uint256 salePrice)
        external view returns (address receiver, uint256 royaltyAmount)
    {
        receiver      = royaltyReceiver;
        royaltyAmount = (salePrice * ROYALTY_BPS) / BPS_DENOM;
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-721 STANDARD
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address owner_) external view returns (uint256) {
        if (owner_ == address(0)) revert TransferToZero();
        return _balanceOf[owner_];
    }

    function ownerOf(uint256 tokenId) public view returns (address o) {
        o = _ownerOf[tokenId];
        if (o == address(0)) revert NonexistentToken();
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        if (msg.sender != o && !_operatorApprovals[o][msg.sender]) revert NotAuthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_ownerOf[tokenId] == address(0)) revert NonexistentToken();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address o, address op) external view returns (bool) {
        return _operatorApprovals[o][op];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert TransferToZero();
        if (_ownerOf[tokenId] != from) revert TransferFromWrong();
        if (
            msg.sender != from
            && !_operatorApprovals[from][msg.sender]
            && _tokenApprovals[tokenId] != msg.sender
        ) revert NotAuthorized();
        unchecked {
            _balanceOf[from] -= 1;
            _balanceOf[to]   += 1;
        }
        _ownerOf[tokenId] = to;
        delete _tokenApprovals[tokenId];
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data)
                returns (bytes4 ret)
            {
                if (ret != IERC721Receiver.onERC721Received.selector) revert UnsafeRecipient();
            } catch {
                revert UnsafeRecipient();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-165
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId
            || interfaceId == type(IERC2981).interfaceId;
    }
}
