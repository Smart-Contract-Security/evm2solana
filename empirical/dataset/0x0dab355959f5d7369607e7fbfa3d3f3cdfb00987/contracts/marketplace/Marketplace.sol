// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IBaseERC721} from "../interface/IBaseERC721.sol";
import {IBaseERC1155} from "../interface/IBaseERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "../base/TreasuryManager.sol";

import "./errors/MarketplaceError.sol";
import "./events/MarketplaceEvents.sol";

/**
 * @title TCGMarketplace
 * @dev A marketplace contract for ERC721 and ERC1155 tokens, supporting both fixed-price listings and auctions.
 * The contract is upgradeable via UUPS and includes role-based access control for management functions.
 */
contract TCGMarketplace is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ERC1155HolderUpgradeable,
    MarketplaceEvents
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using Address for address payable;
    using SafeERC20 for IERC20;

    /// @notice Role identifier for accounts allowed to upgrade the contract.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role identifier for accounts allowed to manage the contract's settings.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Enumeration representing the types of tokens supported by the marketplace.
    enum TokenType {
        ERC721,
        ERC1155
    }

    /// @notice Enumeration representing the types of listings supported by the marketplace.
    enum ListingType {
        FixedPrice,
        Auction
    }

    /// @notice Enumeration representing the status of listings.
    enum ListingStatus {
        None,
        Active,
        Ended,
        Cancelled,
        Sold
    }

    /// @notice Struct representing a listing in the marketplace.
    struct Listing {
        bytes32 listingId;
        uint256 tokenId;
        address tokenAddress;
        uint256 amount;
        uint256 price;
        address paymentToken;
        address seller;
        uint8 listingType;
        uint64 listingEndTime;
    }

    /// @notice The fee in basis points charged on sales (e.g., 100 = 1%).
    // uint256 public feeBasisPoints;

    // /// @notice The period in seconds within which the winning bidder can claim the auctioned item.
    // uint256 public claimPeriod;

    /// @notice A set of whitelisted payment tokens.
    EnumerableSet.AddressSet private _whitelistedPaymentTokens;

    /// @notice A set of whitelisted tokens that can be listed on the marketplace.
    EnumerableSet.AddressSet private _whitelistedTokens;

    /// @notice The address that receives the marketplace fees.
    address public taxReceiver;

    // TreasuryManager instance for handling royalty fee swaps.
    TreasuryManager public treasuryManager;

    /// @notice Flag indicating whether native tokens (e.g., ETH) are allowed as payment.
    bool public allowNativeToken;

    /// @notice Flag indicating whether royalty is enabled.
    bool public enableRoyalty;

    /// @notice Flag indicating whether royalty is enabled.
    uint64 public listingCancelCooldown;

    address public unitTokenAddress;

    IUniswapV2Router02 public lpRouter;

    bool public autoSwapEnabled;

    /// @dev Mapping from listingId to the corresponding listing.
    mapping(bytes32 => Listing) private _listings;

    /// @dev Mapping to track the end time for claiming auctioned items.
    mapping(bytes32 => uint256) private _claimEndTimes;

    /// @dev Mapping to track the highest bidders in auctions.
    mapping(bytes32 => address) private _highestBidders;

    /// @dev Mapping to track the highest bids in auctions.
    mapping(bytes32 => uint256) private _highestBids;

    /// @dev Mapping to track the user bids in auctions.
    mapping(bytes32 => mapping(address => uint256)) private _userBids;

    // /// @dev Mapping to track the user bids in payment tokens.
    mapping(bytes32 => address) private _auctionPaymentToken;

    /// @dev Mapping to track the listing timestamp.
    mapping(bytes32 => uint64) private _listingTimestamps;

    /// @dev Mapping to track listing status.
    mapping(bytes32 => uint8) private _listingStatus;

    // /// @dev Mapping to track the user's participated auctions.
    mapping(address => EnumerableSet.Bytes32Set) private _userAuctions;

    // /// @dev Mapping to track the auctions' target bid.
    mapping(bytes32 => uint256) private _targetBids;

    // /// @dev Mapping to track the auctions' starting bid.
    mapping(bytes32 => uint256) private _startingBids;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the marketplace contract with initial settings.
     * @param _upgrader The address to assign the UPGRADER_ROLE.
     * @param _manager The address to assign the MANAGER_ROLE.
     * @param _taxReceiver The address to receive marketplace fees.
     * @param _allowNativeToken Flag indicating whether native tokens (e.g., ETH) are allowed as payment.
     * @dev Reverts with `ErrorAddressZero` if any of the addresses are the zero address.
     */
    function initialize(
        // uint256 _initialFeeBasisPoints,
        // uint256 _initialClaimPeriod,
        address _upgrader,
        address _manager,
        address _taxReceiver,
        bool _allowNativeToken,
        bool _enableRoyalty,
        uint64 _listingCancelCooldown,
        bool _autoSwapEnabled
    ) public initializer {
        if (
            _upgrader == address(0) ||
            _manager == address(0) ||
            _taxReceiver == address(0)
        ) {
            revert ErrorAddressZero();
        }
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, _upgrader);
        _grantRole(MANAGER_ROLE, _manager);

        // feeBasisPoints = _initialFeeBasisPoints;
        // claimPeriod = _initialClaimPeriod;
        taxReceiver = _taxReceiver;
        allowNativeToken = _allowNativeToken;
        enableRoyalty = _enableRoyalty;
        listingCancelCooldown = _listingCancelCooldown;
        autoSwapEnabled = _autoSwapEnabled;
    }

    /**
     * @dev Modifier to restrict operations to only whitelisted tokens.
     * Reverts with `ErrorTokenNotWhitelisted` if the token is not whitelisted.
     * @param _tokenAddress The address of the token to check.
     */
    modifier onlyWhitelistedToken(address _tokenAddress) {
        if (!_whitelistedTokens.contains(_tokenAddress)) {
            revert ErrorTokenNotWhitelisted(_tokenAddress);
        }
        _;
    }

    /**
     * @dev Modifier to restrict operations to only whitelisted payment tokens.
     * Reverts with `ErrorPaymentTokenNotWhitelisted` or `ErrorNativePaymentTokenNotAllowed` as appropriate.
     * @param _paymentToken The address of the payment token to check.
     */
    modifier onlyWhitelistedPaymentToken(address _paymentToken) {
        if (
            _paymentToken != address(0) &&
            !_whitelistedPaymentTokens.contains(_paymentToken)
        ) {
            revert ErrorPaymentTokenNotWhitelisted(_paymentToken);
        }
        if (_paymentToken == address(0) && !allowNativeToken) {
            revert ErrorNativePaymentTokenNotAllowed();
        }
        _;
    }

    /**
     * @dev Modifier to restrict operations to only active listings.
     * Reverts with `ErrorListingNotActive` if the listing is not active.
     * @param _listingId The id of the listing.
     */
    modifier onlyActiveListing(bytes32 _listingId) {
        if (_listingStatus[_listingId] != uint8(ListingStatus.Active)) {
            revert ErrorListingNotActive(_listingId);
        }
        _;
    }

    /**
     * @dev Modifier to restrict operations to only claimble listings.
     * Reverts with `ErrorAuctionNotClaimable` if the listing is not active.
     * @param _listingId The id of the listing.
     */
    modifier onlyClaimable(bytes32 _listingId) {
        if (
            _listingStatus[_listingId] != uint8(ListingStatus.Cancelled) &&
            _listingStatus[_listingId] != uint8(ListingStatus.Ended)
        ) {
            revert ErrorAuctionNotClaimable(_listingId);
        }
        _;
    }

    /**
     * @dev Modifier to ensure that a valid price is provided.
     * Reverts with `ErrorInvalidPrice` if the price is zero.
     * @param price The price to check.
     */
    modifier validPrice(uint256 price) {
        if (price == 0) {
            revert ErrorInvalidPrice();
        }
        _;
    }

    /**
     * @dev Modifier to ensure that a valid amount is provided.
     * Reverts with `ErrorInvalidAmount` if the amount is zero.
     * @param amount The amount to check.
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert ErrorInvalidAmount();
        }
        _;
    }

    /**
     * @notice Adds a token to the whitelist.
     * @param tokenAddress The address of the token to add.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function addToken(address tokenAddress) external onlyRole(MANAGER_ROLE) {
        if (!_whitelistedTokens.contains(tokenAddress)) {
            _whitelistedTokens.add(tokenAddress);
        }
        emit TokenAdded(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Adds multiple tokens to the whitelist in bulk.
     * @param tokenAddress An array of token addresses to add.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function bulkAddToken(
        address[] calldata tokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        for (uint256 i; i < tokenAddress.length; ++i) {
            if (!_whitelistedTokens.contains(tokenAddress[i])) {
                _whitelistedTokens.add(tokenAddress[i]);
            }
        }
        emit BulkTokenAdded(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Removes a token from the whitelist.
     * @param tokenAddress The address of the token to remove.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function removeToken(address tokenAddress) external onlyRole(MANAGER_ROLE) {
        if (_whitelistedTokens.contains(tokenAddress)) {
            _whitelistedTokens.remove(tokenAddress);
        }
        emit TokenRemoved(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Removes multiple tokens from the whitelist in bulk.
     * @param tokenAddress An array of token addresses to remove.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function bulkRemoveToken(
        address[] calldata tokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        for (uint256 i; i < tokenAddress.length; ++i) {
            if (_whitelistedTokens.contains(tokenAddress[i])) {
                _whitelistedTokens.remove(tokenAddress[i]);
            }
        }
        emit BulkTokenRemoved(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Adds a payment token to the whitelist.
     * @param tokenAddress The address of the payment token to add.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function addPaymentToken(
        address tokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        if (!_whitelistedPaymentTokens.contains(tokenAddress)) {
            _whitelistedPaymentTokens.add(tokenAddress);
        }
        emit PaymentTokenAdded(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Adds multiple payment tokens to the whitelist in bulk.
     * @param tokenAddress An array of payment token addresses to add.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function bulkAddPaymentToken(
        address[] calldata tokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        for (uint256 i; i < tokenAddress.length; ++i) {
            if (!_whitelistedPaymentTokens.contains(tokenAddress[i])) {
                _whitelistedPaymentTokens.add(tokenAddress[i]);
            }
        }
        emit BulkPaymentTokenAdded(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Removes a payment token from the whitelist.
     * @param tokenAddress The address of the payment token to remove.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function removePaymentToken(
        address tokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        if (_whitelistedPaymentTokens.contains(tokenAddress)) {
            _whitelistedPaymentTokens.remove(tokenAddress);
        }
        emit PaymentTokenRemoved(tokenAddress, uint64(block.timestamp));
    }

    /**
     * @notice Removes multiple payment tokens from the whitelist in bulk.
     * @param tokenAddress An array of payment token addresses to remove.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function bulkRemovePaymentToken(
        address[] calldata tokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        for (uint256 i; i < tokenAddress.length; ++i) {
            if (_whitelistedPaymentTokens.contains(tokenAddress[i])) {
                _whitelistedPaymentTokens.remove(tokenAddress[i]);
            }
        }
        emit BulkPaymentTokenRemoved(tokenAddress, uint64(block.timestamp));
    }

    // /**
    //  * @notice Updates the fee basis points for marketplace transactions.
    //  * @param newFeeBasisPoints The new fee basis points (e.g., 100 = 1%).
    //  * @dev Only callable by accounts with the MANAGER_ROLE.
    //  */
    // function setFeeBasisPoints(
    //     uint256 newFeeBasisPoints
    // ) external onlyRole(MANAGER_ROLE) {
    //     if (newFeeBasisPoints == 0 || newFeeBasisPoints > 10000) {
    //         revert ErrorInvalidFeeBasisPoints();
    //     }
    //     feeBasisPoints = newFeeBasisPoints;
    //     emit FeeUpdated(newFeeBasisPoints);
    // }

    // /**
    //  * @notice Updates the claim period for auctions.
    //  * @param newClaimPeriod The new claim period in seconds.
    //  * @dev Only callable by accounts with the MANAGER_ROLE.
    //  */
    // function setClaimPeriod(
    //     uint256 newClaimPeriod
    // ) external onlyRole(MANAGER_ROLE) {
    //     if (claimPeriod == 0) {
    //         revert ErrorInvalidClaimPeriod();
    //     }
    //     claimPeriod = newClaimPeriod;
    //     emit ClaimPeriodUpdated(newClaimPeriod);
    // }

    /**
     * @notice Updates the tax receiver address.
     * @param _taxReceiver The new tax receiver address.
     * @dev Reverts with `ErrorInvalidAddress` if the address is invalid.
     * Only callable by accounts with the MANAGER_ROLE.
     */
    function setTaxReceiver(
        address _taxReceiver
    ) external onlyRole(MANAGER_ROLE) {
        if (_taxReceiver == address(0)) {
            revert ErrorInvalidAddress();
        }
        taxReceiver = _taxReceiver;
        emit TaxReceiverUpdated(_taxReceiver);
    }

    /**
     * @notice Creates a new fixed listing in the marketplace.
     * @param tokenAddress The address of the token to list.
     * @param tokenId The ID of the token to list.
     * @param amount The amount of the token to list (for ERC1155).
     * @param price The price of the listing.
     * @param paymentToken The address of the payment token.
     * @param duration The duration of the auction.
     * @dev Reverts with `ErrorInvalidTokenType`, `ErrorTokenNotWhitelisted`, `ErrorPaymentTokenNotWhitelisted`, `ErrorNativePaymentTokenNotAllowed`, `ErrorInvalidPrice`, or `ErrorInvalidAmount` as appropriate.
     * Only callable by accounts with valid roles.
     */
    function createFixedListing(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        address paymentToken,
        uint64 duration
    )
        external
        onlyWhitelistedToken(tokenAddress)
        onlyWhitelistedPaymentToken(paymentToken)
        validPrice(price)
        validAmount(amount)
        nonReentrant
    {
        uint8 tokenType = _getTokenType(tokenAddress);
        if (tokenType == uint8(TokenType.ERC721)) {
            IBaseERC721(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        } else if (tokenType == uint8(TokenType.ERC1155)) {
            IBaseERC1155(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                amount,
                ""
            );
        }
        if (duration == 0) {
            revert ErrorInvalidListingDuration();
        }

        uint64 listingEndTime = uint64(block.timestamp + duration);
        uint8 listingType = uint8(ListingType.FixedPrice);
        bytes32 listingId = keccak256(
            abi.encodePacked(
                amount,
                price,
                paymentToken,
                msg.sender,
                tokenAddress,
                tokenId,
                listingType
            )
        );

        _listings[listingId] = Listing(
            listingId,
            tokenId,
            tokenAddress,
            amount,
            price,
            paymentToken,
            msg.sender,
            listingType,
            listingEndTime
        );

        _listingTimestamps[listingId] = uint64(block.timestamp);
        _listingStatus[listingId] = uint8(ListingStatus.Active);

        emit ListingCreated(
            listingId,
            tokenId,
            msg.sender,
            tokenAddress,
            paymentToken,
            amount,
            price,
            tokenType,
            listingType,
            listingEndTime,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Creates a new auction listing in the marketplace.
     * @param tokenAddress The address of the token to list.
     * @param tokenId The ID of the token to list.
     * @param amount The amount of the token to list (for ERC1155).
     * @param startingBid The starting bid of the auction.
     * @param targetBid The target bid of the auction.
     * @param buyoutPrice The buyout price of the auction.
     * @param paymentToken The address of the payment token.
     * @param duration The duration of the auction.
     * @dev Reverts with `ErrorInvalidTokenType`, `ErrorTokenNotWhitelisted`, `ErrorPaymentTokenNotWhitelisted`, `ErrorNativePaymentTokenNotAllowed`, `ErrorInvalidPrice`, or `ErrorInvalidAmount` as appropriate.
     * Only callable by accounts with valid roles.
     */
    function createAuctionListing(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 startingBid,
        uint256 targetBid,
        uint256 buyoutPrice,
        address paymentToken,
        uint64 duration
    )
        external
        onlyWhitelistedToken(tokenAddress)
        onlyWhitelistedPaymentToken(paymentToken)
        validAmount(amount)
        nonReentrant
    {
        uint8 tokenType = _getTokenType(tokenAddress);
        if (tokenType == uint8(TokenType.ERC721)) {
            IBaseERC721(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        } else if (tokenType == uint8(TokenType.ERC1155)) {
            IBaseERC1155(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                amount,
                ""
            );
        }
        if (duration == 0) {
            revert ErrorInvalidListingDuration();
        }

        uint64 listingEndTime = uint64(block.timestamp + duration);
        uint8 listingType = uint8(ListingType.Auction);
        bytes32 listingId = keccak256(
            abi.encodePacked(
                amount,
                buyoutPrice,
                paymentToken,
                msg.sender,
                tokenAddress,
                tokenId,
                listingType
            )
        );

        _listings[listingId] = Listing(
            listingId,
            tokenId,
            tokenAddress,
            amount,
            buyoutPrice,
            paymentToken,
            msg.sender,
            listingType,
            listingEndTime
        );

        _listingTimestamps[listingId] = uint64(block.timestamp);
        _listingStatus[listingId] = uint8(ListingStatus.Active);
        _startingBids[listingId] = startingBid;
        _targetBids[listingId] = targetBid;

        emit ListingCreated(
            listingId,
            tokenId,
            msg.sender,
            tokenAddress,
            paymentToken,
            amount,
            buyoutPrice,
            tokenType,
            listingType,
            listingEndTime,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Cancels an active fixed listing.
     * @param _listingId The id of the listing.
     * @dev Reverts with `ErrorCallerNotSeller` if the caller is not the seller.
     * @dev Reverts with `ErrorListingIsLocked` if the seller is trying to cancel locked listing.
     * Only callable by the seller of the listing.
     */
    function cancelListing(
        bytes32 _listingId
    ) external onlyActiveListing(_listingId) nonReentrant {
        Listing memory listing = _listings[_listingId];
        if (listing.seller != msg.sender) {
            revert ErrorCallerNotSeller(msg.sender, _listingId);
        }

        // locked for 15 mins
        if (
            _listingTimestamps[_listingId] + listingCancelCooldown >
            uint64(block.timestamp)
        ) {
            revert ErrorListingIsLocked();
        }

        if (listing.listingType == uint8(ListingType.Auction)) {
            if (_highestBids[_listingId] >= _targetBids[_listingId]) {
                revert ErrorCannotCancelAuction();
            }
        }

        uint8 tokenType = _getTokenType(listing.tokenAddress);

        if (tokenType == uint8(TokenType.ERC721)) {
            IBaseERC721(listing.tokenAddress).safeTransferFrom(
                address(this),
                listing.seller,
                listing.tokenId
            );
        } else if (tokenType == uint8(TokenType.ERC1155)) {
            IBaseERC1155(listing.tokenAddress).safeTransferFrom(
                address(this),
                listing.seller,
                listing.tokenId,
                listing.amount,
                ""
            );
        }

        delete _listings[_listingId];

        if (listing.listingType == uint8(ListingType.Auction)) {
            delete _highestBidders[_listingId];
            delete _highestBids[_listingId];
            delete _targetBids[_listingId];
            delete _startingBids[_listingId];
        }
        _listingStatus[_listingId] = uint8(ListingStatus.Cancelled);

        emit ListingCancelled(
            _listingId,
            listing.tokenId,
            listing.tokenAddress,
            listing.seller,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Purchases a token from an active fixed-price listing.
     * @param _listingId The id of the listing.
     * @dev Reverts with `ErrorInvalidPrice` or `ErrorCallerNotEnoughBalance` as appropriate.
     * Only callable by accounts with sufficient balance and approvals.
     */
    function buy(
        bytes32 _listingId
    ) external payable onlyActiveListing(_listingId) nonReentrant {
        Listing memory listing = _listings[_listingId];
        if (
            listing.listingType == uint8(ListingType.Auction) &&
            listing.price == 0
        ) {
            revert ErrorNoBuyoutPrice(_listingId);
        }
        uint256 royaltyFee;
        address royaltyRecipient;

        if (enableRoyalty) {
            try
                IERC2981(listing.tokenAddress).royaltyInfo(
                    listing.tokenId,
                    listing.price
                )
            returns (address royaltyFeeRecipient, uint256 royaltyFeeAmount) {
                if (
                    royaltyFeeRecipient != address(0) && royaltyFeeAmount != 0
                ) {
                    royaltyFee = royaltyFeeAmount;
                    royaltyRecipient = royaltyFeeRecipient;
                }
            } catch {}
        }

        uint8 tokenType = _getTokenType(listing.tokenAddress);
        if (listing.paymentToken == address(0)) {
            if (msg.value != listing.price) {
                revert ErrorInvalidPrice();
            }
            // uint256 fee = (msg.value * feeBasisPoints) / 10000;
            // payable(listing.seller).transfer(msg.value - fee - royaltyFee);
            payable(listing.seller).transfer(msg.value - royaltyFee);
            // payable(taxReceiver).transfer(fee);
            if (royaltyFee != 0) {
                payable(royaltyRecipient).transfer(royaltyFee);
            }
        } else {
            IERC20 paymentToken = IERC20(listing.paymentToken);
            if (paymentToken.balanceOf(msg.sender) < listing.price) {
                revert ErrorCallerNotEnoughBalance(
                    msg.sender,
                    listing.paymentToken,
                    listing.price,
                    paymentToken.balanceOf(msg.sender)
                );
            }
            // uint256 fee = (listing.price * feeBasisPoints) / 10000;
            // paymentToken.safeTransferFrom(
            //     msg.sender,
            //     listing.seller,
            //     listing.price - fee - royaltyFee
            // );
            paymentToken.safeTransferFrom(
                msg.sender,
                listing.seller,
                listing.price - royaltyFee
            );
            // paymentToken.safeTransferFrom(msg.sender, taxReceiver, fee);
            if (royaltyFee != 0) {
                if (
                    listing.paymentToken == unitTokenAddress &&
                    address(lpRouter) != address(0) &&
                    unitTokenAddress != address(0) &&
                    address(treasuryManager) != address(0) &&
                    autoSwapEnabled
                ) {
                    paymentToken.safeTransferFrom(
                        msg.sender,
                        address(treasuryManager),
                        royaltyFee
                    );
                    treasuryManager.swapTax(
                        royaltyRecipient,
                        royaltyFee
                    );
                } else {
                    paymentToken.safeTransferFrom(
                        msg.sender,
                        royaltyRecipient,
                        royaltyFee
                    );
                }
            }
        }

        if (tokenType == uint8(TokenType.ERC721)) {
            IBaseERC721(listing.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId
            );
        } else if (tokenType == uint8(TokenType.ERC1155)) {
            IBaseERC1155(listing.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId,
                listing.amount,
                ""
            );
        }

        delete _listings[_listingId];
        _listingStatus[_listingId] = uint8(ListingStatus.Sold);

        emit ListingSold(
            _listingId,
            listing.tokenId,
            listing.seller,
            listing.tokenAddress,
            listing.paymentToken,
            msg.sender,
            listing.amount,
            listing.price,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Places a bid on an active auction listing.
     * @param _listingId The id of the listing.
     * @param bidAmount The amount of the bid.
     * @dev Reverts with `ErrorListingNotAuction`, `ErrorAuctionEnded`, `ErrorBidTooLow`, `ErrorCallerNotEnoughBalance` as appropriate.
     * Only callable by accounts with sufficient balance.
     */
    function placeBid(
        bytes32 _listingId,
        uint256 bidAmount
    ) external payable onlyActiveListing(_listingId) nonReentrant {
        Listing memory listing = _listings[_listingId];
        if (listing.listingType != uint8(ListingType.Auction)) {
            revert ErrorListingNotAuction(_listingId);
        }
        if (block.timestamp >= listing.listingEndTime) {
            revert ErrorAuctionEnded(_listingId);
        }
        if (
            _highestBids[_listingId] >= bidAmount ||
            _startingBids[_listingId] > bidAmount
        ) {
            revert ErrorBidTooLow(_listingId, bidAmount);
        }
        uint256 newBidAmount = bidAmount - _userBids[_listingId][msg.sender];
        if (listing.paymentToken == address(0)) {
            if (msg.value < newBidAmount) {
                revert ErrorCallerNotEnoughBalance(
                    msg.sender,
                    address(0),
                    newBidAmount,
                    msg.value
                );
            }
        } else {
            IERC20 paymentToken = IERC20(listing.paymentToken);
            if (paymentToken.balanceOf(msg.sender) < newBidAmount) {
                revert ErrorCallerNotEnoughBalance(
                    msg.sender,
                    listing.paymentToken,
                    newBidAmount,
                    paymentToken.balanceOf(msg.sender)
                );
            }
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                newBidAmount
            );
        }
        if (!_userAuctions[msg.sender].contains(_listingId)) {
            _userAuctions[msg.sender].add(_listingId);
        }
        _userBids[_listingId][msg.sender] = bidAmount;
        _highestBidders[_listingId] = msg.sender;
        _highestBids[_listingId] = _userBids[_listingId][msg.sender];

        emit BidPlaced(
            _listingId,
            listing.tokenId,
            listing.tokenAddress,
            msg.sender,
            bidAmount,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Ends an auction and marks the listing as claimable.
     * @param _listingId The id of the listing.
     * @dev Reverts with `ErrorlistingEndTimeNotMet` if the listing end time has not been met.
     * Only callable by accounts with the MANAGER_ROLE.
     */
    function endAuction(
        bytes32 _listingId
    )
        external
        onlyRole(MANAGER_ROLE)
        onlyActiveListing(_listingId)
        nonReentrant
    {
        Listing memory listing = _listings[_listingId];
        if (listing.listingType != uint8(ListingType.Auction)) {
            revert ErrorListingNotAuction(_listingId);
        }
        if (block.timestamp < listing.listingEndTime) {
            revert ErrorlistingEndTimeNotMet(_listingId);
        }

        address highestBidder = _highestBidders[_listingId];
        uint256 highestBid = _highestBids[_listingId];
        uint256 targetBid = _targetBids[_listingId];
        uint8 tokenType = _getTokenType(listing.tokenAddress);

        if (highestBid >= targetBid) {
            // uint256 fee = (highestBid * feeBasisPoints) / 10000;
            // uint256 payout = highestBid - fee;

            uint256 royaltyFee;
            address royaltyRecipient;

            if (enableRoyalty) {
                try
                    IERC2981(listing.tokenAddress).royaltyInfo(
                        listing.tokenId,
                        listing.price
                    )
                returns (
                    address royaltyFeeRecipient,
                    uint256 royaltyFeeAmount
                ) {
                    if (
                        royaltyFeeRecipient != address(0) &&
                        royaltyFeeAmount != 0
                    ) {
                        royaltyFee = royaltyFeeAmount;
                        royaltyRecipient = royaltyFeeRecipient;
                    }
                } catch {}
            }

            if (listing.paymentToken == address(0)) {
                payable(listing.seller).transfer(highestBid - royaltyFee);
                // payable(taxReceiver).transfer(fee);
                if (royaltyFee != 0) {
                    payable(royaltyRecipient).transfer(royaltyFee);
                }
            } else {
                IERC20 paymentToken = IERC20(listing.paymentToken);
                paymentToken.safeTransfer(
                    listing.seller,
                    highestBid - royaltyFee
                );
                // paymentToken.safeTransfer(taxReceiver, fee);
                if (royaltyFee != 0) {
                    if (
                        listing.paymentToken == unitTokenAddress &&
                        address(lpRouter) != address(0) &&
                        unitTokenAddress != address(0) &&
                        autoSwapEnabled
                    ) {
                        paymentToken.safeTransfer(
                            address(treasuryManager),
                            royaltyFee
                        );
                        treasuryManager.swapTax(
                            royaltyRecipient,
                            royaltyFee
                        );
                    } else {
                        paymentToken.safeTransfer(address(treasuryManager), royaltyFee);
                    }
                }
            }

            if (tokenType == uint8(TokenType.ERC721)) {
                IBaseERC721(listing.tokenAddress).safeTransferFrom(
                    address(this),
                    highestBidder,
                    listing.tokenId
                );
            } else if (tokenType == uint8(TokenType.ERC1155)) {
                IBaseERC1155(listing.tokenAddress).safeTransferFrom(
                    address(this),
                    highestBidder,
                    listing.tokenId,
                    listing.amount,
                    ""
                );
            }
            delete _userBids[_listingId][highestBidder];
            _userAuctions[highestBidder].remove(_listingId);
        } else {
            if (tokenType == uint8(TokenType.ERC721)) {
                IBaseERC721(listing.tokenAddress).safeTransferFrom(
                    address(this),
                    listing.seller,
                    listing.tokenId
                );
            } else if (tokenType == uint8(TokenType.ERC1155)) {
                IBaseERC1155(listing.tokenAddress).safeTransferFrom(
                    address(this),
                    listing.seller,
                    listing.tokenId,
                    listing.amount,
                    ""
                );
            }
        }

        delete _listings[_listingId];
        delete _highestBidders[_listingId];
        delete _highestBids[_listingId];
        delete _targetBids[_listingId];
        delete _startingBids[_listingId];

        _listingStatus[_listingId] = uint8(ListingStatus.Ended);
        _auctionPaymentToken[_listingId] = listing.paymentToken;

        if (highestBid >= targetBid) {
            emit AuctionEnded(
                _listingId,
                listing.tokenId,
                listing.tokenAddress,
                highestBidder,
                highestBid,
                uint64(block.timestamp)
            );
        } else {
            emit AuctionEnded(
                _listingId,
                listing.tokenId,
                listing.tokenAddress,
                address(0),
                0,
                uint64(block.timestamp)
            );
        }
    }

    /**
     * @notice Cancels an unclaimed auction after the claim period has ended.
     * @param _listingId The id of the listing.
     * @dev Reverts with `ErrorAuctionNotClaimable`, `ErrorClaimPeriodNotOver` as appropriate.
     * Only callable by the seller after the claim period has ended.
     */
    function claimBid(
        bytes32 _listingId
    ) external onlyClaimable(_listingId) nonReentrant {
        if (!_userAuctions[msg.sender].contains(_listingId)) {
            revert ErrorNoUserBid(_listingId);
        }
        address paymentToken = _auctionPaymentToken[_listingId];
        uint256 bidAmount = _userBids[_listingId][msg.sender];

        if (paymentToken == address(0)) {
            payable(msg.sender).transfer(bidAmount);
        } else {
            IERC20(paymentToken).safeTransfer(msg.sender, bidAmount);
        }
        _userAuctions[msg.sender].remove(_listingId);
        delete _userBids[_listingId][msg.sender];

        emit BidClaimed(
            _listingId,
            msg.sender,
            paymentToken,
            bidAmount,
            uint64(block.timestamp)
        );
    }

    /**
     * @notice Gets the details of a listing.
     * @param _listingId The id of the listing.
     * @return The listing details.
     */
    function getListing(
        bytes32 _listingId
    ) external view returns (Listing memory) {
        return _listings[_listingId];
    }

    /**
     * @notice Gets the highest bid and bidder information for a token.
     * @param _listingId The id of the listing.
     * @return The highest bidder and highest bid amount.
     */
    function getHighestBidInfo(
        bytes32 _listingId
    ) external view returns (address, uint256) {
        return (_highestBidders[_listingId], _highestBids[_listingId]);
    }

    /**
     * @notice Gets the claim end time for an auctioned token.
     * @param _listingId The id of the listing.
     * @return The claim end time in seconds.
     */
    function getClaimEndTime(
        bytes32 _listingId
    ) external view returns (uint256) {
        return _claimEndTimes[_listingId];
    }

    /**
     * @notice Gets the target bid of an auction.
     * @param _listingId The id of the listing.
     * @return The target bid in uint256
     */
    function getTargetBid(bytes32 _listingId) external view returns (uint256) {
        return _targetBids[_listingId];
    }

    /**
     * @notice Gets the starting bid of an auction.
     * @param _listingId The id of the listing.
     * @return The starting bid in uint256
     */
    function getStartingBid(
        bytes32 _listingId
    ) external view returns (uint256) {
        return _startingBids[_listingId];
    }

    /**
     * @notice Checks if listing is claimable.
     * @param _listingId The id of the listing.
     * @return Boolean if its claimble or not
     */
    function isClaimable(bytes32 _listingId) external view returns (bool) {
        return
            _listingStatus[_listingId] == uint8(ListingStatus.Cancelled) ||
            _listingStatus[_listingId] == uint8(ListingStatus.Ended);
    }

    /**
     * @notice Checks if a token is whitelisted.
     * @param tokenAddress The address of the token.
     * @return True if the token is whitelisted, otherwise false.
     */
    function whitelistedTokens(
        address tokenAddress
    ) external view returns (bool) {
        return _whitelistedTokens.contains(tokenAddress);
    }

    /**
     * @notice Checks if a payment token is whitelisted.
     * @param paymentTokenAddress The address of the payment token.
     * @return True if the payment token is whitelisted, otherwise false.
     */
    function whitelistedPaymentTokens(
        address paymentTokenAddress
    ) external view returns (bool) {
        return _whitelistedPaymentTokens.contains(paymentTokenAddress);
    }

    /**
     * @dev Fallback function to receive native tokens (e.g., ETH).
     */
    receive() external payable {}

    /**
     * @dev Handles the receipt of a single ERC721 token type.
     * @return The selector to confirm successful receipt of the token.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev Handles the receipt of a single ERC1155 token type.
     * @return The selector to confirm successful receipt of the token.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of multiple ERC1155 token types.
     * @return The selector to confirm successful receipt of the tokens.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Checks if the contract supports a specific interface.
     * @param interfaceId The interface ID to check.
     * @return True if the interface is supported, otherwise false.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC1155HolderUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(AccessControlUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Determines the type of a token (ERC721 or ERC1155) based on its interface support.
     * @param _nftAddress The address of the token contract.
     * @return tokenType The type of the token.
     * @dev Reverts with `ErrorInvalidTokenType` if the token does not implement either ERC721 or ERC1155 interfaces.
     */
    function _getTokenType(
        address _nftAddress
    ) internal view returns (uint8 tokenType) {
        if (IERC165(_nftAddress).supportsInterface(0xd9b67a26)) {
            tokenType = uint8(TokenType.ERC1155);
        } else if (IERC165(_nftAddress).supportsInterface(0x80ac58cd)) {
            tokenType = uint8(TokenType.ERC721);
        } else {
            revert ErrorInvalidTokenType();
        }
    }

    /**
     * @notice Updates the status for native token.
     */
    function updateAllowNativeToken(
        bool status
    ) external onlyRole(MANAGER_ROLE) nonReentrant {
        if (allowNativeToken == status) {
            revert ErrorSameValue();
        }
        allowNativeToken = status;
    }

    function getListingTimestamp(
        bytes32 _listingId
    ) external view returns (uint64) {
        return _listingTimestamps[_listingId];
    }

    function updateCancelListingCooldown(
        uint64 _listingCancelCooldown
    ) external onlyRole(MANAGER_ROLE) nonReentrant {
        if (listingCancelCooldown == _listingCancelCooldown) {
            revert ErrorSameValue();
        }
        listingCancelCooldown = _listingCancelCooldown;
    }

    function getUserAuctions(
        address _user
    ) external view returns (bytes32[] memory listingIds) {
        uint256 length = _userAuctions[_user].length();
        listingIds = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            listingIds[i] = _userAuctions[_user].at(i);
        }
    }

    /**
     * @notice Sets the Unit Token contract address.
     * @param _unitTokenAddress The address of the Unit Token contract.
     * Only callable by accounts with the MANAGER_ROLE.
     */
    function setUnitTokenAddress(
        address _unitTokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        if (_unitTokenAddress == address(0)) {
            revert ErrorInvalidAddress();
        }
        if (unitTokenAddress == _unitTokenAddress) {
            revert ErrorSameValue();
        }
        unitTokenAddress = _unitTokenAddress;
    }

    /**
     * @notice Sets the Uniswap router address.
     * @param _router The address of the Uniswap V2 router.
     * Only callable by accounts with the MANAGER_ROLE.
     */
    function setUniswapRouter(address _router) external onlyRole(MANAGER_ROLE) {
        if (_router == address(0)) {
            revert ErrorInvalidAddress();
        }
        if (_router == address(lpRouter)) {
            revert ErrorSameValue();
        }
        lpRouter = IUniswapV2Router02(_router);
    }

    // /**
    //  * @dev Internal function to swap a given amount of Unit Token for ETH and forward only the converted ETH
    //  * to the royalty recipient. Follows the same pattern as in the UnitToken contract.
    //  */
    // function _swapRoyaltyFee(
    //     uint256 amount,
    //     address royaltyRecipient
    // ) internal {
    //     // Build the swap path: Unit Token -> WETH.
    //     address[] memory path = new address[](2);
    //     path[0] = unitTokenAddress;
    //     path[1] = lpRouter.WETH();

    //     // Approve the router to spend the specified amount of Unit Token.
    //     IERC20(unitTokenAddress).approve(address(lpRouter), amount);

    //     // Get the expected ETH output for the given amount.
    //     uint[] memory amountsOut = lpRouter.getAmountsOut(amount, path);
    //     uint expectedEth = amountsOut[1];
    //     // Set a minimum acceptable amount to 95% of the expected output (5% slippage tolerance).
    //     uint minEth = (expectedEth * 95) / 100;

    //     // Record the initial ETH balance of the contract.
    //     uint256 initialBalance = address(this).balance;

    //     // Perform the swap.
    //     lpRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
    //         amount,
    //         minEth,
    //         path,
    //         address(this),
    //         block.timestamp
    //     );

    //     // Calculate only the ETH received from this swap.
    //     uint256 newBalance = address(this).balance;
    //     uint256 ethReceived = newBalance - initialBalance;

    //     // Forward only the converted ETH to the royalty recipient.
    //     payable(royaltyRecipient).transfer(ethReceived);
    // }

    /**
     * @notice Updates auto swap status.
     *
     * This function can only be called by an account with the `MANAGER_ROLE`.
     * @param _status The new status for swap.
     */
    function updateAutoSwapStatus(
        bool _status
    ) external onlyRole(MANAGER_ROLE) {
        if (autoSwapEnabled == _status) {
            revert ErrorSameValue();
        }
        autoSwapEnabled = _status;
    }

    /**
     * @notice Sets the TreasuryManager contract address.
     * @param _treasuryManager The address of the TreasuryManager contract.
     * @dev Only callable by accounts with the MANAGER_ROLE.
     */
    function setTreasuryManager(
        address _treasuryManager
    ) external onlyRole(MANAGER_ROLE) {
        if (_treasuryManager == address(0)) {
            revert ErrorInvalidAddress();
        }
        treasuryManager = TreasuryManager(payable(_treasuryManager));
    }
}
