// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721A} from "erc721a/contracts/ERC721A.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RektPunkRenderer} from "./RektPunkRenderer.sol";

/// @title RektPunk — fully-onchain 6666 PFP collection (ERC721A)
/// @notice Traits are assigned at mint time using blockhash + prevrandao entropy.
///         SVG is rendered onchain via RektPunkRenderer.
contract RektPunk is ERC721A, Ownable {
    // ---------- Errors ----------
    error MintClosed();
    error FreePhaseClosed();
    error SoldOut();
    error WrongValue();
    error WalletLimit();
    error TxLimit();
    error ZeroQty();
    error AlreadyClaimedFree();

    // ---------- Constants ----------
    uint256 public constant MAX_SUPPLY = 6666;
    uint256 public constant MAX_PER_WALLET = 20;
    uint256 public constant MAX_PER_TX = 20;
    uint256 public constant FREE_PER_WALLET = 1;

    // Bounds per trait (must match renderer / palettes)
    uint8[9] private TRAIT_BOUNDS = [12, 12, 12, 8, 9, 8, 12, 10, 10];

    // ---------- Storage ----------
    RektPunkRenderer public renderer;

    uint256 public mintPrice;
    bool public mintOpen;       // paid phase
    bool public freeMintOpen;   // free phase (must be claimed first by a wallet)

    /// @dev packed traits per token: 9 bytes, each byte = trait index
    mapping(uint256 => bytes9) private _traits;

    /// @dev tracks free claims per wallet (capped at FREE_PER_WALLET)
    mapping(address => uint256) public freeMinted;

    // ---------- Events ----------
    event Minted(address indexed to, uint256 indexed startTokenId, uint256 qty, bool free);
    event MintConfigUpdated(bool open, uint256 price);
    event FreeMintConfigUpdated(bool open);
    event RendererUpdated(address renderer);

    constructor(address renderer_, uint256 mintPrice_)
        ERC721A("Rekt Punks", "REKT")
        Ownable(msg.sender)
    {
        renderer = RektPunkRenderer(renderer_);
        mintPrice = mintPrice_;
    }

    // ---------- ERC721A overrides ----------
    /// @dev Start tokenIds at 1 instead of 0.
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ---------- Admin ----------
    function setMintConfig(bool open, uint256 price) external onlyOwner {
        mintOpen = open;
        mintPrice = price;
        emit MintConfigUpdated(open, price);
    }

    function setFreeMint(bool open) external onlyOwner {
        freeMintOpen = open;
        emit FreeMintConfigUpdated(open);
    }

    function setRenderer(address renderer_) external onlyOwner {
        renderer = RektPunkRenderer(renderer_);
        emit RendererUpdated(renderer_);
    }

    function withdraw(address to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // ---------- Mint ----------
    /// @notice Claim your 1 free RektPunk. Must be called before paid mint per wallet.
    function freeMint() external {
        if (!freeMintOpen) revert FreePhaseClosed();
        if (freeMinted[msg.sender] >= FREE_PER_WALLET) revert AlreadyClaimedFree();
        if (_numberMinted(msg.sender) + 1 > MAX_PER_WALLET) revert WalletLimit();
        if (_totalMinted() + 1 > MAX_SUPPLY) revert SoldOut();

        freeMinted[msg.sender] = FREE_PER_WALLET;

        uint256 tokenId = _nextTokenId();
        _traits[tokenId] = _rollTraits(tokenId, msg.sender);
        _mint(msg.sender, 1);
        emit Minted(msg.sender, tokenId, 1, true);
    }

    /// @notice Paid mint. Wallet must have claimed its free token first (if free phase exists).
    function mint(uint256 qty) external payable {
        if (qty == 0) revert ZeroQty();
        if (qty > MAX_PER_TX) revert TxLimit();
        if (!mintOpen) revert MintClosed();
        if (freeMinted[msg.sender] < FREE_PER_WALLET) revert FreePhaseClosed();
        if (msg.value != mintPrice * qty) revert WrongValue();
        if (_numberMinted(msg.sender) + qty > MAX_PER_WALLET) revert WalletLimit();
        if (_totalMinted() + qty > MAX_SUPPLY) revert SoldOut();

        uint256 startId = _nextTokenId();
        unchecked {
            for (uint256 i = 0; i < qty; i++) {
                uint256 tokenId = startId + i;
                _traits[tokenId] = _rollTraits(tokenId, msg.sender);
            }
        }

        _mint(msg.sender, qty);
        emit Minted(msg.sender, startId, qty, false);
    }

    // ---------- Trait generation ----------
    function _rollTraits(uint256 tokenId, address to) internal view returns (bytes9) {
        uint256 seed = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), to, tokenId, block.prevrandao))
        );
        bytes memory out = new bytes(9);
        for (uint256 i = 0; i < 9; i++) {
            out[i] = bytes1(uint8(seed % TRAIT_BOUNDS[i]));
            seed >>= 8;
            if (i == 3 || i == 6) {
                seed = uint256(keccak256(abi.encodePacked(seed, tokenId, i)));
            }
        }
        return bytes9(out);
    }

    // ---------- Views ----------
    function traitsOf(uint256 tokenId) public view returns (uint8[9] memory out) {
        if (!_exists(tokenId)) revert OwnerQueryForNonexistentToken();
        bytes9 t = _traits[tokenId];
        for (uint256 i = 0; i < 9; i++) {
            out[i] = uint8(t[i]);
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        return renderer.tokenURI(tokenId, traitsOf(tokenId));
    }

    function tokenSVG(uint256 tokenId) external view returns (string memory) {
        return renderer.renderSVG(traitsOf(tokenId));
    }
}
