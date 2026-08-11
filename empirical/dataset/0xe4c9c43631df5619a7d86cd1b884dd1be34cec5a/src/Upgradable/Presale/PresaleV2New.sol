//SPDX-License-Identifier: MIT
//               _    _____                                        _
// __      _____| |__|___ / _ __   __ _ _   _ _ __ ___   ___ _ __ | |_ ___
// \ \ /\ / / _ \ '_ \ |_ \| '_ \ / _` | | | | '_ ` _ \ / _ \ '_ \| __/ __|
//  \ V  V /  __/ |_) |__) | |_) | (_| | |_| | | | | | |  __/ | | | |_\__ \
//   \_/\_/ \___|_.__/____/| .__/ \__,_|\__, |_| |_| |_|\___|_| |_|\__|___/
//                         |_|          |___/
//
pragma solidity 0.8.28;

import {Initializable, PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

/// @notice ERC20 token metadata interface to fetch decimals, allowance and to approve
interface IERC20 {
    function decimals() external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface Aggregator {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface StakingManager {
    function depositByPresale(address _user, uint256 _amount) external;
}

interface ISanctionsList {
    function isSanctioned(address addr) external view returns (bool);
}

interface INFT {
    function safeMint(address to) external returns (uint256);
}

error ZeroAddress();
error InvalidTime();
error ArrayLengthMismatch();
error NotEnoughTokens();
error WertNotWhitelisted();
error UserNotWhitelisted();
error ClaimNotStarted();
error Claimed();
error NotInSale();
error ExcessTokens();
error PaymentFailed();
error InvalidSplitPercentage();
error CannotSetClaim();
error NotAuthorized();
error AddressInSanctionList();
error BlacklistedUser();
error IndexOutOfBounds();

/// @title PresaleV2New
/// @notice
/// Upgradeable multi-round presale contract supporting:
/// - ETH / USDT / USDC purchases
/// - Wert-based purchases
/// - Optional auto-staking on purchase or claim
/// - Dynamic round timing
/// - Revenue split across multiple wallets
/// - Sanctions enforcement and blacklist logic
///
/// @dev
/// - Uses cumulative round caps (`rounds[0]`)
/// - Prices are USD-denominated (`rounds[1]`) with 1e18 precision
/// - ETH pricing is fetched from Chainlink oracle
/// - Token accounting internally uses 18 decimals (`baseDecimals`)
contract PresaleV2New is Initializable, ReentrancyGuardTransientUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    uint256 public totalTokensSold;
    uint256 public startTime;
    uint256 public claimStart;
    address public saleToken;
    uint256 public baseDecimals;
    uint256 public currentStep;
    uint256 public checkPoint;
    uint256 public usdRaised;
    uint256 public timeConstant;
    uint256 public totalBoughtAndStaked;
    uint256[][3] public rounds;
    uint256[] public remainingTokensTracker;
    uint256[] public percentages; //Supports upto 3 decimal places, 4% = 4000
    address[] public wallets;
    address public paymentWallet;
    address public admin;
    bool public dynamicTimeFlag;
    bool public whitelistClaimOnly;

    IERC20 public USDTInterface;
    Aggregator public aggregatorInterface;
    mapping(address => uint256) public userDeposits;
    mapping(address => bool) public hasClaimed;
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public wertWhitelisted;

    StakingManager public stakingManagerInterface;
    ISanctionsList public sanctionsList;
    bool public applySanctions;

    IERC20 public USDCInterface;
    uint256 public claimAndStakedTokens;
    uint256 public externalUsers;
    uint256 public externalDeposits;

    uint256 constant PECENTAGE_CONST = 100_000;

    address public nftMint;

    enum NftMintType {
        None,
        ForWertBuys,
        ForAllBuys
    }

    NftMintType public nftMintType;

    uint256 public totalBonusAdded;

    struct BonusTier {
        uint256 upperLimitInUSD; //In 10^18
        uint256 bonusPercentage; //In 10^3
    }

    mapping(address => uint256) public userBonus;

    BonusTier[] public bonusTiers;
    bool public enableBonuses;

    event SaleTimeSet(uint256 _start, uint256 timestamp);

    event TokensBought(
        address indexed user,
        uint256 indexed tokensBought,
        address indexed purchaseToken,
        uint256 amountPaid,
        uint256 usdEq,
        uint256 timestamp
    );
    event TokensAdded(address indexed token, uint256 noOfTokens, uint256 timestamp);
    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event ClaimStartUpdated(uint256 prevValue, uint256 newValue, uint256 timestamp);
    event TokensBoughtAndStaked(
        address indexed user,
        uint256 indexed tokensBought,
        address indexed purchaseToken,
        uint256 amountPaid,
        uint256 usdEq,
        uint256 timestamp
    );
    event TokensClaimedAndStaked(address indexed user, uint256 amount, uint256 timestamp);
    event BonusReceived(address indexed user, uint256 indexed tier, uint256 bonusAmount, uint256 usdAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev
     * Initializes the presale contract.
     * This function replaces the constructor for upgradeable deployments.
     *
     * Responsibilities:
     * - Sets oracle and payment tokens
     * - Initializes presale rounds
     * - Configures timing and dynamic round behavior
     * - Sets the primary payment wallet
     *
     * @param _oracle Chainlink-style ETH/USD price oracle address
     * @param _usdt USDT ERC20 token address
     * @param _usdc USDC ERC20 token address
     * @param _startTime Unix timestamp when presale starts
     * @param _rounds 3-slot array:
     *        [0] cumulative token caps per round
     *        [1] USD price per token per round (1e18 precision)
     *        [2] round end timestamps
     * @param _paymentWallet Wallet that receives funds when no split is defined
     * @param _dynamicTimeFlag Enables automatic time extension when rounds advance
     * @param _timeConstant Time (in seconds) added when dynamic timing is enabled
     */
    function initialize(
        address _oracle,
        address _usdt,
        address _usdc,
        uint256 _startTime,
        uint256[][3] memory _rounds,
        address _paymentWallet,
        bool _dynamicTimeFlag,
        uint256 _timeConstant
    ) external initializer {
        require(
            _oracle != address(0) && _usdt != address(0) && _usdc != address(0) && _paymentWallet != address(0),
            ZeroAddress()
        );
        require(_startTime >= block.timestamp, InvalidTime());
        __Pausable_init_unchained();
        __Ownable_init_unchained(msg.sender);
        __ReentrancyGuardTransient_init();
        baseDecimals = (10 ** 18);
        aggregatorInterface = Aggregator(_oracle);
        USDTInterface = IERC20(_usdt);
        USDCInterface = IERC20(_usdc);
        startTime = _startTime;
        rounds = _rounds;
        paymentWallet = _paymentWallet;
        dynamicTimeFlag = _dynamicTimeFlag;
        timeConstant = _timeConstant;
        emit SaleTimeSet(startTime, block.timestamp);
    }

    //************************ Buy Functions ************************//

    /**
     * @dev
     * Allows a user to purchase presale tokens using USDT.
     *
     * Flow:
     * - Validates sale conditions
     * - Calculates USD cost
     * - Optionally stakes tokens immediately
     * - Splits received USDT according to configured wallets
     *
     * @param _amount Number of presale tokens to purchase (whole units)
     * @param _stake If true, tokens are staked immediately via staking manager
     *
     * @return success Boolean indicating successful execution
     */
    function buyWithUSDT(uint256 _amount, bool _stake) external whenNotPaused returns (bool) {
        _checkSaleConditions(_amount, msg.sender);
        return _buyAndStakeHelper(_amount, address(USDTInterface), msg.sender, _stake, false);
    }

    /**
     * @dev
     * Allows a user to purchase presale tokens using USDC.
     *
     * @param _amount Number of presale tokens to purchase
     * @param _stake Whether tokens should be staked immediately
     *
     * @return success Boolean indicating successful execution
     */
    function buyWithUSDC(uint256 _amount, bool _stake) external whenNotPaused returns (bool) {
        _checkSaleConditions(_amount, msg.sender);
        return _buyAndStakeHelper(_amount, address(USDCInterface), msg.sender, _stake, false);
    }

    /**
     * @dev
     * Allows a user to purchase presale tokens using native ETH.
     *
     * Requirements:
     * - `msg.value` must cover required ETH amount
     * - Excess ETH is refunded
     *
     * @param _amount Number of presale tokens to purchase
     * @param _stake Whether tokens should be staked immediately
     *
     * @return success Boolean indicating successful execution
     */
    function buyWithEth(uint256 _amount, bool _stake) external payable whenNotPaused nonReentrant returns (bool) {
        _checkSaleConditions(_amount, msg.sender);
        return _buyAndStakeHelper(_amount, address(0), msg.sender, _stake, false);
    }

    /**
     * @dev
     * Wert-powered ETH purchase executed by a whitelisted Wert relayer.
     *
     * @param _user End-user receiving presale tokens
     * @param _amount Number of presale tokens purchased
     * @param _stake Whether tokens should be staked immediately
     *
     * @return success Boolean indicating successful execution
     */
    function buyWithETHWert(address _user, uint256 _amount, bool _stake)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        _checkSaleConditions(_amount, _user);
        require(wertWhitelisted[msg.sender], WertNotWhitelisted());
        return _buyAndStakeHelper(_amount, address(0), _user, _stake, true);
    }

    /**
     * @dev
     * Wert-powered USDC purchase executed by a whitelisted Wert relayer.
     *
     * Excess allowance (if any) is refunded to the end-user.
     *
     * @param _user End-user receiving presale tokens
     * @param _amount Number of presale tokens purchased
     * @param _stake Whether tokens should be staked immediately
     *
     * @return success Boolean indicating successful execution
     */
    function buyWithUSDCWERT(address _user, uint256 _amount, bool _stake)
        external
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        _checkSaleConditions(_amount, _user);
        require(wertWhitelisted[msg.sender], WertNotWhitelisted());
        address usdc = address(USDCInterface);
        _buyAndStakeHelper(_amount, usdc, _user, _stake, true);
        uint256 allowanceVal = IERC20(usdc).allowance(msg.sender, address(this));
        if (allowanceVal > 0) {
            _transferFrom(usdc, _user, allowanceVal);
        }
        return true;
    }

    //************************ Claim Functions ************************//

    /**
     * @dev
     * Claims purchased presale tokens.
     *
     * Requirements:
     * - Claim must be enabled
     * - User must not be blacklisted
     * - User must not have claimed already
     * - If whitelist-only is enabled, user must be whitelisted
     *
     * @return success Boolean indicating successful execution
     */
    function claim() external whenNotPaused returns (bool) {
        require(!hasClaimed[msg.sender], Claimed());
        uint256 amount = userDeposits[msg.sender];
        _claimConditions(amount);
        require(block.timestamp >= claimStart, ClaimNotStarted());
        if (whitelistClaimOnly) {
            require(isWhitelisted[msg.sender], UserNotWhitelisted());
        }
        hasClaimed[msg.sender] = true;

        delete userDeposits[msg.sender];
        _transfer(saleToken, amount);
        emit TokensClaimed(msg.sender, amount, block.timestamp);
        return true;
    }

    /**
     * @dev
     * Claims purchased presale tokens and immediately stakes them.
     *
     * Tokens are transferred directly to the staking manager
     * and are not held by the user wallet.
     *
     * @return success Boolean indicating successful execution
     */
    function claimAndStake() external whenNotPaused returns (bool) {
        uint256 amount = userDeposits[msg.sender];
        _claimConditions(amount);

        delete userDeposits[msg.sender];
        claimAndStakedTokens += amount;
        stakingManagerInterface.depositByPresale(msg.sender, amount);
        emit TokensClaimedAndStaked(msg.sender, amount, block.timestamp);
        return true;
    }

    //************************ Buy Helpers - Internal Functions ************************//

    /**
     * @dev
     * Core purchase handler used by all buy paths.
     *
     * Responsibilities:
     * - Updates round state and accounting
     * - Converts USD price into payment token amount
     * - Routes tokens to staking or user deposits
     * - Handles fund distribution
     *
     * @param _amount Number of presale tokens purchased
     * @param _token Payment token address (address(0) for ETH)
     * @param _user Beneficiary of the purchase
     * @param _stake Whether tokens should be staked immediately
     * @param _isWertBuy Indicates Whether buy is via wert or not
     *
     * @return success Boolean indicating successful execution
     */
    function _buyAndStakeHelper(uint256 _amount, address _token, address _user, bool _stake, bool _isWertBuy)
        internal
        returns (bool)
    {
        uint256 usdAmount = _updateRoundDetailsOnBuy(_amount); //In 10^18
        uint256 tokenAmount = _getTokenAmount(usdAmount, _token);
        uint256 bonus = _updateAndGetUserBonus(_user, usdAmount, _amount);
        uint256 totalUserAmount = _amount * baseDecimals + bonus;
        checkAndMintNFT(_user, _isWertBuy);
        if (_stake) {
            stakingManagerInterface.depositByPresale(_user, totalUserAmount);
            totalBoughtAndStaked += _amount;
            emit TokensBoughtAndStaked(_user, _amount, _token, tokenAmount, usdAmount, block.timestamp);
        } else {
            userDeposits[_user] += totalUserAmount;
            emit TokensBought(_user, _amount, _token, tokenAmount, usdAmount, block.timestamp);
        }
        _splitFee(tokenAmount, _token, _user);
        return true;
    }

    function _updateAndGetUserBonus(address _user, uint256 _usdAmount, uint256 _tokensBought)
        internal
        returns (uint256)
    {

        if (!enableBonuses) return 0;

        (uint256 tier, uint256 bonusPercentage) = _calculateBonusTierForPurchase(_usdAmount);

        if (bonusPercentage != 0) {
            uint256 userBonusCalc = (_tokensBought * baseDecimals * bonusPercentage) / PECENTAGE_CONST;
            userBonus[_user] += userBonusCalc;
            totalBonusAdded += userBonusCalc;
            emit BonusReceived(_user, tier, userBonusCalc, _usdAmount);
            return userBonusCalc;
        }

        return 0;
    }

    function _calculateBonusTierForPurchase(uint256 _purchaseAmountInUSD)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 total = bonusTiers.length;

        for (uint256 i = 0; i < total; i++) {
            BonusTier memory tier = bonusTiers[i];
            if (_purchaseAmountInUSD < tier.upperLimitInUSD) {
                return (i, tier.bonusPercentage);
            }
        }

        return (0,0);
    }

    /**
     * @dev
     * Updates round state when tokens are purchased.
     *
     * Handles:
     * - Multi-round overflow purchases
     * - Round transitions
     * - Remaining token tracking
     * - USD accounting
     *
     * @param _amount Number of presale tokens being purchased
     *
     * @return usdAmount Total USD cost (1e18 precision)
     */
    function _updateRoundDetailsOnBuy(uint256 _amount) internal returns (uint256) {
        (
            uint256 usdAmount,
            uint256 tempCheckPoint,
            uint256 indexTillTimeSwitch,
            uint256 newCurrentStep,
            uint256 newUnsold
        ) = _getRoundBuyDetails(_amount);

        uint256 _currentStep = currentStep;

        if (newUnsold > 0) remainingTokensTracker.push(newUnsold);
        if (newUnsold == 0 && _currentStep != newCurrentStep) {
            remainingTokensTracker.push(0);
        }
        for (uint256 i = _currentStep + 1; i < newCurrentStep; i++) {
            if (i > indexTillTimeSwitch) remainingTokensTracker.push(0);
            else remainingTokensTracker.push(rounds[0][i] - rounds[0][i - 1]);
        }
        if (checkPoint != tempCheckPoint) checkPoint = tempCheckPoint;
        if (_currentStep != newCurrentStep) {
            currentStep = newCurrentStep;
            if (dynamicTimeFlag && newCurrentStep != rounds[0].length) {
                manageTimeDiff();
            }
        }

        totalTokensSold += _amount;
        usdRaised += usdAmount;
        return usdAmount;
    }

    /**
     * @dev
     * Calculates purchase impact across rounds without mutating state.
     *
     * @param _amount Number of presale tokens being purchased
     *
     * @return usdAmount Total USD cost
     * @return newCheckpoint Updated checkpoint after purchase
     * @return indexTillTimeSwitch Index where time-based round switch occurred
     * @return newCurrentStep Resulting round index after purchase
     * @return unsoldInOldRound Tokens remaining in previous round (if crossed)
     */
    function _getRoundBuyDetails(uint256 _amount) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        uint256 calculatedCurrentStep = checkForActualCurrentRound();
        uint256 totalRounds = rounds[0].length;
        require(calculatedCurrentStep < totalRounds, NotInSale());

        uint256 indexTillTimeSwitch = calculatedCurrentStep;

        uint256 unsoldInOldRound = 0;
        uint256 total;

        uint256 tempCheckPoint;
        uint256 cachedCheckPoint = checkPoint;

        if (calculatedCurrentStep != currentStep) {
            uint256 oldTotal = cachedCheckPoint == 0 ? totalTokensSold : cachedCheckPoint;
            unsoldInOldRound = rounds[0][currentStep] - oldTotal;
            indexTillTimeSwitch = calculatedCurrentStep - 1;
            total = rounds[0][indexTillTimeSwitch];
            tempCheckPoint = total + _amount;
        } else {
            (total, tempCheckPoint) =
                cachedCheckPoint == 0 ? (totalTokensSold, 0) : (cachedCheckPoint, cachedCheckPoint + _amount);
        }

        uint256 __amount = _amount;
        uint256 USDAmount = 0;
        uint256 newCurrentStep = calculatedCurrentStep;

        if (__amount + total >= rounds[0][calculatedCurrentStep]) {
            uint256 remaining = __amount;
            uint256 i;
            for (i = calculatedCurrentStep; i < totalRounds; i++) {
                uint256 maxInRound = rounds[0][i];
                uint256 totalTokensInCurrentRoundAlone = maxInRound - total;
                if (remaining > totalTokensInCurrentRoundAlone) {
                    USDAmount += totalTokensInCurrentRoundAlone * rounds[1][i];
                    remaining = remaining - totalTokensInCurrentRoundAlone;
                    total = maxInRound;
                } else {
                    USDAmount += remaining * rounds[1][i];
                    total += remaining;
                    tempCheckPoint = total;
                    if (remaining == totalTokensInCurrentRoundAlone) i++;
                    remaining = 0;
                    break;
                }
            }
            require(remaining == 0, ExcessTokens());
            newCurrentStep = i;
        } else {
            USDAmount = __amount * rounds[1][calculatedCurrentStep];
        }

        return (USDAmount, tempCheckPoint, indexTillTimeSwitch, newCurrentStep, unsoldInOldRound);
    }

    /**
     * @dev
     * Converts USD value into payment token amount.
     *
     * - ETH uses Chainlink price feed
     * - ERC20 uses token decimals
     *
     * @param _usdPrice USD value (1e18 precision)
     * @param _token Payment token address
     *
     * @return tokenAmount Amount of payment token required
     */
    function _getTokenAmount(uint256 _usdPrice, address _token) internal view returns (uint256) {
        if (_token == address(0)) {
            return (_usdPrice * baseDecimals) / getLatestPrice();
        } else {
            uint256 decimals = IERC20(_token).decimals();
            uint256 exp = (18 - decimals);
            return _usdPrice / (10 ** exp);
        }
    }

    /**
     * @dev
     * Splits incoming payment across configured wallets.
     *
     * @param _tokenAmount Payment amount
     * @param _token Payment token address
     * @param _user Buyer address (used for ETH refunds)
     */
    function _splitFee(uint256 _tokenAmount, address _token, address _user) internal {
        if (_token != address(0)) {
            _splitFeeInERC20(_tokenAmount, _token);
        } else {
            uint256 excess = _splitFeeInNativeToken(_tokenAmount);
            if (excess > 0) _transferInNativeToken(_user, excess);
        }
    }

    /**
     * @dev
     * Handles ETH payment splitting and refund of excess ETH.
     *
     * @param _tokenAmount Required ETH amount
     *
     * @return excess ETH refunded to buyer
     */
    function _splitFeeInNativeToken(uint256 _tokenAmount) internal returns (uint256) {
        require(msg.value >= _tokenAmount, NotEnoughTokens());
        uint256 len = wallets.length;

        if (len == 0) {
            _transferInNativeToken(paymentWallet, _tokenAmount);
        } else {
            uint256 tempCalc = 0;
            for (uint256 i = 0; i < len; i++) {
                uint256 amountToTransfer = (_tokenAmount * percentages[i]) / PECENTAGE_CONST;
                _transferInNativeToken(wallets[i], amountToTransfer);
                tempCalc += amountToTransfer;
            }
            uint256 rem = (_tokenAmount - tempCalc);
            if (rem > 0) {
                _transferInNativeToken(wallets[len - 1], rem);
            }
        }
        uint256 excess = msg.value - _tokenAmount;
        return excess;
    }

    /**
     * @dev
     * Handles ERC20 payment splitting.
     *
     * @param _tokenAmount Required ERC20 amount
     * @param _token ERC20 token address
     */
    function _splitFeeInERC20(uint256 _tokenAmount, address _token) internal {
        uint256 len = wallets.length;
        if (len == 0) {
            _transferFrom(_token, paymentWallet, _tokenAmount);
        } else {
            uint256 tempCalc = 0;
            for (uint256 i = 0; i < len; i++) {
                uint256 amountToTransfer = (_tokenAmount * percentages[i]) / PECENTAGE_CONST;
                _transferFrom(_token, wallets[i], amountToTransfer);
                tempCalc += amountToTransfer;
            }
            uint256 rem = (_tokenAmount - tempCalc);
            if (rem > 0) {
                _transferFrom(_token, wallets[len - 1], rem);
            }
        }
    }

    /**
     * @dev
     * Updates the end timestamp of the current round when dynamic timing is enabled.
     *
     * The new round end time is set to:
     * `block.timestamp + timeConstant`
     *
     * This function is invoked:
     * - Automatically when advancing rounds during a buy
     * - Manually when incrementing rounds via admin
     */
    function manageTimeDiff() internal {
        rounds[2][currentStep] = block.timestamp + timeConstant;
    }

    /**
     * @dev
     * Checks minting conditions and mints an NFT to the user if eligible.
     * - If `nftMintType` is `ForAllBuys`, an NFT is minted for every purchase.
     * - If `nftMintType` is `ForWertBuys`, an NFT is minted only when `_isWertBuy` is true.
     * - Does nothing for other mint types.
     *
     * @param _user The address of the user receiving the NFT.
     * @param _isWertBuy Boolean indicating whether the purchase was made via Wert.
     */
    function checkAndMintNFT(address _user, bool _isWertBuy) internal {
        NftMintType mintType = nftMintType;
        if (mintType == NftMintType.ForAllBuys || (mintType == NftMintType.ForWertBuys && _isWertBuy)) {
            INFT(nftMint).safeMint(_user);
        }
    }

    //********************* Owner Setter Function *********************/

    /**
     * @dev
     * Pauses all buy and claim operations.
     *
     * Callable only by the contract owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev
     * Unpauses the contract, re-enabling buy and claim operations.
     *
     * Callable only by the contract owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev
     * Configures revenue split wallets and their corresponding percentages.
     *
     * Requirements:
     * - `_walletsArray` and `_percentagesArray` must have equal length
     * - Each percentage must be greater than zero
     * - Total percentage must equal `PECENTAGE_CONST` (100%)
     *
     * Existing split configuration is fully replaced.
     *
     * @param _walletsArray List of wallet addresses to receive funds
     * @param _percentagesArray Corresponding split percentages
     */
    function updateSplits_oer(address[] memory _walletsArray, uint256[] memory _percentagesArray) public onlyOwner {
        uint256 len = _walletsArray.length;
        require(len == _percentagesArray.length, ArrayLengthMismatch());
        delete wallets;
        delete percentages;
        uint256 totalPercentage = 0;

        for (uint256 i = 0; i < len; i++) {
            require(_percentagesArray[i] > 0, InvalidSplitPercentage());
            totalPercentage += _percentagesArray[i];
        }

        require(totalPercentage == PECENTAGE_CONST, InvalidSplitPercentage());
        wallets = _walletsArray;
        percentages = _percentagesArray;
    }

    /**
     * @dev
     * Updates the staking manager contract address.
     *
     * Grants infinite approval of the sale token to the staking manager
     * to enable staking via `depositByPresale`.
     *
     * @param _stakingManagerAddress Address of the staking manager contract
     */
    function updateStakingManager_S2x(address _stakingManagerAddress) external onlyOwner {
        require(_stakingManagerAddress != address(0), ZeroAddress());
        stakingManagerInterface = StakingManager(_stakingManagerAddress);
        IERC20(saleToken).approve(_stakingManagerAddress, type(uint256).max);
    }

    /**
     * @dev
     * Initializes token claiming and staking functionality.
     *
     * Responsibilities:
     * - Sets claim start time
     * - Sets sale token address
     * - Enables whitelist-only claiming
     * - Transfers presale tokens into the contract
     * - Configures staking manager
     *
     * This function can only be called once.
     *
     * @param _claimStartTime Unix timestamp when claiming begins
     * @param _noOfTokens Total number of presale tokens supplied
     * @param _saleTokenAddress ERC20 token distributed in the presale
     * @param _stakingManagerAddress Address of staking manager contract
     *
     * @return success Boolean indicating successful execution
     */
    function startClaim_p8v(
        uint256 _claimStartTime,
        uint256 _noOfTokens,
        address _saleTokenAddress,
        address _stakingManagerAddress
    ) external onlyOwner returns (bool) {
        // require(claimStart == 0, CannotSetClaim());
        require(_stakingManagerAddress != address(0), ZeroAddress());
        claimStart = _claimStartTime;
        saleToken = _saleTokenAddress;
        whitelistClaimOnly = true;
        stakingManagerInterface = StakingManager(_stakingManagerAddress);
        IERC20(_saleTokenAddress).approve(_stakingManagerAddress, type(uint256).max);
        _transferFrom(_saleTokenAddress, address(this), _noOfTokens);
        emit TokensAdded(_saleTokenAddress, _noOfTokens, block.timestamp);
        return true;
    }

    /**
     * @dev
     * Updates the claim start timestamp.
     *
     * Requirements:
     * - Claim must have already been initialized
     * - New claim start must be after the final round end time
     * - New claim start must be in the future
     *
     * @param _claimStartTime New claim start timestamp
     *
     * @return success Boolean indicating successful execution
     */
    function updateClaimStart_T4b(uint256 _claimStartTime) external onlyOwner returns (bool) {
        require(claimStart > 0, CannotSetClaim());
        uint256 endTime = rounds[2][rounds[2].length - 1];
        require(_claimStartTime > endTime && _claimStartTime > block.timestamp, InvalidTime());
        uint256 prevValue = claimStart;
        claimStart = _claimStartTime;
        emit ClaimStartUpdated(prevValue, _claimStartTime, block.timestamp);
        return true;
    }

    /**
     * @dev
     * Updates Wert relayer whitelist status.
     *
     * Wert-whitelisted addresses are allowed to perform
     * purchases on behalf of users.
     *
     * @param _addressList List of addresses to update
     * @param _statusList Corresponding whitelist statuses
     */
    function updateWERTWhitelistStatus_2cr(address[] calldata _addressList, bool[] calldata _statusList)
        external
        onlyOwner
    {
        uint256 len = _addressList.length;
        require(len == _statusList.length, ArrayLengthMismatch());
        for (uint256 i = 0; i < len; i++) {
            wertWhitelisted[_addressList[i]] = _statusList[i];
        }
    }

    /**
     * @dev
     * Updates round configuration data.
     *
     * This overwrites all existing round caps, prices, and end times.
     *
     * @param _newRounds New round configuration array
     */
    function updateRoundsData_wPp(uint256[][3] memory _newRounds) external onlyOwner {
        rounds = _newRounds;
    }

    /**
     * @dev
     * Updates round configuration data of a particular round.
     *
     * @param _index Index at which update has to be made
     * @param _maxCap round cap for the round
     * @param _price price for the round
     * @param _endTime end time for the round
     */
    function updateRoundDetailsAtIndex_V3J(uint256 _index, uint256 _maxCap, uint256 _price, uint256 _endTime)
        external
        onlyOwner
    {
        require(rounds[0].length > _index, IndexOutOfBounds());
        rounds[0][_index] = _maxCap;
        rounds[1][_index] = _price;
        rounds[2][_index] = _endTime;
    }

    /**
     * @dev
     * Updates blacklist status for users.
     *
     * Blacklisted users are prevented from claiming tokens.
     *
     * @param _userInBlacklist List of user addresses
     * @param _statusList Corresponding blacklist statuses
     */
    function updateUserBlacklistStatus_ShV(address[] calldata _userInBlacklist, bool[] calldata _statusList)
        external
        onlyOwner
    {
        uint256 len = _userInBlacklist.length;
        require(len == _statusList.length, ArrayLengthMismatch());

        for (uint256 i = 0; i < len; i++) {
            isBlacklisted[_userInBlacklist[i]] = _statusList[i];
        }
    }

    /**
     * @dev
     * Updates claim whitelist status for users.
     *
     * Only whitelisted users can claim when
     * `whitelistClaimOnly` is enabled.
     *
     * @param _usersList List of user addresses
     * @param _statusList Corresponding whitelist statuses
     */
    function updateUserWhitelistStatus_G5K(address[] calldata _usersList, bool[] calldata _statusList)
        external
        onlyOwner
    {
        uint256 len = _usersList.length;
        require(len == _statusList.length, ArrayLengthMismatch());
        for (uint256 i = 0; i < len; i++) {
            isWhitelisted[_usersList[i]] = _statusList[i];
        }
    }

    /**
     * @dev
     * Updates the primary payment wallet.
     *
     * Used when no revenue split is configured.
     *
     * @param _newPaymentWallet Address of new payment wallet
     */
    function updatePaymentWallet__S3(address _newPaymentWallet) external onlyOwner {
        require(_newPaymentWallet != address(0), ZeroAddress());
        paymentWallet = _newPaymentWallet;
    }

    /**
     * @dev
     * Updates the time constant used for dynamic round timing.
     *
     * Value should be specified in seconds.
     *
     * @param _newTimeConstant New time constant
     */
    function updateTimeConstant_HuF(uint256 _newTimeConstant) external onlyOwner {
        timeConstant = _newTimeConstant;
    }

    /**
     * @dev
     * Seeds user deposits from an external source (e.g. BSC presale).
     *
     * Used to migrate or synchronize off-chain or cross-chain purchases.
     *
     * @param _users List of user addresses
     * @param _userDeposits Corresponding deposit amounts
     */
    function externalSeeder_Omh(address[] calldata _users, uint256[] calldata _userDeposits) external onlyOwner {
        uint256 len = _users.length; // cached loop length m-o
        require(len == _userDeposits.length, ArrayLengthMismatch());

        uint256 _externalDeposits = 0; // temporary variable

        for (uint256 i = 0; i < len; i++) {
            uint256 amount = _userDeposits[i]; // m-o
            userDeposits[_users[i]] += amount; // update user deposit
            _externalDeposits += amount; // accumulate locally
        }

        externalUsers += len; // add users count in the array
        externalDeposits += _externalDeposits; // single SSTORE
    }

    /**
     * @dev
     * Sets the admin address.
     *
     * Admin has limited permissions distinct from the owner.
     *
     * @param _newAdmin Address of the new admin
     */
    function updateAdmin_ftF(address _newAdmin) external onlyOwner {
        admin = _newAdmin;
    }

    /**
     * @dev
     * Manually updates the current round index and checkpoint.
     *
     * Intended for backend correction or emergency recovery.
     *
     * @param _step New current round index
     * @param _newCheckpoint New checkpoint value
     */
    function updateCurrentStep_W4o(uint256 _step, uint256 _newCheckpoint) external onlyOwner {
        currentStep = _step;
        checkPoint = _newCheckpoint;
    }

    /**
     * @dev
     * Enables or disables dynamic round timing.
     *
     * @param _status Boolean flag to toggle dynamic timing
     */
    function updateDynamicTimeFlag_4Lg(bool _status) external onlyOwner {
        dynamicTimeFlag = _status;
    }

    /**
     * @dev
     * Updates the remaining tokens tracker array.
     *
     * Callable by owner or admin only.
     * Used for manual reconciliation or backend sync.
     *
     * @param _unsoldTokensArray Array of remaining tokens per round
     */
    function updateRemainingTokensArray_N6A(uint256[] memory _unsoldTokensArray) public {
        require(msg.sender == admin || msg.sender == owner(), NotAuthorized());
        delete remainingTokensTracker;
        remainingTokensTracker = _unsoldTokensArray;
    }

    /**
     * @dev
     * Configures sanctions enforcement.
     *
     * When enabled, sanctioned addresses are blocked from purchasing.
     *
     * @param _sanctionContract Address of sanctions list contract
     * @param _applySanctionsBool Whether sanctions should be enforced
     */
    function updateSanctions_baF(address _sanctionContract, bool _applySanctionsBool) external onlyOwner {
        require(_sanctionContract != address(0), ZeroAddress());
        sanctionsList = ISanctionsList(_sanctionContract);
        applySanctions = _applySanctionsBool;
    }

    /**
     * @dev
     * Enables or disables whitelist-only claiming.
     *
     * @param _status Boolean flag to control whitelist-only claim behavior
     */
    function updateClaimWhitelistStatus_vsC(bool _status) external onlyOwner {
        whitelistClaimOnly = _status;
    }

    /**
     * @dev
     * Resets the presale, so it starts from begining
     *
     * This overwrites all existing rounds, removes the remianing token tracker
     * details, it resets current step and checkpoint
     *
     * @param _firstRoundEndTime End time of first round
     */
    function resetPresale_hBh(uint256 _firstRoundEndTime) external onlyOwner {
        rounds[2][0] = _firstRoundEndTime;
        delete remainingTokensTracker;
        currentStep = 0;
        checkPoint = 0;
    }

    /**
     * @dev
     * This function allows the contract owner to:
     * - Set a new NFT contract address used for minting.
     * - Update the minting condition type (e.g., for all buys or only Wert buys).
     *
     *
     * @param _nft The address of the NFT contract that implements the `INFT` interface.
     * @param _type The minting condition type to apply.
     *        - `NftMintType.ForWertBuys` → Mint only for Wert purchases.
     *        - `NftMintType.ForAllBuys` → Mint for all purchases.
     */
    function updateNFTMintDetails_oa_(address _nft, NftMintType _type) external onlyOwner {
        nftMint = _nft;
        nftMintType = _type;
    }

    function updateBonusTier(BonusTier[] memory _bonusTier) external onlyOwner {
        if (bonusTiers.length > 0) delete bonusTiers;
        uint256 len = _bonusTier.length;
        for (uint256 i = 0; i < len; i++) {
            bonusTiers.push(_bonusTier[i]);
        }
    }

    function updateEnableBonuses(bool _value) external onlyOwner {
        enableBonuses = _value;
    }

    //************************* Admin and Owner Setter Function ***********************//

    /**
     * @dev
     * Advances the current round index manually.
     *
     * Responsibilities:
     * - Finalizes remaining tokens for the current round
     * - Updates checkpoint
     * - Applies dynamic timing if enabled
     *
     * Callable by admin or owner only.
     */
    function incrementCurrentStep() external {
        require(msg.sender == admin || msg.sender == owner(), NotAuthorized());
        uint256 maxTokenToBuyInCurrentRound = rounds[0][currentStep];
        if (checkPoint < maxTokenToBuyInCurrentRound) {
            if (currentStep == 0) {
                remainingTokensTracker.push(maxTokenToBuyInCurrentRound - totalTokensSold);
            } else {
                remainingTokensTracker.push(maxTokenToBuyInCurrentRound - checkPoint);
            }
            checkPoint = maxTokenToBuyInCurrentRound;
        }
        currentStep++;
        if (dynamicTimeFlag && currentStep < rounds[0].length) {
            rounds[2][currentStep] = block.timestamp + timeConstant;
        }
    }

    //************************ Public View Functions ************************//

    /**
     * @dev
     * Returns latest ETH/USD price scaled to 1e18.
     *
     * @return price ETH price in USD (1e18 precision)
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price,,,) = aggregatorInterface.latestRoundData();
        price = (price * (10 ** 10));
        return uint256(price);
    }

    /**
     * @dev
     * Returns ETH amount required for purchasing given tokens.
     *
     * @param _amount Number of presale tokens
     *
     * @return ethAmount ETH required
     */
    function ethBuyHelper(uint256 _amount) external view returns (uint256 ethAmount) {
        (uint256 usdAmount,,,,) = _getRoundBuyDetails(_amount);
        ethAmount = _getTokenAmount(usdAmount, address(0));
    }

    /**
     * @dev
     * Calculates USDT required to purchase a given number of presale tokens.
     *
     * @param _amount Number of presale tokens
     *
     * @return usdPrice Required USDT amount
     */
    function usdtBuyHelper(uint256 _amount) external view returns (uint256 usdPrice) {
        (uint256 usdAmount,,,,) = _getRoundBuyDetails(_amount);
        usdPrice = _getTokenAmount(usdAmount, address(USDTInterface));
    }

    /**
     * @dev
     * Returns round data array by index.
     *
     * @param _no Index of the round data array
     *
     * @return Array containing round details
     */
    function roundDetails(uint256 _no) external view returns (uint256[] memory) {
        return rounds[_no];
    }

    /**
     * @dev
     * Returns the remaining tokens tracker array.
     *
     * @return Array of remaining token amounts per round
     */
    function trackRemainingTokens() external view returns (uint256[] memory) {
        return remainingTokensTracker;
    }

    /**
     * @dev
     * Determines the actual active round based on time and sold tokens.
     *
     * @return index Current active round index
     */
    function checkForActualCurrentRound() public view returns (uint256) {
        uint256 len = rounds[0].length;
        uint256 total = checkPoint == 0 ? totalTokensSold : checkPoint;
        for (uint256 i = currentStep; i < len; i++) {
            //In case round ended
            if (block.timestamp < rounds[2][i] && total < rounds[0][i]) {
                return i;
            }
        }
        return len;
    }

    /**
     * @dev
     * Returns the maximum number of tokens that can be purchased
     * across the current and next round.
     *
     * @return maxTokens Maximum purchasable token amount
     */
    function maxTokensToBuy() external view returns (uint256) {
        uint256 index = checkForActualCurrentRound();
        uint256 len = rounds[0].length;
        if (index == len) return 0;

        uint256 prevRoundTotal = (index == 0) ? 0 : rounds[0][index - 1];
        if (index == len - 1) return rounds[0][index] - prevRoundTotal;
        else return rounds[0][index + 1] - prevRoundTotal;
    }

    //************************ Validation functions ************************//

    /**
     * @dev
     * Validates sale conditions before allowing a purchase.
     *
     * Checks:
     * - Sale start time
     * - Non-zero amount
     * - Sanctions compliance (if enabled)
     *
     * @param _amount Number of tokens to purchase
     * @param _user Buyer address
     */
    function _checkSaleConditions(uint256 _amount, address _user) private view {
        require(block.timestamp >= startTime, InvalidTime());

        require(_amount > 0, NotEnoughTokens());
        if (applySanctions) {
            require(!sanctionsList.isSanctioned(_user), AddressInSanctionList());
        }
    }

    /**
     * @dev
     * Validates claim conditions before allowing a claim.
     *
     * Checks:
     * - Claim has started
     * - User is not blacklisted
     */
    function _claimConditions(uint256 _amount) private view {
        require(saleToken != address(0), ClaimNotStarted());
        require(!isBlacklisted[msg.sender], BlacklistedUser());
        require(_amount > 0, NotEnoughTokens());
    }

    //************************ Assembly functions ************************//

    /**
     * @dev
     * Transfers native ETH to a recipient address.
     *
     * Uses low-level `call` to forward all remaining gas.
     * Reverts if the transfer fails.
     *
     * @param _recipient Address receiving the ETH
     * @param _amount Amount of ETH to transfer (in wei)
     */
    function _transferInNativeToken(address _recipient, uint256 _amount) internal {
        bool success;
        assembly {
            success := call(
                gas(), // forward all remaining gas
                _recipient, // to
                _amount, // value
                0, // in offset
                0, // in size
                0, // out offset
                0 // out size
            )
        }
        require(success, PaymentFailed());
    }

    /**
     * @dev
     * Transfers ERC20 to a recipient address from the msg.sender.
     *
     * Uses low-level `call` to forward all remaining gas.
     * Reverts if the transfer fails.
     *
     * @param _token Address of the receiving  token
     * @param _to Address receiving the token
     * @param _amount Amount of token to transfer (in wei)
     */
    function _transferFrom(address _token, address _to, uint256 _amount) internal {
        assembly {
            let freeMemoryPointer := mload(0x40)

            // transferFrom(address,address,uint256) = 0x23b872dd
            mstore(freeMemoryPointer, hex"23b872dd")
            mstore(add(freeMemoryPointer, 0x04), caller())
            mstore(add(freeMemoryPointer, 0x24), _to)
            mstore(add(freeMemoryPointer, 0x44), _amount)

            if iszero(call(gas(), _token, 0, freeMemoryPointer, 0x64, 0, 0)) { revert(0, 0) }
        }
    }

    /**
     * @dev
     * Transfers ERC20 from the contract to the msg.sender.
     *
     * Uses low-level `call` to forward all remaining gas.
     * Reverts if the transfer fails.
     *
     * @param _token Address of the receiving  token
     * @param _amount Amount of token to transfer (in wei)
     */
    function _transfer(address _token, uint256 _amount) internal {
        assembly {
            let freeMemoryPointer := mload(0x40)

            // transfer(address,uint256) = a9059cbb
            mstore(freeMemoryPointer, hex"a9059cbb")
            mstore(add(freeMemoryPointer, 0x04), caller())
            mstore(add(freeMemoryPointer, 0x24), _amount)

            if iszero(call(gas(), _token, 0, freeMemoryPointer, 0x64, 0, 0)) { revert(0, 0) }
        }
    }
}
