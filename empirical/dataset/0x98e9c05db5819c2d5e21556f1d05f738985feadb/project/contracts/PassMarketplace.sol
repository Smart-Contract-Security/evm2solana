// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IForgottenWorldsPassMarket {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isSellable(uint256 passId) external view returns (bool);
    function marketplaceTransfer(
        address from,
        address to,
        uint256 passId
    ) external;
}

interface IFeeShareReceiver {
    function depositMarketplaceFees() external payable;
}

contract PassMarketplace is Ownable, ReentrancyGuard, Pausable {
    IForgottenWorldsPassMarket public passContract;
    IFeeShareReceiver public feeShareReceiver;

    uint256 public constant FEE_BPS = 1500; // 15%
    uint256 public constant BPS_DENOMINATOR = 10000;

    uint256 public maxListingPrice;
    uint256 public transferFee;

    uint256 public collectedFees;

    struct Listing {
        address seller;
        uint256 price;
        bool active;
    }

    mapping(uint256 => Listing) public listings;

    event PassListed(
        uint256 indexed passId,
        address indexed seller,
        uint256 price
    );
    event ListingCancelled(uint256 indexed passId);
    event PassBought(
        uint256 indexed passId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );
    event PassTransferred(
        uint256 indexed passId,
        address indexed from,
        address indexed to,
        uint256 fee
    );
    event MaxListingPriceUpdated(uint256 price);
    event TransferFeeUpdated(uint256 fee);
    event FeeShareReceiverUpdated(address indexed receiver);
    event FeesReceived(address indexed sender, uint256 amount);

    constructor(address _passContract) Ownable(msg.sender) {
        require(_passContract != address(0), "Invalid pass contract");
        passContract = IForgottenWorldsPassMarket(_passContract);
    }

    receive() external payable {
        collectedFees += msg.value;
        emit FeesReceived(msg.sender, msg.value);
    }

    // -------------------------
    // Admin
    // -------------------------

    function setMaxListingPrice(uint256 price) external onlyOwner {
        maxListingPrice = price;
        emit MaxListingPriceUpdated(price);
    }

    function setTransferFee(uint256 fee) external onlyOwner {
        transferFee = fee;
        emit TransferFeeUpdated(fee);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawFees(address payable to) external onlyOwner {
        require(to != address(0), "Invalid receiver");

        uint256 amount = collectedFees;
        collectedFees = 0;

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Withdraw failed");
    }

    function setFeeShareReceiver(address receiver) external onlyOwner {
        require(receiver != address(0), "Invalid receiver");
        feeShareReceiver = IFeeShareReceiver(receiver);
        emit FeeShareReceiverUpdated(receiver);
    }

    // -------------------------
    // Listing
    // -------------------------

    function listPass(uint256 passId, uint256 price) external whenNotPaused {
        require(price > 0, "Invalid price");
        require(
            maxListingPrice == 0 || price <= maxListingPrice,
            "Price too high"
        );
        require(passContract.ownerOf(passId) == msg.sender, "Not pass owner");
        require(passContract.isSellable(passId), "Pass not sellable");

        listings[passId] = Listing({
            seller: msg.sender,
            price: price,
            active: true
        });

        emit PassListed(passId, msg.sender, price);
    }

    function cancelListing(uint256 passId) external {
        Listing memory listing = listings[passId];

        require(listing.active, "Not listed");
        require(listing.seller == msg.sender, "Not seller");

        delete listings[passId];

        emit ListingCancelled(passId);
    }

    function buyPass(uint256 passId) external payable nonReentrant whenNotPaused {
        Listing memory listing = listings[passId];

        require(listing.active, "Not listed");
        require(msg.value == listing.price, "Wrong ETH");
        require(
            passContract.ownerOf(passId) == listing.seller,
            "Seller no longer owns pass"
        );
        require(passContract.isSellable(passId), "Pass not sellable");

        delete listings[passId];

        uint256 fee = (msg.value * FEE_BPS) / BPS_DENOMINATOR;
        uint256 sellerAmount = msg.value - fee;

        if (address(feeShareReceiver) != address(0)) {
            feeShareReceiver.depositMarketplaceFees{value: fee}();
        } else {
            collectedFees += fee;
        }

        passContract.marketplaceTransfer(listing.seller, msg.sender, passId);

        (bool ok, ) = payable(listing.seller).call{value: sellerAmount}("");
        require(ok, "Seller payment failed");

        emit PassBought(passId, msg.sender, listing.seller, msg.value);
    }

    // -------------------------
    // Paid Direct Transfer
    // -------------------------

    function transferPass(
        address to,
        uint256 passId
    ) external payable nonReentrant whenNotPaused {
        require(to != address(0), "Invalid receiver");
        require(msg.value == transferFee, "Wrong transfer fee");
        require(passContract.ownerOf(passId) == msg.sender, "Not pass owner");
        require(passContract.isSellable(passId), "Pass not transferable");

        delete listings[passId];

        collectedFees += msg.value;

        passContract.marketplaceTransfer(msg.sender, to, passId);

        emit PassTransferred(passId, msg.sender, to, msg.value);
    }

    // -------------------------
    // Views
    // -------------------------

    function getListing(
        uint256 passId
    ) external view returns (address seller, uint256 price, bool active) {
        Listing memory listing = listings[passId];
        return (listing.seller, listing.price, listing.active);
    }
}
