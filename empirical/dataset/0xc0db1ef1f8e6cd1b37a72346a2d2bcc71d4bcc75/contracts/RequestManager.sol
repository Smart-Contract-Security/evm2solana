// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC20MetadataMintable.sol";
import {FactoryLib} from "./libraries/FactoryLib.sol";
import {IRequestManager} from "./interfaces/IRequestManager.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IPriceAggregator} from "./interfaces/IPriceAggregator.sol";
import {IUserManager} from "./interfaces/IUserManager.sol";

contract RequestManager is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IRequestManager
{
    using SafeERC20 for IERC20MetadataMintable;
    using FactoryLib for uint8;

    address public receiverAddress;

    IFactory public factory;
    IUserManager public userManager;
    IPriceAggregator public goldPriceAggregator;
    IPriceAggregator public silverPriceAggregator;
    IERC20MetadataMintable public usdcToken;
    IERC20MetadataMintable public usdtToken;

    mapping(address => mapping(address => uint256)) public userRequestCount;
    mapping(address => mapping(address => mapping(uint256 => FactoryLib.RequestInfo)))
        public requestInfo;
    mapping(address => FactoryLib.UserOneTimeFee) public userOneTimeFee;

    modifier zeroAddress(address _address) {
        require(_address != address(0), "Invalid address");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the RequestManager contract
     * @param _factory The address of the Factory contract
     * @param _userManager The address of the UserManager contract
     * @param _receiverAddress The address that receives fees
     * @param _usdcToken The address of the USDC token contract
     * @param _usdtToken The address of the USDT token contract
     * @param _goldPriceAggregator The address of the gold price aggregator
     * @param _silverPriceAggregator The address of the silver price aggregator
     */
    function initialize(
        address _factory,
        address _userManager,
        address _receiverAddress,
        address _usdcToken,
        address _usdtToken,
        address _goldPriceAggregator,
        address _silverPriceAggregator
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_msgSender());

        require(_factory != address(0), "Invalid factory address");
        require(_userManager != address(0), "Invalid user manager address");

        factory = IFactory(_factory);
        userManager = IUserManager(_userManager);
        receiverAddress = _receiverAddress;
        usdcToken = IERC20MetadataMintable(_usdcToken);
        usdtToken = IERC20MetadataMintable(_usdtToken);
        goldPriceAggregator = IPriceAggregator(_goldPriceAggregator);
        silverPriceAggregator = IPriceAggregator(_silverPriceAggregator);
    }

    /**
     * @dev Updates the factory address
     * @notice Only the owner can update the factory
     * @param _factory The new factory address (must not be zero address)
     */
    function updateFactory(
        address _factory
    ) external onlyOwner zeroAddress(_factory) {
        factory = IFactory(_factory);
    }

    /**
     * @dev Updates the user manager address
     * @notice Only the owner can update the user manager
     * @param _userManager The new user manager address (must not be zero address)
     */
    function updateUserManager(
        address _userManager
    ) external onlyOwner zeroAddress(_userManager) {
        userManager = IUserManager(_userManager);
    }

    /**
     * @dev Updates the receiver address
     * @notice Only the owner can update the receiver address
     * @param _receiverAddress The new receiver address (must not be zero address)
     */
    function updateReceiverAddress(
        address _receiverAddress
    ) public onlyOwner zeroAddress(_receiverAddress) {
        receiverAddress = _receiverAddress;
    }

    /**
     * @dev Gets the current price and decimals for a given asset type
     * @param _assetType The asset type (Gold or Silver)
     * @return _decimals The number of decimals for the price
     * @return _latestAnswer The latest price from the aggregator
     */
    function getAssetPrice(
        FactoryLib.AssetType _assetType
    ) public view returns (uint8, int256) {
        IPriceAggregator _priceAggregator = _assetType ==
            FactoryLib.AssetType.Gold
            ? goldPriceAggregator
            : silverPriceAggregator;

        uint8 _decimals = _priceAggregator.decimals();
        (, int256 _price, , , ) = _priceAggregator.latestRoundData();

        return (_decimals, _price);
    }

    /**
     * @dev Gets the request count for a user and token
     * @param _user is the user address
     * @param _tokenAddress is the token address
     * @return The request count
     */
    function getUserRequestCount(
        address _user,
        address _tokenAddress
    ) external view returns (uint256) {
        return userRequestCount[_user][_tokenAddress];
    }

    /**
     * @dev Gets the request info for a user, token, and buy ID
     * @param _user is the user address
     * @param _tokenAddress is the token address
     * @param _buyId is the buy ID
     * @return The request info
     */
    function getRequestInfo(
        address _user,
        address _tokenAddress,
        uint256 _buyId
    ) external view returns (FactoryLib.RequestInfo memory) {
        return requestInfo[_user][_tokenAddress][_buyId];
    }

    /**
     * @dev Requests tokens from the factory
     * @notice Transfers buy tokens to factory, creates a request, and locks tokens
     * @param _buyType The type of the buy (0 for USDC, 1 for USDT)
     * @param _buyAmount The amount of buy tokens to spend
     * @param _tokenAddress The address of the token to buy
     * @param _investmentId The investment identifier string
     */
    function requestTokens(
        uint8 _buyType,
        uint256 _buyAmount,
        address _tokenAddress,
        string memory _investmentId
    ) public nonReentrant {
        require(_buyAmount > 0, "Buy amount must be greater than 0");

        FactoryLib.TokenInfo memory _tokenInfo = _validateTokenRequest(
            _tokenAddress,
            _buyAmount
        );

        (uint256 _tokenAmount, uint256 _totalShare, ) = calculateTokenAmount(
            _buyType,
            _tokenAddress,
            _buyAmount,
            msg.sender,
            false,
            FactoryLib.TokenCategory.VaultedBullion // Only  Vaulted Bullion is supported for USDC and USDT
        );

        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(
            _tokenInfo.maxSupply >= _tokenInfo.locked + _totalShare,
            "Token amount must be less than max supply"
        );

        (uint256 _platformFee, uint256 _oneTimeFee) = _getFeeAmounts(
            _buyAmount,
            _tokenInfo
        );

        uint256 _requestId = _createRequest(
            _buyType,
            _tokenAddress,
            _buyAmount,
            _tokenAmount,
            _platformFee,
            _oneTimeFee
        );

        _requestTokensExecute(
            _buyType,
            _tokenAddress,
            _buyAmount,
            _tokenAmount,
            _requestId,
            _platformFee,
            _oneTimeFee,
            _investmentId
        );
    }

    /**
     * @dev Executes lock, transfer and emit for a token request (reduces stack depth in requestTokens)
     * @param _buyType The type of the buy (0 for USDC, 1 for USDT)
     * @param _tokenAddress The address of the token
     * @param _buyAmount The amount of buy tokens to spend
     * @param _tokenAmount The amount of tokens to receive
     * @param _requestId The request ID
     * @param _platformFee The platform fee
     * @param _oneTimeFee The one-time fee
     * @param _investmentId The investment identifier
     */
    function _requestTokensExecute(
        uint8 _buyType,
        address _tokenAddress,
        uint256 _buyAmount,
        uint256 _tokenAmount,
        uint256 _requestId,
        uint256 _platformFee,
        uint256 _oneTimeFee,
        string memory _investmentId
    ) internal {
        factory.updateTokenLocked(_tokenAddress, _tokenAmount, true);

        IERC20MetadataMintable buyToken = _getBuyToken(_buyType);
        buyToken.safeTransferFrom(msg.sender, address(factory), _buyAmount);

        emit TokensBought(
            msg.sender,
            _tokenAddress,
            _requestId,
            _buyAmount,
            _tokenAmount,
            _platformFee,
            _oneTimeFee,
            _investmentId
        );
    }

    /**
     * @dev Calculates the amount of tokens to buy
     * @param _buyType is the type of the buy (0 for USDC, 1 for USDT)
     * @param _tokenAddress is the address of the token
     * @param _amount is the amount of USD to buy
     * @return _tokenAmount is the amount of tokens to buy
     */
    function calculateTokenAmount(
        uint8 _buyType,
        address _tokenAddress,
        uint256 _amount,
        address _userAddress,
        bool _isPledge,
        FactoryLib.TokenCategory _category
    )
        public
        view
        returns (
            uint256 _tokenAmount,
            uint256 _totalShare,
            uint256 _mineOwnerShare
        )
    {
        require(_tokenAddress != address(0), "Invalid token address");

        // Only Vaulted Bullion is supported for USDC and USDT
        if (!_isPledge && _category != FactoryLib.TokenCategory.VaultedBullion)
            revert(
                "Only Vaulted Bullion is supported for non-pledged requests"
            );

        FactoryLib.TokenInfo memory _tokenInfo = factory.getTokenInfo(
            _tokenAddress
        );
        require(_tokenInfo.tokenAddress != address(0), "Token does not exist");

        (int256 _tokenPrice, uint8 _tokenPriceDecimals) = FactoryLib
            .getPriceAndDecimals(
                _tokenInfo.assetType,
                goldPriceAggregator,
                silverPriceAggregator
            );

        // Amount after platform fee and one time fee
        _amount = _subtractFeeAmounts(
            _amount,
            _tokenInfo.platformFee,
            _userAddress,
            _isPledge
        );

        IERC20MetadataMintable _buyToken = _getBuyToken(_buyType);

        _tokenAmount = FactoryLib.calculateTokenAmount(
            _tokenInfo,
            _amount,
            _tokenPrice,
            _tokenPriceDecimals,
            _buyToken.decimals()
        );

        (_totalShare, _mineOwnerShare) = _calculateShares(
            _category,
            _tokenAmount,
            _tokenAddress
        );
    }

    /**
     * @dev Subtracts fee amounts from the amount
     * @param _amount The amount to subtract fees from
     * @param _platformFee The platform fee
     * @param _userAddress The user address
     * @param _isPledge Whether the request is a pledge
     * @return _amount The amount after subtracting fees
     */
    function _subtractFeeAmounts(
        uint256 _amount,
        uint256 _platformFee,
        address _userAddress,
        bool _isPledge
    ) internal view returns (uint256) {
        if (!_isPledge) {
            if (_platformFee > 0) {
                _amount -= (_amount * _platformFee) / 100_00;
            }

            if (
                !userManager.userOneTimeFee(_userAddress).completeStatus &&
                !userOneTimeFee[_userAddress].completeStatus
            ) {
                uint256 _oneTimeFee = userManager.oneTimeFee();
                require(
                    _amount > _oneTimeFee,
                    "Amount too low after platform and one-time fees"
                );
                _amount -= _oneTimeFee;
            }
        }
        return _amount;
    }

    /**
     * @dev Calculates the shares for a token
     * @param _category The category of the token
     * @param _tokenAmount The amount of tokens to calculate shares for
     * @param _tokenAddress The address of the token
     * @return totalShare The total share
     * @return mineOwnerShare The mine owner share
     */
    function _calculateShares(
        FactoryLib.TokenCategory _category,
        uint256 _tokenAmount,
        address _tokenAddress
    ) internal view returns (uint256 totalShare, uint256 mineOwnerShare) {
        (
            uint256 mineOwner,
            uint256 esg,
            uint256 givingBack,
            uint256 marketing,
            uint256 introducer
        ) = factory.calculateCategoryShares(
                _category,
                _tokenAmount,
                _tokenAddress
            );

        totalShare = mineOwner + esg + givingBack + marketing + introducer;
        mineOwnerShare = mineOwner;
    }

    /**
     * @dev Accepts buy requests and distributes tokens to users
     * @notice Can only be called by the token agent. Processes multiple requests in a batch.
     * @param _users Array of user addresses who made the requests
     * @param _tokenAddresses Array of token addresses for each request
     * @param _tokenAmounts Array of token amounts to distribute
     * @param _acceptRequestParams The parameters for the accept request
     */
    function acceptBuyRequest(
        address[] calldata _users,
        address[] calldata _tokenAddresses,
        uint256[] calldata _tokenAmounts,
        FactoryLib.AcceptRequestParams calldata _acceptRequestParams
    ) external nonReentrant {
        require(
            _users.length == _tokenAddresses.length &&
                _users.length == _tokenAmounts.length &&
                _users.length == _acceptRequestParams.buyIds.length &&
                _users.length == _acceptRequestParams.isPledge.length &&
                _users.length == _acceptRequestParams.categories.length &&
                _users.length == _acceptRequestParams.investmentIds.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < _users.length; i++) {
            address _user = _users[i];
            address _tokenAddress = _tokenAddresses[i];
            uint256 _tokenAmount = _tokenAmounts[i];
            uint256 _buyId = _acceptRequestParams.buyIds[i];
            string memory _investmentId = _acceptRequestParams.investmentIds[i];

            require(_user != address(0), "Invalid user address");
            require(_tokenAddress != address(0), "Invalid token address");
            require(_tokenAmount > 0, "Token amount must be greater than 0");

            FactoryLib.TokenInfo memory _tokenInfo = factory.getTokenInfo(
                _tokenAddress
            );
            require(
                _tokenInfo.tokenAddress != address(0),
                "Token does not exist"
            );
            require(
                _tokenInfo.agent == msg.sender,
                "Not the agent of the token"
            );

            if (!_acceptRequestParams.isPledge[i]) {
                _tokenAmount = _processNonPledgedRequest(
                    _user,
                    _tokenAddress,
                    _buyId
                );
            }

            _processTokenDistribution(
                _user,
                _acceptRequestParams.categories[i],
                _tokenAddress,
                _tokenAmount,
                _buyId,
                _investmentId
            );
        }
    }

    /**
     * @dev Rejects buy requests and refunds users
     * @notice Can only be called by the token agent. Processes multiple rejections in a batch.
     * @param _users Array of user addresses whose requests are being rejected
     * @param _tokenAddresses Array of token addresses for each request
     * @param _buyIds Array of buy request IDs to reject
     * @param _investmentIds Array of investment identifiers
     */
    function rejectBuyRequest(
        address[] calldata _users,
        address[] calldata _tokenAddresses,
        uint256[] calldata _buyIds,
        string[] calldata _investmentIds
    ) external nonReentrant {
        require(
            _users.length == _tokenAddresses.length &&
                _users.length == _buyIds.length &&
                _users.length == _investmentIds.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < _users.length; i++) {
            _processRejection(
                _users[i],
                _tokenAddresses[i],
                _buyIds[i],
                _investmentIds[i]
            );
        }
    }

    /**
     * @dev Creates a new request and stores it in the requestInfo mapping
     * @notice Increments the user's request count for the token and stores request details
     * @param _buyType The type of the buy (0 for USDC, 1 for USDT)
     * @param _tokenAddress The address of the token being requested
     * @param _buyAmount The amount of buy tokens spent
     * @param _tokenAmount The calculated amount of tokens to receive
     * @param _platformFee The platform fee amount
     * @param _oneTimeFee The one-time fee amount
     * @return _requestId The created request ID (incremented from previous count)
     */
    function _createRequest(
        uint8 _buyType,
        address _tokenAddress,
        uint256 _buyAmount,
        uint256 _tokenAmount,
        uint256 _platformFee,
        uint256 _oneTimeFee
    ) internal returns (uint256) {
        uint256 _requestId = userRequestCount[msg.sender][_tokenAddress];
        userRequestCount[msg.sender][_tokenAddress]++;

        requestInfo[msg.sender][_tokenAddress][_requestId] = FactoryLib
            .RequestInfo(
                _buyType,
                _tokenAddress,
                _buyAmount,
                _tokenAmount,
                _platformFee,
                _oneTimeFee,
                FactoryLib.Status.Pending
            );

        return _requestId;
    }

    /**
     * @dev Processes non-pledged request: validates and transfers fees
     * @notice Validates the request exists, matches token amount, and hasn't been completed/rejected.
     *         Marks request as completed and transfers platform fee + one-time fee to receiver.
     * @param _user The user address who made the request
     * @param _tokenAddress The token address for the request
     * @param _buyId The buy request ID
     */
    function _processNonPledgedRequest(
        address _user,
        address _tokenAddress,
        uint256 _buyId
    ) internal returns (uint256 _tokenAmount) {
        require(
            _buyId < userRequestCount[_user][_tokenAddress],
            "Invalid buy ID"
        );

        FactoryLib.RequestInfo storage _requestInfo = requestInfo[_user][
            _tokenAddress
        ][_buyId];
        require(
            _requestInfo.tokenAddress != address(0),
            "Request does not exist"
        );

        _tokenAmount = _requestInfo.tokenAmount;

        require(
            _requestInfo.status == FactoryLib.Status.Pending,
            "Request should be in pending state"
        );

        _requestInfo.status = FactoryLib.Status.Completed;

        factory.transferTokens(
            _requestInfo.buyType == 0 ? usdcToken : usdtToken,
            receiverAddress,
            _requestInfo.platformFee + _requestInfo.oneTimeFee
        );
    }

    /**
     * @dev Processes token distribution and emits event
     * @notice Calculates gross mint amount, updates token bought amount, and distributes category shares.
     *         Emits MintRequestAccepted event with category percentage information.
     * @param _user The user address receiving tokens
     * @param _category The category of the token
     * @param _tokenAddress The token address being distributed
     * @param _tokenAmount The base token amount (before gross mint calculation)
     * @param _buyId The buy request ID
     * @param _investmentId The investment identifier
     */
    function _processTokenDistribution(
        address _user,
        FactoryLib.TokenCategory _category,
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _buyId,
        string memory _investmentId
    ) internal {
        uint256 _grossMintAmount = factory.calculateGrossMintAmount(
            _category,
            _tokenAddress,
            _tokenAmount
        );

        factory.updateTokenBought(_tokenAddress, _grossMintAmount);

        FactoryLib.CategoryPercentage memory _categoryPercentage = factory
            .transferCategoryShares(
                _category,
                _user,
                _tokenAddress,
                _tokenAmount
            );

        emit MintRequestAccepted(
            _tokenAddress,
            _user,
            _buyId,
            _tokenAmount,
            _investmentId,
            _categoryPercentage
        );
    }

    /**
     * @dev Validates token request parameters
     * @notice Checks that token exists, buy amount is within minimum and maximum investment limits
     * @param _tokenAddress The address of the token to validate
     * @param _buyAmount The buy amount to validate against token limits
     * @return _tokenInfo The validated token information struct
     */
    function _validateTokenRequest(
        address _tokenAddress,
        uint256 _buyAmount
    ) internal view returns (FactoryLib.TokenInfo memory) {
        FactoryLib.TokenInfo memory _tokenInfo = factory.getTokenInfo(
            _tokenAddress
        );
        require(_tokenInfo.tokenAddress != address(0), "Token does not exist");
        require(
            _buyAmount >= _tokenInfo.minimumInvestment,
            "Insufficient amount"
        );
        require(
            _buyAmount <= _tokenInfo.maximumInvestment,
            "Exceeds maximum investment"
        );
        return _tokenInfo;
    }

    /**
     * @dev Validates rejection request parameters
     * @notice Checks user address, buy ID validity, request existence, token existence, agent authorization, and that request hasn't been rejected
     * @param _user The user address who made the request
     * @param _tokenAddress The token address for the request
     * @param _buyId The buy request ID to validate
     * @return _requestInfo The request info storage reference for further processing
     */
    function _validateRejectRequest(
        address _user,
        address _tokenAddress,
        uint256 _buyId
    ) internal view returns (FactoryLib.RequestInfo storage _requestInfo) {
        require(_user != address(0), "Invalid user address");
        require(
            _buyId < userRequestCount[_user][_tokenAddress],
            "Invalid buy ID"
        );

        _requestInfo = requestInfo[_user][_tokenAddress][_buyId];
        require(
            _requestInfo.tokenAddress != address(0),
            "Request does not exist"
        );

        FactoryLib.TokenInfo memory _tokenInfo = factory.getTokenInfo(
            _requestInfo.tokenAddress
        );
        require(_tokenInfo.tokenAddress != address(0), "Token does not exist");
        require(_tokenInfo.agent == msg.sender, "Not the agent of the token");
        require(
            _requestInfo.status == FactoryLib.Status.Pending,
            "Request should be in pending state"
        );
    }

    /**
     * @dev Processes the rejection: marks as rejected and transfers funds
     * @notice Marks request as rejected, refunds buy amount + platform fee to user,
     *         transfers one-time fee to receiver, and emits MintRequestRejected event
     * @param _user The user address whose request is being rejected
     * @param _tokenAddress The token address for the request
     * @param _buyId The buy request ID to reject
     * @param _investmentId The investment identifier
     */
    function _processRejection(
        address _user,
        address _tokenAddress,
        uint256 _buyId,
        string memory _investmentId
    ) internal {
        FactoryLib.RequestInfo storage _requestInfo = _validateRejectRequest(
            _user,
            _tokenAddress,
            _buyId
        );

        _requestInfo.status = FactoryLib.Status.Rejected;
        factory.updateTokenLocked(
            _requestInfo.tokenAddress,
            _requestInfo.tokenAmount,
            false
        );

        IERC20MetadataMintable _buyToken = _getBuyToken(_requestInfo.buyType);

        // Refund user: full buy amount minus non-refundable one-time fee
        factory.transferTokens(
            _buyToken,
            _user,
            _requestInfo.buyAmount - _requestInfo.oneTimeFee
        );

        factory.transferTokens(
            _buyToken,
            receiverAddress,
            _requestInfo.oneTimeFee
        );

        emit MintRequestRejected(
            _requestInfo.tokenAddress,
            _user,
            _buyId,
            _investmentId
        );
    }

    /**
     * @dev Calculates platform fee and one-time fee for a token purchase
     * @notice Checks UserManager for existing one-time fee status before applying fee
     * @param _buyAmount The amount of buy tokens being spent
     * @param _tokenInfo The token information containing platform fee percentage
     * @return _platformFee The calculated platform fee amount
     * @return _oneTimeFee The one-time fee (0 if already paid, otherwise oneTimeFee)
     */
    function _getFeeAmounts(
        uint256 _buyAmount,
        FactoryLib.TokenInfo memory _tokenInfo
    ) internal returns (uint256 _platformFee, uint256 _oneTimeFee) {
        _platformFee = (_buyAmount * _tokenInfo.platformFee) / 100_00;

        IUserManager.UserOneTimeFee
            memory _userOneTimeFeeInUserManager = userManager.userOneTimeFee(
                msg.sender
            );

        if (userOneTimeFee[msg.sender].completeStatus) {
            _oneTimeFee = 0;
        } else if (_userOneTimeFeeInUserManager.completeStatus) {
            userOneTimeFee[msg.sender].completeStatus = true;
            _oneTimeFee = 0;
        } else {
            userOneTimeFee[msg.sender].feeAmount = userManager.oneTimeFee();
            userOneTimeFee[msg.sender].completeStatus = true;
            _oneTimeFee = userManager.oneTimeFee();
        }
    }

    /**
     * @dev Gets the buy token based on the buy type
     * @param _buyType The type of the buy (0 for USDC, 1 for USDT)
     * @return The buy token contract
     */
    function _getBuyToken(
        uint8 _buyType
    ) internal view returns (IERC20MetadataMintable) {
        return _buyType == 0 ? usdcToken : usdtToken;
    }

    function transferRequestManagerOwnership(
        address _newOwner
    ) public onlyOwner {
        transferOwnership(_newOwner);
    }
}
