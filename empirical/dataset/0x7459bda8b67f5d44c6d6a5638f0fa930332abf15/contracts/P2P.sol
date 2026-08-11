//SPDX-License-Identifier: MIT
pragma solidity =0.8.28;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IAuthorityManager.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPriceAggregator.sol";
import "./libs/P2PLibrary.sol";

contract P2P is ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;

    uint256 public buyOfferCounter;
    uint256 public sellOfferCounter;

    uint64 public feePercentage;
    uint64 public priceMarkup;

    IAuthorityManager public authorityManager;
    IFactory public factory;

    IPriceAggregator public goldPriceAggregator;
    IPriceAggregator public silverPriceAggregator;

    IERC20Metadata public usdt;
    IERC20Metadata public usdc;

    mapping(uint256 => P2PLibrary.BuyOffer) public buyOffers;
    mapping(uint256 => P2PLibrary.SellOffer) public sellOffers;

    event BuyOfferCreated(P2PLibrary.BuyOffer _buyOffer, uint256 _buyOfferId);
    event SellOfferCreated(
        P2PLibrary.SellOffer _sellOffer,
        uint256 _sellOfferId
    );
    event BuyOfferCancelled(uint256 _buyOfferId);
    event SellOfferCancelled(uint256 _sellOfferId);
    event BuyOfferAccepted(
        uint256 _buyOfferId,
        uint256 _tokenAmount,
        uint256 _amountSellerGets,
        uint256 _fee,
        address _seller
    );
    event SellOfferAccepted(
        uint256 _sellOfferId,
        uint256 _tokenAmount,
        uint256 _amountBuyerPays,
        uint256 _fee,
        address _buyer
    );
    event FeePercentageUpdated(uint64 _feePercentage);
    event PriceMarkupUpdated(uint64 _priceMarkup);
    event AuthorityManagerUpdated(address _authorityManager);
    event FactoryUpdated(address _factory);

    modifier onlyOwner() {
        require(msg.sender == authorityManager.owner(), "Not owner");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _authorityManager,
        address _factory,
        address _goldPriceAggregator,
        address _silverPriceAggregator,
        address _usdt,
        address _usdc
    ) external initializer {
        require(_authorityManager != address(0), "invalid address");
        require(_factory != address(0), "invalid address");
        require(_goldPriceAggregator != address(0), "invalid address");
        require(_silverPriceAggregator != address(0), "invalid address");
        require(_usdt != address(0), "invalid address");
        require(_usdc != address(0), "invalid address");
        __ReentrancyGuard_init();
        feePercentage = 5e7; // 0.05%
        priceMarkup = 5e8; // 5%
        authorityManager = IAuthorityManager(_authorityManager);
        factory = IFactory(_factory);
        goldPriceAggregator = IPriceAggregator(_goldPriceAggregator);
        silverPriceAggregator = IPriceAggregator(_silverPriceAggregator);
        usdt = IERC20Metadata(_usdt);
        usdc = IERC20Metadata(_usdc);
    }

    function setFeePercentage(uint64 _feePercentage) external onlyOwner {
        require(_feePercentage <= 1e9, "Fee percentage too high");
        feePercentage = _feePercentage;
        emit FeePercentageUpdated(_feePercentage);
    }

    function setPriceMarkup(uint64 _priceMarkup) external onlyOwner {
        require(_priceMarkup <= 1e9, "Markup percentage too high");
        priceMarkup = _priceMarkup;
        emit PriceMarkupUpdated(_priceMarkup);
    }

    function setAuthorityManager(address _authorityManager) external onlyOwner {
        require(_authorityManager != address(0), "invalid address");
        authorityManager = IAuthorityManager(_authorityManager);
        emit AuthorityManagerUpdated(_authorityManager);
    }

    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "invalid address");
        factory = IFactory(_factory);
        emit FactoryUpdated(_factory);
    }

    function createBuyOffer(
        P2PLibrary.BuyType _buyType,
        P2PLibrary.PropertyType _propertyType,
        uint256 _propertyId,
        uint256 _tokenAmount,
        uint256 _price,
        address _tokenAddress
    ) external nonReentrant {
        require(_tokenAmount > 0, "Invalid token amount");
        require(_price > 0, "Invalid price");
        require(_tokenAddress != address(0), "invalid token");
        (uint256 paymentAmount, uint256 fee) = calculateForBuyOffer(
            _buyType,
            _propertyType,
            _tokenAmount,
            _price,
            _propertyId,
            _tokenAddress
        );
        unchecked {
            buyOfferCounter++;
        }
        P2PLibrary.BuyOffer storage _offer = buyOffers[buyOfferCounter];
        _offer.price = _price;
        _offer.totalTokens = _tokenAmount;
        _offer.paymentAmount = paymentAmount + fee;
        _offer.remainingPaymentAmount = paymentAmount + fee;
        _offer.propertyId = _propertyId;
        _offer.feePercentage = feePercentage;
        _offer.paymentToken = _buyType;
        _offer.propertyType = _propertyType;
        _offer.status = P2PLibrary.OrderStatus.PENDING;
        _offer.maker = msg.sender;

        if (_propertyType == P2PLibrary.PropertyType.ERC3643) {
            P2PLibrary.PropertyData memory property = authorityManager
                .propertyDetails(_propertyId);
            _tokenAddress = property.token;
        } else {
            P2PLibrary.TokenInfo memory info = factory.getTokenInfo(
                _tokenAddress
            );
            _tokenAddress = info.tokenAddress;
        }
        require(_tokenAddress != address(0), "Token not registered");
        _offer.tokenAddress = _tokenAddress;

        //  allowance check
        IERC20Metadata _buyToken = _getBuyToken(_buyType);
        require(
            _buyToken.allowance(msg.sender, address(this)) >=
                _offer.paymentAmount,
            "Allowance not enough"
        );
        _buyToken.safeTransferFrom(
            msg.sender,
            address(this),
            _offer.paymentAmount
        );

        emit BuyOfferCreated(_offer, buyOfferCounter);
    }

    function createSellOffer(
        P2PLibrary.BuyType _buyType,
        P2PLibrary.PropertyType _propertyType,
        uint256 _propertyId,
        uint256 _tokenAmount,
        uint256 _price,
        address _tokenAddress
    ) external nonReentrant {
        require(_tokenAmount > 0, "Invalid token amount");
        require(_price > 0, "Invalid price");
        require(_tokenAddress != address(0), "invalid token");
        uint256 tokenPrice;
        P2PLibrary.PropertyData memory property;
        P2PLibrary.TokenInfo memory _tokenInfo;
        if (_propertyType == P2PLibrary.PropertyType.ERC3643) {
            property = authorityManager.propertyDetails(_propertyId);
            tokenPrice = property.price;
            _tokenAddress = property.token;
        } else {
            _tokenInfo = factory.getTokenInfo(_tokenAddress);
            tokenPrice = getAssetPrice(_tokenInfo.assetType);
            _tokenAddress = _tokenInfo.tokenAddress;
        }
        require(_tokenAddress != address(0), "Token not registered");
        _validatePrice(_price, tokenPrice);
        unchecked {
            sellOfferCounter++;
        }
        P2PLibrary.SellOffer storage _offer = sellOffers[sellOfferCounter];
        _offer.price = _price;
        _offer.totalTokens = _tokenAmount;
        _offer.propertyId = _propertyId;
        _offer.paymentToken = _buyType;
        _offer.feePercentage = feePercentage;
        _offer.propertyType = _propertyType;
        _offer.status = P2PLibrary.OrderStatus.PENDING;
        _offer.maker = msg.sender;
        _offer.tokenAddress = _tokenAddress;

        //  allowance check
        require(
            IERC20Metadata(_offer.tokenAddress).allowance(
                msg.sender,
                address(this)
            ) >= _tokenAmount,
            "Allowance not enough"
        );
        IERC20Metadata(_offer.tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );

        emit SellOfferCreated(_offer, sellOfferCounter);
    }

    function calculateForSellOffer(
        P2PLibrary.BuyType _buyType,
        uint256 _tokenAmount,
        uint256 _price,
        address _tokenAddress
    ) public view returns (uint256 _amount, uint256 fee) {
        IERC20Metadata token = IERC20Metadata(_tokenAddress);
        IERC20Metadata buyToken = _getBuyToken(_buyType);

        uint256 tokenDecimals = token.decimals();
        uint256 buyTokenDecimals = buyToken.decimals();

        _amount =
            (_tokenAmount * _price * (10 ** buyTokenDecimals)) /
            (10 ** tokenDecimals * 10 ** 6);

        fee = (_amount * feePercentage) / 1e10;
        _amount -= fee;
    }

    function cancelBuyOffer(uint256 _offerId) external nonReentrant {
        require(_offerId > 0 && _offerId <= buyOfferCounter, "Invalid offer");
        P2PLibrary.BuyOffer storage _offer = buyOffers[_offerId];
        if (_offer.propertyType == P2PLibrary.PropertyType.ERC3643) {
            P2PLibrary.PropertyData memory _property = authorityManager
                .propertyDetails(_offer.propertyId);
            require(
                _offer.maker == msg.sender || _property.agent == msg.sender,
                "Not maker or investment manager"
            );
        } else {
            P2PLibrary.TokenInfo memory _tokenInfo = factory.getTokenInfo(
                _offer.tokenAddress
            );
            require(
                _offer.maker == msg.sender || _tokenInfo.agent == msg.sender,
                "Not maker or investment manager"
            );
        }
        require(
            _offer.status == P2PLibrary.OrderStatus.PENDING ||
                _offer.status == P2PLibrary.OrderStatus.PARTIALLY_FILLED,
            "Not pending or partially filled"
        );
        _offer.status = P2PLibrary.OrderStatus.CANCELLED;

        IERC20Metadata _buyToken = _offer.paymentToken ==
            P2PLibrary.BuyType.USDT
            ? usdt
            : usdc;

        _buyToken.safeTransfer(_offer.maker, _offer.remainingPaymentAmount);

        emit BuyOfferCancelled(_offerId);
    }

    function cancelSellOffer(uint256 _offerId) external nonReentrant {
        require(_offerId > 0 && _offerId <= sellOfferCounter, "Invalid offer");
        P2PLibrary.SellOffer storage _offer = sellOffers[_offerId];
        if (_offer.propertyType == P2PLibrary.PropertyType.ERC3643) {
            P2PLibrary.PropertyData memory _property = authorityManager
                .propertyDetails(_offer.propertyId);
            require(
                _offer.maker == msg.sender || _property.agent == msg.sender,
                "Not maker or investment manager"
            );
        } else {
            P2PLibrary.TokenInfo memory _tokenInfo = factory.getTokenInfo(
                _offer.tokenAddress
            );
            require(
                _offer.maker == msg.sender || _tokenInfo.agent == msg.sender,
                "Not maker or investment manager"
            );
        }
        require(
            _offer.status == P2PLibrary.OrderStatus.PENDING ||
                _offer.status == P2PLibrary.OrderStatus.PARTIALLY_FILLED,
            "Not pending or partially filled"
        );
        _offer.status = P2PLibrary.OrderStatus.CANCELLED;

        uint256 remainingTokens = _offer.totalTokens - _offer.filledTokens;

        IERC20Metadata(_offer.tokenAddress).safeTransfer(
            _offer.maker,
            remainingTokens
        );

        emit SellOfferCancelled(_offerId);
    }

    function _validatePrice(uint256 _price, uint256 _tokenPrice) internal view {
        uint256 _markup = (_tokenPrice * priceMarkup) / 1e10;

        if (_price > _tokenPrice) {
            require(_price <= _tokenPrice + _markup, "Price too high");
        } else {
            require(_price >= _tokenPrice - _markup, "Price too low");
        }
    }

    function calculateForBuyOffer(
        P2PLibrary.BuyType _buyType,
        P2PLibrary.PropertyType _propertyType,
        uint256 _tokenAmount,
        uint256 _price,
        uint256 _propertyId,
        address _tokenAddress
    ) public view returns (uint256 buyAmount, uint256 fee) {
        require(_tokenAddress != address(0), "invalid token");
        uint256 tokenPrice;
        address tokenAddress;

        if (_propertyType == P2PLibrary.PropertyType.ERC3643) {
            P2PLibrary.PropertyData memory property = authorityManager
                .propertyDetails(_propertyId);
            tokenPrice = property.price;
            tokenAddress = property.token;
        } else {
            P2PLibrary.TokenInfo memory info = factory.getTokenInfo(
                _tokenAddress
            );
            tokenPrice = getAssetPrice(info.assetType);
            tokenAddress = info.tokenAddress;
        }

        _validatePrice(_price, tokenPrice);

        IERC20Metadata token = IERC20Metadata(tokenAddress);
        IERC20Metadata buyToken = _getBuyToken(_buyType);

        uint256 tokenDecimals = token.decimals();
        uint256 buyTokenDecimals = buyToken.decimals();

        buyAmount =
            (_tokenAmount * _price * (10 ** buyTokenDecimals)) /
            (10 ** tokenDecimals * 10 ** 6);

        fee = (buyAmount * feePercentage) / 1e10;
    }

    function _getBuyToken(
        P2PLibrary.BuyType _buyType
    ) internal view returns (IERC20Metadata) {
        return _buyType == P2PLibrary.BuyType.USDT ? usdt : usdc;
    }

    /**
     * @dev Gets the current price and decimals for a given asset type
     * @param _assetType The asset type (Gold or Silver)
     * @return _latestAnswer The latest price from the aggregator
     */
    function getAssetPrice(
        P2PLibrary.AssetType _assetType
    ) public view returns (uint256) {
        IPriceAggregator priceAggregator = _assetType ==
            P2PLibrary.AssetType.Gold
            ? goldPriceAggregator
            : silverPriceAggregator;

        uint8 oracleDecimals = priceAggregator.decimals();
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceAggregator.latestRoundData();
        require(price > 0, "Invalid oracle price");

        uint256 normalizedPrice = uint256(price);

        if (oracleDecimals > 6) {
            normalizedPrice = normalizedPrice / (10 ** (oracleDecimals - 6));
        } else if (oracleDecimals < 6) {
            normalizedPrice = normalizedPrice * (10 ** (6 - oracleDecimals));
        }

        return normalizedPrice;
    }

    function acceptBuyOffer(
        uint256 _buyOfferId,
        uint256 _tokenAmount
    ) external nonReentrant {
        (uint256 _sellerAmount, uint256 _fee) = calculateAmountSellerGets(
            _buyOfferId,
            _tokenAmount
        );

        P2PLibrary.BuyOffer storage offer = buyOffers[_buyOfferId];
        // check allowance
        IERC20Metadata token = IERC20Metadata(offer.tokenAddress);
        require(
            token.allowance(msg.sender, address(this)) >= _tokenAmount,
            "Insufficient allowance"
        );
        //check balance
        require(
            token.balanceOf(msg.sender) >= _tokenAmount,
            "Insufficient balance"
        );

        uint256 _totalFee = _fee * 2;
        uint256 _totalDeduction = _sellerAmount + _totalFee;

        // update storage
        offer.filledTokens += _tokenAmount;
        offer.remainingPaymentAmount -= _totalDeduction;
        offer.fee += _totalFee;

        if (offer.remainingPaymentAmount == 0) {
            offer.status = P2PLibrary.OrderStatus.FILLED;
        } else {
            offer.status = P2PLibrary.OrderStatus.PARTIALLY_FILLED;
        }

        IERC20Metadata buyToken = _getBuyToken(offer.paymentToken);
        address _owner = authorityManager.receiverAddress();

        // fee to owner
        buyToken.safeTransfer(_owner, _totalFee);

        // payment to seller
        buyToken.safeTransfer(msg.sender, _sellerAmount);

        // transfer property tokens to buyer
        token.safeTransferFrom(msg.sender, offer.maker, _tokenAmount);

        if (offer.filledTokens == offer.totalTokens) {
            if (offer.remainingPaymentAmount > 0) {
                offer.status = P2PLibrary.OrderStatus.FILLED;
                buyToken.safeTransfer(_owner, offer.remainingPaymentAmount);
                offer.remainingPaymentAmount = 0;
            }
        }

        emit BuyOfferAccepted(
            _buyOfferId,
            _tokenAmount,
            _sellerAmount,
            _totalFee,
            msg.sender
        );
    }

    function calculateAmountSellerGets(
        uint256 _buyOfferId,
        uint256 _tokenAmount
    ) public view returns (uint256 amountSellerGets, uint256 fee) {
        require(
            _buyOfferId > 0 && _buyOfferId <= buyOfferCounter,
            "Invalid offer"
        );
        require(_tokenAmount > 0, "Invalid token amount");
        P2PLibrary.BuyOffer memory _offer = buyOffers[_buyOfferId];
        require(
            _offer.status != P2PLibrary.OrderStatus.CANCELLED,
            "This offer is cancelled"
        );
        require(
            _offer.status != P2PLibrary.OrderStatus.FILLED,
            "This offer is completed"
        );
        require(
            _offer.totalTokens >= _offer.filledTokens + _tokenAmount,
            "Not enough token amount remainning in this order"
        );
        IERC20Metadata _buyToken = _getBuyToken(_offer.paymentToken);
        IERC20Metadata _token = IERC20Metadata(_offer.tokenAddress);
        uint256 tokenDecimals = _token.decimals();
        uint256 buyTokenDecimals = _buyToken.decimals();
        amountSellerGets =
            (_tokenAmount * _offer.price * (10 ** buyTokenDecimals)) /
            ((10 ** tokenDecimals) * 10 ** 6);
        fee = (amountSellerGets * _offer.feePercentage) / 1e10;
        amountSellerGets -= fee;
    }

    function acceptSellOffer(
        uint256 _sellOfferId,
        uint256 _tokenAmount
    ) external nonReentrant {
        (uint256 _totalPaymentAmount, uint256 _fee) = calculateAmountBuyerPays(
            _sellOfferId,
            _tokenAmount
        );

        P2PLibrary.SellOffer storage _offer = sellOffers[_sellOfferId];

        // check allowance
        IERC20Metadata _buyToken = _getBuyToken(_offer.paymentToken);
        require(
            _buyToken.allowance(msg.sender, address(this)) >=
                _totalPaymentAmount,
            "Insufficient allowance"
        );
        //check balance
        require(
            _buyToken.balanceOf(msg.sender) >= _totalPaymentAmount,
            "Insufficient balance"
        );

        uint256 _buyerFee = _fee;
        uint256 _sellerFee = _fee;
        uint256 _totalFee = _buyerFee + _sellerFee;
        uint256 _sellerReceive = _totalPaymentAmount - _totalFee;

        // update storage
        _offer.filledTokens += _tokenAmount;
        _offer.fee += _totalFee;

        if (_offer.filledTokens == _offer.totalTokens) {
            _offer.status = P2PLibrary.OrderStatus.FILLED;
        } else {
            _offer.status = P2PLibrary.OrderStatus.PARTIALLY_FILLED;
        }

        // fee to receiver
        _buyToken.safeTransferFrom(
            msg.sender,
            authorityManager.receiverAddress(),
            _totalFee
        );

        // payment to seller
        _buyToken.safeTransferFrom(msg.sender, _offer.maker, _sellerReceive);

        // transfer property tokens to buyer
        IERC20Metadata(_offer.tokenAddress).safeTransfer(
            msg.sender,
            _tokenAmount
        );

        emit SellOfferAccepted(
            _sellOfferId,
            _tokenAmount,
            _totalPaymentAmount,
            _totalFee,
            msg.sender
        );
    }

    function calculateAmountBuyerPays(
        uint256 _sellOfferId,
        uint256 _tokenAmount
    ) public view returns (uint256 buyAmount, uint256 fee) {
        require(
            _sellOfferId > 0 && _sellOfferId <= sellOfferCounter,
            "Invalid offer"
        );
        require(_tokenAmount > 0, "Invalid token amount");
        P2PLibrary.SellOffer memory _offer = sellOffers[_sellOfferId];
        require(
            _offer.status != P2PLibrary.OrderStatus.CANCELLED,
            "This offer is cancelled"
        );
        require(
            _offer.status != P2PLibrary.OrderStatus.FILLED,
            "This offer is completed"
        );
        require(
            _offer.totalTokens >= _offer.filledTokens + _tokenAmount,
            "Not enough token amount remainning in this order"
        );

        IERC20Metadata token = IERC20Metadata(_offer.tokenAddress);
        IERC20Metadata buyToken = _getBuyToken(_offer.paymentToken);

        uint256 tokenDecimals = token.decimals();
        uint256 buyTokenDecimals = buyToken.decimals();

        buyAmount =
            (_tokenAmount * _offer.price * (10 ** buyTokenDecimals)) /
            (10 ** tokenDecimals * 10 ** 6);
        require(buyAmount > 0, "Payment rounds to zero");

        fee = (buyAmount * _offer.feePercentage) / 1e10;

        buyAmount += fee;
    }
}
