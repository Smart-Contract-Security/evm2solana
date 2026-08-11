// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MarketPlace
 * @notice On-chain marketplace for the two tradeable Mining ETH assets — Miner
 * NFTs and Check NFTs. Listings may be priced in **either ETH or METH** at the
 * seller's choice. The marketplace escrows the listed NFT until either the
 * seller cancels or a buyer fills the listing. A 5% (default) flat fee on the
 * sale price routes to the treasury; the remainder pays the seller.
 *
 * Soulbound assets (dMETH, Bag NFTs) are out of scope by design — only Miner
 * and Check assets are accepted.
 */
contract MarketPlace is Ownable, ReentrancyGuard {
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //              TYPES
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    enum Currency { ETH, METH }
    enum AssetType { Miner, Check }

    struct Listing {
        address seller;
        AssetType asset;
        Currency currency;
        uint256 tokenId;
        uint256 price;
        uint256 listTime;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            STORAGE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    address public meth;
    address public minerNFT;
    address public checkNFT;
    address public treasury;
    uint256 public cancelCooldown = 1 hours; // cooldown to stop griefing

    /// @dev Fee in basis points. 500 = 5.00%.
    uint16 public feeBps = 500;
    uint16 public constant MAX_FEE_BPS = 2000; // 20% absolute cap

    uint256 public nextListingId = 1;
    mapping(uint256 => Listing) public listings;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            EVENTS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        AssetType asset,
        Currency currency,
        uint256 tokenId,
        uint256 price
    );
    event Bought(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 fee
    );
    event Cancelled(uint256 indexed listingId, address indexed seller);
    event PriceUpdated(uint256 indexed listingId, uint256 newPrice);
    event FeeUpdated(uint16 feeBps);
    event ConfigUpdated(string indexed key, address value);

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            ERRORS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    error ListingNotFound();
    error NotSeller();
    error InsufficientPayment();
    error ETHNotAccepted();
    error InvalidPrice();
    error InvalidFee();
    error ZeroAddress();
    error TransferFailed();
    error NotConfigured();
    error YourListing();
    error CancelCooldown();

    constructor() Ownable(msg.sender) {}

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         USER FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice List a Miner or Check NFT for sale in ETH or METH. The token is
    /// escrowed in this contract — the seller must approve the marketplace
    /// before calling.
    function list(AssetType asset, Currency currency, uint256 tokenId, uint256 price)
        external
        nonReentrant
        returns (uint256 listingId)
    {
        if (price == 0) revert InvalidPrice();
        address nftAddr = _nftAddress(asset);
        if (nftAddr == address(0)) revert NotConfigured();
        if (currency == Currency.METH && meth == address(0)) revert NotConfigured();

        listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            asset: asset,
            currency: currency,
            tokenId: tokenId,
            price: price,
            listTime: block.timestamp
        });

        IERC721(nftAddr).transferFrom(msg.sender, address(this), tokenId);

        emit Listed(listingId, msg.sender, asset, currency, tokenId, price);
    }

    /// @notice Buy a listed asset. ETH listings require msg.value >= price;
    /// METH listings pull via transferFrom and require msg.value == 0.
    function buy(uint256 listingId) external payable nonReentrant {
        Listing memory l = listings[listingId];
        if (l.seller == address(0)) revert ListingNotFound();
        if (l.seller == msg.sender) revert YourListing();

        uint256 fee = (l.price * feeBps) / 10000;
        uint256 sellerCut = l.price - fee;

        // Effects: clear before external interactions.
        delete listings[listingId];

        if (l.currency == Currency.ETH) {
            if (msg.value < l.price) revert InsufficientPayment();

            // Refund overpayment.
            if (msg.value > l.price) {
                (bool refund, ) = payable(msg.sender).call{value: msg.value - l.price}("");
                if (!refund) revert TransferFailed();
            }
            (bool ok, ) = payable(l.seller).call{value: sellerCut}("");
            if (!ok) revert TransferFailed();
            if (fee > 0) {
                if (treasury == address(0)) revert NotConfigured();
                (bool okFee, ) = payable(treasury).call{value: fee}("");
                if (!okFee) revert TransferFailed();
            }
        } else {
            if (msg.value != 0) revert ETHNotAccepted();
            // METH pulls from buyer.
            require(IERC20(meth).transferFrom(msg.sender, l.seller, sellerCut), "METH seller xfer");
            if (fee > 0) {
                if (treasury == address(0)) revert NotConfigured();
                require(IERC20(meth).transferFrom(msg.sender, treasury, fee), "METH fee xfer");
            }
        }

        IERC721(_nftAddress(l.asset)).transferFrom(address(this), msg.sender, l.tokenId);

        emit Bought(listingId, msg.sender, l.seller, l.price, fee);
    }

    /// @notice Cancel an active listing. Only the seller may cancel. The NFT
    /// is returned to the seller.
    function cancel(uint256 listingId) external nonReentrant {
        Listing memory l = listings[listingId];
        if (l.seller == address(0)) revert ListingNotFound();
        if (l.seller != msg.sender) revert NotSeller();
        if (block.timestamp < l.listTime + cancelCooldown) revert CancelCooldown();

        delete listings[listingId];
        IERC721(_nftAddress(l.asset)).transferFrom(address(this), msg.sender, l.tokenId);

        emit Cancelled(listingId, msg.sender);
    }

    /// @notice Update the asking price on an existing listing (same currency).
    function updatePrice(uint256 listingId, uint256 newPrice) external {
        Listing storage l = listings[listingId];
        if (l.seller == address(0)) revert ListingNotFound();
        if (l.seller != msg.sender) revert NotSeller();
        if (newPrice == 0) revert InvalidPrice();
        l.price = newPrice;
        emit PriceUpdated(listingId, newPrice);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         VIEW FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function _nftAddress(AssetType asset) internal view returns (address) {
        if (asset == AssetType.Miner) return minerNFT;
        return checkNFT;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        ADMIN FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function setFee(uint16 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert InvalidFee();
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function setMeth(address _meth) external onlyOwner {
        if (_meth == address(0)) revert ZeroAddress();
        meth = _meth;
        emit ConfigUpdated("meth", _meth);
    }

    function setMinerNFT(address _minerNFT) external onlyOwner {
        if (_minerNFT == address(0)) revert ZeroAddress();
        minerNFT = _minerNFT;
        emit ConfigUpdated("minerNFT", _minerNFT);
    }

    function setCheckNFT(address _checkNFT) external onlyOwner {
        if (_checkNFT == address(0)) revert ZeroAddress();
        checkNFT = _checkNFT;
        emit ConfigUpdated("checkNFT", _checkNFT);
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit ConfigUpdated("treasury", _treasury);
    }

    /// @dev Accept inbound transferFrom (non-safe variant doesn't trigger this,
    /// but safeTransferFrom from external callers will — accept it).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
