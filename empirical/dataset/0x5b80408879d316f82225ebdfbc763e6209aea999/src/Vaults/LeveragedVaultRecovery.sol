// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import "../Dependencies/EbisuUpgradeableV2.sol";
import "../Interfaces/IAddressesRegistry.sol";
import "../Interfaces/IEbisuAdminRegistry.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/ITroveManager.sol";
import "../Interfaces/ITroveNFT.sol";
import "../Zappers/Interfaces/ILeverageZapper.sol";
import "../Zappers/Interfaces/IExchangeHelpersV2.sol";
import "../Types/LatestTroveData.sol";
import "../Dependencies/Constants.sol";
import "./Interfaces/ILeveragedVault.sol";
import "./Interfaces/IVaultPriceFeed.sol";

/**
 * @title LeveragedVault
 * @notice ERC4626 vault that manages a leveraged trove position
 * @dev Users deposit collateral, vault maintains target leverage using existing LeverageZapper
 */
contract LeveragedVaultRecovery is 
    ERC4626Upgradeable, 
    EbisuUpgradeableV2, 
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721Receiver
{
    using SafeERC20 for IERC20;

    // ============================================
    // Constants
    // ============================================
    
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice Buffer for leverUp BOLD calculation (0.1% for quoter rounding differences)
    uint256 public constant LEVER_UP_BUFFER_BPS = 10;
    
    /// @notice Maximum allowed slippage for leverage operations (2%)
    uint256 public constant MAX_SLIPPAGE_BPS = 200;
    
    /// @notice Deposit fee in basis points (0.25%) - protects existing shareholders from slippage
    uint256 public constant DEPOSIT_FEE_BPS = 25;

    /// @notice Share multiplier for initial mint (1 Asset Token = 1000 vault tokens displayed)
    uint256 public constant SHARE_MULTIPLIER = 1000;

    // ============================================
    // State Variables
    // ============================================
    
    /// @notice The trove ID managed by this vault
    uint256 public troveId;
    
    /// @notice Target leverage ratio in 18 decimals (e.g., 2e18 for 2x)
    uint256 public targetLeverageX18;
    
    /// @notice The leverage zapper contract
    ILeverageZapper public leverageZapper;
    
    /// @notice Addresses registry for this branch
    IAddressesRegistry public addressesRegistry;
    
    /// @notice Cached protocol contracts
    IBorrowerOperations public borrowerOperations;
    ITroveManager public troveManager;
    ITroveNFT public troveNFT;
    IERC20 public collToken;
    
    /// @notice Exchange helpers for accurate swap quotes
    IExchangeHelpersV2 public exchangeHelpers;
    
    /// @notice Authorized keepers that can call rebalance
    mapping(address => bool) public authorizedKeepers;
    
    /// @notice Authorized addresses that can adjust target leverage
    mapping(address => bool) public authorizedLeverageAdjusters;
    
    /// @notice Minimum deposit amount to avoid dust (set per collateral type)
    uint256 public minDeposit;

    /// @notice Vault price feed for view functions (provides fresh Chainlink prices)
    IVaultPriceFeed public vaultPriceFeed;

    /// @notice Security manager for emergency pause functionality
    address public securityManager;

    /// @notice Rebalance threshold in basis points (5% default)
    uint256 public rebalanceThresholdBps;
    
    // ============================================
    // Events
    // ============================================
    
    event TroveReceived(uint256 indexed troveId, address indexed from);
    event Rebalanced(uint256 oldLeverage, uint256 newLeverage);
    event LeverUpExecuted(uint256 flashLoanAmount, uint256 boldAmount);
    event LeverDownExecuted(uint256 flashLoanAmount, uint256 minBoldAmount);
    event TargetLeverageUpdated(uint256 oldLeverage, uint256 newLeverage);
    event KeeperUpdated(address indexed keeper, bool authorized);
    event LeverageAdjusterUpdated(address indexed adjuster, bool authorized);
    event DepositFeeCollected(address indexed depositor, uint256 feeAmount);
    event RebalanceThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event IdleCollateralSwept(uint256 amount);

    // ============================================
    // Errors
    // ============================================
    
    error TroveAlreadySet();
    error TroveNotSet();
    error InvalidTroveNFT();
    error ZeroAddress();
    error InvalidLeverage();
    error DepositTooSmall();
    error TroveUnderwater();
    error SlippageTooHigh(uint256 actualSlippageBps, uint256 maxSlippageBps);
    error UnauthorizedKeeper();
    error UnauthorizedLeverageAdjuster();
    error InvalidMinDeposit();
    error OracleDown();
    error PriceMismatch(uint256 fetchedPrice, uint256 viewPrice);
    error InvalidPrice();
    error UnauthorizedTroveTransfer();
    error UnauthorizedSecurityManager();
    error InvalidRebalanceThreshold();

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @notice Ensures oracle price is fresh and consistent before share calculations
     * @dev Calls fetchPrice() and validates that getPrice() returns the same value.
     *      Reverts if oracle is down or prices don't match (protects against edge cases).
     */
    modifier refreshPrice() {
        (uint256 fetchedPrice, bool oracleDown) = vaultPriceFeed.fetchPrice();
        if (oracleDown) revert OracleDown();
        uint256 viewPrice = vaultPriceFeed.getPrice();
        if (viewPrice != fetchedPrice) revert PriceMismatch(fetchedPrice, viewPrice);
        _;
    }

    /**
     * @notice Restricts access to the security manager or ebisu admin
     * @dev Used for emergency pause functionality
     */
    modifier onlySecurityManagerOrAdmin() {
        if (msg.sender != securityManager && msg.sender != _ebisuAdminRegistry.ebisuAdmin()) {
            revert UnauthorizedSecurityManager();
        }
        _;
    }

    /**
     * @notice Restricts access to authorized keepers, security manager, or ebisu admin
     * @dev Used for rebalance operations
     */
    modifier onlyKeeperOrAdmin() {
        if (!authorizedKeepers[msg.sender] && 
            msg.sender != securityManager && 
            msg.sender != _ebisuAdminRegistry.ebisuAdmin()) {
            revert UnauthorizedKeeper();
        }
        _;
    }

    /**
     * @notice Restricts access to authorized leverage adjusters, security manager, or ebisu admin
     * @dev Used for target leverage updates
     */
    modifier onlyLeverageAdjusterOrAdmin() {
        if (!authorizedLeverageAdjusters[msg.sender] && 
            msg.sender != securityManager &&
            msg.sender != _ebisuAdminRegistry.ebisuAdmin()) {
            revert UnauthorizedLeverageAdjuster();
        }
        _;
    }

    // ============================================
    // Storage Gap
    // ============================================
    
    uint256[40] private __gap;

    // ============================================
    // Constructor & Initializer
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vault
     * @param _addressesRegistry The addresses registry for this branch
     * @param _leverageZapper The leverage zapper contract
     * @param _exchangeHelpers The exchange helpers contract for accurate quotes
     * @param _vaultPriceFeed The vault price feed for price queries
     * @param _ebisuAdminRegistry_ The admin registry for upgrade authorization
     * @param _securityManager The security manager for emergency pause functionality
     * @param _targetLeverageX18 Target leverage in 18 decimals (e.g., 2e18 for 2x)
     * @param _minDeposit Minimum deposit amount to avoid dust (set per collateral type)
     * @param _name Vault token name
     * @param _symbol Vault token symbol
     */
    function initialize(
        IAddressesRegistry _addressesRegistry,
        ILeverageZapper _leverageZapper,
        IExchangeHelpersV2 _exchangeHelpers,
        IVaultPriceFeed _vaultPriceFeed,
        IEbisuAdminRegistry _ebisuAdminRegistry_,
        address _securityManager,
        uint256 _targetLeverageX18,
        uint256 _minDeposit,
        string memory _name,
        string memory _symbol
    ) external initializer {
        if (address(_addressesRegistry) == address(0) || 
            address(_leverageZapper) == address(0) ||
            address(_exchangeHelpers) == address(0) ||
            address(_vaultPriceFeed) == address(0) ||
            address(_ebisuAdminRegistry_) == address(0) ||
            _securityManager == address(0)) {
            revert ZeroAddress();
        }
        // Minimum leverage is 1.1x (1.1e18), typical range is 1.5x to 5x
        if (_targetLeverageX18 < 11e17 || _targetLeverageX18 > 10e18) {
            revert InvalidLeverage();
        }
        if (_minDeposit == 0) {
            revert InvalidMinDeposit();
        }

        // Cache addresses from registry
        addressesRegistry = _addressesRegistry;
        leverageZapper = _leverageZapper;
        exchangeHelpers = _exchangeHelpers;
        vaultPriceFeed = _vaultPriceFeed;
        _ebisuAdminRegistry = _ebisuAdminRegistry_;
        securityManager = _securityManager;
        targetLeverageX18 = _targetLeverageX18;
        minDeposit = _minDeposit;
        rebalanceThresholdBps = 500; // Default 5%
        
        borrowerOperations = _addressesRegistry.borrowerOperations();
        troveManager = _addressesRegistry.troveManager();
        troveNFT = _addressesRegistry.troveNFT();
        collToken = IERC20(address(_addressesRegistry.collToken()));

        // Initialize parent contracts
        __ERC4626_init(IERC20Upgradeable(address(collToken)));
        __ERC20_init(_name, _symbol);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        // Set deployer as initial keeper and leverage adjuster
        authorizedKeepers[msg.sender] = true;
        authorizedLeverageAdjusters[msg.sender] = true;

        // Approve collateral to zapper and borrowerOperations for leverage operations
        collToken.approve(address(_leverageZapper), type(uint256).max);
        collToken.approve(address(borrowerOperations), type(uint256).max);
    }

    // ============================================
    // IERC721Receiver Implementation
    // ============================================

    /**
     * @notice Receive trove NFT and set up permissions
     * @dev After receiving, sets zapper as manager so vault can use leverUp/Down
     *      Also mints initial shares to the depositor based on trove's net equity
     */
    function onERC721Received(
        address /* operator */,
        address from,
        uint256 tokenId,
        bytes calldata /* data */
    ) external override returns (bytes4) {
        // Only accept from the correct TroveNFT contract
        if (msg.sender != address(troveNFT)) {
            revert InvalidTroveNFT();
        }
        
        // Only authorized keepers can transfer trove to this vault
        if (!authorizedKeepers[from]) {
            revert UnauthorizedTroveTransfer();
        }
        
        // Only accept one trove per vault
        if (troveId != 0) {
            revert TroveAlreadySet();
        }

        troveId = tokenId;

        // Note: Zapper permissions should already be set during trove creation
        // The trove creator must set addManager=zapper, removeManager=zapper, receiver=zapper
        // when calling openLeveragedTrove to allow the vault to use leverUp/leverDown

        // Mint initial shares to the trove depositor
        // Shares equal the net equity multiplied by SHARE_MULTIPLIER (1 Asset Token = 1000 vault tokens)
        uint256 initialAssets = totalAssets();
        if (initialAssets > 0) {
            _mint(from, initialAssets * SHARE_MULTIPLIER);
        }

        emit TroveReceived(tokenId, from);
        
        return IERC721Receiver.onERC721Received.selector;
    }

    // ============================================
    // ERC4626 Overrides
    // ============================================

    /**
     * @notice Returns total assets (net equity) in collateral units
     * @dev Net equity = entireColl - (entireDebt / price)
     */
    function totalAssets() public view virtual override returns (uint256) {
        LatestTroveData memory troveData = troveManager.getLatestTroveData(troveId);
        uint256 price = _getViewPrice();
        
        if (price == 0) {
            return 0;
        }

        // Net equity in collateral = entireColl - (entireDebt / price)
        uint256 debtInColl = (troveData.entireDebt * DECIMAL_PRECISION) / price;
        
        if (troveData.entireColl <= debtInColl) {
            return 0;
        }
        
        return troveData.entireColl - debtInColl;
    }

    /**
     * @notice Preview shares received for a deposit, accounting for deposit fee
     * @dev Overrides ERC4626 to apply deposit fee before share calculation
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = (assets * DEPOSIT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 netAssets = assets - fee;
        return _convertToShares(netAssets, MathUpgradeable.Rounding.Down);
    }

    /**
     * @notice Preview assets needed to mint shares, accounting for deposit fee
     * @dev Overrides ERC4626 to account for deposit fee in asset calculation
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 assetsNeeded = _convertToAssets(shares, MathUpgradeable.Rounding.Up);
        // Inverse of fee: assets = netAssets / (1 - feeRate) = netAssets * 10000 / (10000 - feeBps)
        return (assetsNeeded * BPS_DENOMINATOR) / (BPS_DENOMINATOR - DEPOSIT_FEE_BPS);
    }

    /**
     * @notice Deposit collateral assets and receive vault shares
     * @dev Refreshes oracle price before share calculation to ensure fair pricing
     */
    function deposit(uint256 assets, address receiver) public virtual override refreshPrice returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Mint exact amount of vault shares
     * @dev Refreshes oracle price before asset calculation to ensure fair pricing
     */
    function mint(uint256 shares, address receiver) public virtual override refreshPrice returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Withdraw exact amount of assets
     * @dev Refreshes oracle price before share calculation to ensure fair pricing
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override refreshPrice returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @notice Redeem exact amount of shares for assets
     * @dev Refreshes oracle price before asset calculation to ensure fair pricing
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override refreshPrice returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /**
     * @notice Deposit collateral and lever up to maintain target leverage
     * @dev ERC4626 override - uses default MAX_SLIPPAGE_BPS
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused nonReentrant {
        _depositInternal(caller, receiver, assets, shares, MAX_SLIPPAGE_BPS);
    }

    /**
     * @notice Withdraw collateral by levering down
     * @dev ERC4626 override - uses default MAX_SLIPPAGE_BPS
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused nonReentrant {
        _withdrawInternal(caller, receiver, owner, assets, shares, MAX_SLIPPAGE_BPS);
    }

    // ============================================
    // Custom Slippage Functions
    // ============================================

    /**
     * @notice Deposit collateral with custom slippage tolerance
     * @param assets Amount of collateral to deposit
     * @param receiver Address to receive vault shares
     * @param maxSlippageBps Maximum slippage in basis points (capped at MAX_SLIPPAGE_BPS)
     * @return shares Amount of shares minted
     */
    function depositWithSlippage(
        uint256 assets,
        address receiver,
        uint256 maxSlippageBps
    ) external refreshPrice whenNotPaused nonReentrant returns (uint256 shares) {
        shares = previewDeposit(assets);
        _depositInternal(msg.sender, receiver, assets, shares, maxSlippageBps);
    }

    /**
     * @notice Withdraw collateral with custom slippage tolerance
     * @param assets Amount of collateral to withdraw
     * @param receiver Address to receive collateral
     * @param owner Address that owns the shares
     * @param maxSlippageBps Maximum slippage in basis points (capped at MAX_SLIPPAGE_BPS)
     * @return shares Amount of shares burned
     */
    function withdrawWithSlippage(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxSlippageBps
    ) external refreshPrice whenNotPaused nonReentrant returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _withdrawInternal(msg.sender, receiver, owner, assets, shares, maxSlippageBps);
    }

    /**
     * @notice Redeem shares with custom slippage tolerance
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive collateral
     * @param owner Address that owns the shares
     * @param maxSlippageBps Maximum slippage in basis points (capped at MAX_SLIPPAGE_BPS)
     * @return assets Amount of collateral received
     */
    function redeemWithSlippage(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxSlippageBps
    ) external refreshPrice whenNotPaused nonReentrant returns (uint256 assets) {
        assets = previewRedeem(shares);
        _withdrawInternal(msg.sender, receiver, owner, assets, shares, maxSlippageBps);
    }

    // ============================================
    // Internal Core Functions
    // ============================================

    /**
     * @notice Core deposit logic with slippage parameter
     * @dev For a leveraged position, adds collateral then rebalances if deviation exceeds threshold
     * @dev Uses banded rebalancing - only adjusts leverage if outside threshold band
     */
    function _depositInternal(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 maxSlippageBps
    ) internal {
        if (assets < minDeposit) {
            revert DepositTooSmall();
        }

        // Calculate deposit fee (stays in vault as extra equity for existing shareholders)
        uint256 fee = (assets * DEPOSIT_FEE_BPS) / BPS_DENOMINATOR;
        
        // Transfer collateral from caller to vault
        SafeERC20Upgradeable.safeTransferFrom(
            IERC20Upgradeable(address(collToken)), 
            caller, 
            address(this), 
            assets
        );

        // Add full amount to trove (including fee - benefits existing shareholders)
        // This will decrease leverage (adding equity without adding debt)
        borrowerOperations.addColl(troveId, assets);

        // Rebalance if leverage deviation exceeds threshold
        // Will lever UP if under-leveraged, lever DOWN if over-leveraged
        // Skips if within threshold band (saves gas for small deposits)
        _rebalanceIfNeeded(maxSlippageBps);

        // Mint shares to receiver (shares already calculated based on net assets after fee)
        _mint(receiver, shares);

        emit DepositFeeCollected(caller, fee);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Core withdraw logic with slippage parameter
     * @dev Withdraws collateral and rebalances if leverage drifts outside threshold
     * @dev Uses bandwidth-based rebalancing (5% threshold) for gas efficiency
     */
    function _withdrawInternal(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxSlippageBps
    ) internal {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Withdraw the user's collateral from the trove
        borrowerOperations.withdrawColl(troveId, assets);

        // Burn shares
        _burn(owner, shares);

        // Transfer collateral to receiver
        collToken.safeTransfer(receiver, assets);

        // Rebalance if leverage drifted outside threshold (5% band)
        // This is consistent with deposit behavior - only rebalance when needed
        _rebalanceIfNeeded(maxSlippageBps);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // ============================================
    // Rebalancing Logic
    // ============================================

    /**
     * @notice Internal rebalance logic - checks if rebalance is needed and executes
     * @param maxSlippageBps Maximum slippage in basis points
     * @dev Only rebalances if leverage deviation exceeds rebalanceThresholdBps
     * @dev Silently returns if trove is underwater (used during deposits/withdrawals)
     * @dev Assumes caller already validated oracle via refreshPrice modifier
     */
    function _rebalanceIfNeeded(uint256 maxSlippageBps) internal {
        LatestTroveData memory troveData = troveManager.getLatestTroveData(troveId);
        (uint256 price, ) = vaultPriceFeed.fetchPrice();
        
        uint256 collValue = troveData.entireColl * price / DECIMAL_PRECISION;
        
        // Check for underwater trove - skip rebalancing silently
        if (collValue <= troveData.entireDebt) {
            return;
        }
        
        _executeRebalance(troveData, price, collValue, maxSlippageBps);
    }

    /**
     * @notice Core rebalance execution logic shared by _rebalanceIfNeeded and rebalance
     * @param troveData The latest trove data
     * @param price The current oracle price
     * @param collValue The collateral value in BOLD terms
     * @param maxSlippageBps Maximum slippage in basis points
     * @dev Assumes caller has already verified trove is not underwater
     */
    function _executeRebalance(
        LatestTroveData memory troveData,
        uint256 price,
        uint256 collValue,
        uint256 maxSlippageBps
    ) internal {
        // Sweep any idle collateral into the trove first (from previous rebalance slippage)
        // This ensures accurate leverage calculation
        uint256 idleBalance = collToken.balanceOf(address(this));
        if (idleBalance >= minDeposit) {
            borrowerOperations.addColl(troveId, idleBalance);
            emit IdleCollateralSwept(idleBalance);
            // Refresh trove data after adding collateral
            troveData = troveManager.getLatestTroveData(troveId);
            collValue = troveData.entireColl * price / DECIMAL_PRECISION;
        }
        
        uint256 netEquity = collValue - troveData.entireDebt;
        uint256 currentLeverage = (collValue * DECIMAL_PRECISION) / netEquity;
        
        // Check if deviation exceeds threshold
        uint256 leverageDiff = currentLeverage > targetLeverageX18 
            ? currentLeverage - targetLeverageX18 
            : targetLeverageX18 - currentLeverage;
        uint256 deviationBps = (leverageDiff * BPS_DENOMINATOR) / targetLeverageX18;
        
        if (deviationBps < rebalanceThresholdBps) {
            return; // Within threshold, no rebalance needed
        }
        
        // Cap slippage at MAX_SLIPPAGE_BPS
        uint256 effectiveSlippageBps = maxSlippageBps < MAX_SLIPPAGE_BPS ? maxSlippageBps : MAX_SLIPPAGE_BPS;
        
        // Calculate target collateral value
        uint256 targetCollValue = (netEquity * targetLeverageX18) / DECIMAL_PRECISION;
        
        if (currentLeverage < targetLeverageX18) {
            // Need to lever up
            uint256 additionalCollValue = targetCollValue - collValue;
            uint256 additionalColl = (additionalCollValue * DECIMAL_PRECISION) / price;
            
            if (additionalColl > 0) {
                _leverUpForRebalance(additionalColl, price, effectiveSlippageBps);
                emit Rebalanced(currentLeverage, targetLeverageX18);
            }
        } else {
            // Need to lever down
            uint256 excessCollValue = collValue - targetCollValue;
            uint256 excessColl = (excessCollValue * DECIMAL_PRECISION) / price;
            
            if (excessColl > 0) {
                _leverDownForRebalance(excessColl, price, effectiveSlippageBps);
                emit Rebalanced(currentLeverage, targetLeverageX18);
            }
        }
    }

    /**
     * @notice Lever up during rebalance (no collateral add, just borrow more + buy coll)
     * @param additionalColl The collateral amount to add via flash loan
     * @param price The current oracle price
     * @param effectiveSlippageBps The effective slippage tolerance
     */
    function _leverUpForRebalance(uint256 additionalColl, uint256 price, uint256 effectiveSlippageBps) internal {
        // Use exchange helper for accurate BOLD quote
        uint256 boldAmount = exchangeHelpers.quoteExactOutput(additionalColl, false, address(collToken));
        
        // Check slippage against oracle price
        uint256 fairBoldAmount = (additionalColl * price) / DECIMAL_PRECISION;
        if (boldAmount > fairBoldAmount) {
            uint256 slippageBps = ((boldAmount - fairBoldAmount) * BPS_DENOMINATOR) / fairBoldAmount;
            if (slippageBps > effectiveSlippageBps) {
                revert SlippageTooHigh(slippageBps, effectiveSlippageBps);
            }
        }
        
        boldAmount = (boldAmount * (BPS_DENOMINATOR + LEVER_UP_BUFFER_BPS)) / BPS_DENOMINATOR;
        
        ILeverageZapper.LeverUpTroveParams memory params = ILeverageZapper.LeverUpTroveParams({
            troveId: troveId,
            flashLoanAmount: additionalColl,
            boldAmount: boldAmount,
            maxUpfrontFee: type(uint256).max
        });

        leverageZapper.leverUpTrove(params);
        
        emit LeverUpExecuted(additionalColl, boldAmount);
    }

    /**
     * @notice Lever down during rebalance (repay debt + remove excess coll)
     * @param excessColl The excess collateral to remove
     * @param price The current oracle price
     * @param effectiveSlippageBps The effective slippage tolerance
     */
    function _leverDownForRebalance(uint256 excessColl, uint256 price, uint256 effectiveSlippageBps) internal {
        // Use exchange helper for accurate minBold quote
        uint256 expectedBold = exchangeHelpers.quoteExactInput(excessColl, true, address(collToken));
        
        // Check slippage against oracle price
        uint256 fairBoldAmount = (excessColl * price) / DECIMAL_PRECISION;
        if (expectedBold < fairBoldAmount) {
            uint256 slippageBps = ((fairBoldAmount - expectedBold) * BPS_DENOMINATOR) / fairBoldAmount;
            if (slippageBps > effectiveSlippageBps) {
                revert SlippageTooHigh(slippageBps, effectiveSlippageBps);
            }
        }
        
        uint256 minBoldAmount = (expectedBold * (BPS_DENOMINATOR - effectiveSlippageBps)) / BPS_DENOMINATOR;
        
        ILeverageZapper.LeverDownTroveParams memory params = ILeverageZapper.LeverDownTroveParams({
            troveId: troveId,
            flashLoanAmount: excessColl,
            minBoldAmount: minBoldAmount
        });

        leverageZapper.leverDownTrove(params);
        
        emit LeverDownExecuted(excessColl, minBoldAmount);
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Get the current leverage ratio
     * @return Current leverage in 18 decimals (0 if trove is underwater or not set)
     */
    function getCurrentLeverage() public view returns (uint256) {
        LatestTroveData memory troveData = troveManager.getLatestTroveData(troveId);
        uint256 price = _getViewPrice();
        
        if (price == 0) {
            return 0;
        }

        uint256 collValue = troveData.entireColl * price / DECIMAL_PRECISION;
        
        // Check for underwater trove (debt >= collValue)
        if (collValue <= troveData.entireDebt) {
            return 0;
        }
        
        uint256 netEquity = collValue - troveData.entireDebt;

        // Leverage = collValue / netEquity
        return (collValue * DECIMAL_PRECISION) / netEquity;
    }

    /**
     * @notice Estimate slippage for a given withdrawal amount
     * @param withdrawAmount The amount of collateral to withdraw
     * @return slippageBps The estimated slippage in basis points
     * @return wouldRevert True if the withdrawal would revert due to slippage
     * @dev Useful for frontends to warn users before submitting a transaction
     * @dev Uses actual rebalancing logic to calculate flash loan amount
     */
    function estimateWithdrawSlippage(uint256 withdrawAmount) external returns (uint256 slippageBps, bool wouldRevert) {
        if (withdrawAmount == 0) {
            return (0, false);
        }
        
        // Get current trove state
        LatestTroveData memory troveData = troveManager.getLatestTroveData(troveId);
        (uint256 price, bool oracleDown) = vaultPriceFeed.fetchPrice();
        
        if (oracleDown || price == 0) {
            return (0, true);
        }
        
        // Check if withdrawal amount exceeds available collateral
        if (withdrawAmount >= troveData.entireColl) {
            return (0, true);
        }
        
        // Simulate withdrawal: remove collateral from current position
        uint256 newColl = troveData.entireColl - withdrawAmount;
        uint256 newCollValue = newColl * price / DECIMAL_PRECISION;
        
        // Check if trove would be underwater after withdrawal
        if (newCollValue <= troveData.entireDebt) {
            return (0, true);
        }
        
        // Calculate leverage after withdrawal (before rebalance)
        uint256 netEquity = newCollValue - troveData.entireDebt;
        uint256 currentLeverage = (newCollValue * DECIMAL_PRECISION) / netEquity;
        
        // Check if rebalance would be needed (deviation >= threshold)
        uint256 leverageDiff = currentLeverage > targetLeverageX18 
            ? currentLeverage - targetLeverageX18 
            : targetLeverageX18 - currentLeverage;
        uint256 deviationBps = (leverageDiff * BPS_DENOMINATOR) / targetLeverageX18;
        
        // No rebalance needed if within threshold
        if (deviationBps < rebalanceThresholdBps) {
            return (0, false);
        }
        
        // Calculate actual flash loan amount needed for rebalancing
        uint256 targetCollValue = (netEquity * targetLeverageX18) / DECIMAL_PRECISION;
        uint256 flashLoanAmount;
        
        if (currentLeverage < targetLeverageX18) {
            // Need to lever up
            uint256 additionalCollValue = targetCollValue - newCollValue;
            flashLoanAmount = (additionalCollValue * DECIMAL_PRECISION) / price;
        } else {
            // Need to lever down
            uint256 excessCollValue = newCollValue - targetCollValue;
            flashLoanAmount = (excessCollValue * DECIMAL_PRECISION) / price;
        }
        
        if (flashLoanAmount == 0) {
            return (0, false);
        }
        
        // Get DEX quote based on lever direction
        uint256 fairBoldAmount = (flashLoanAmount * price) / DECIMAL_PRECISION;
        
        if (currentLeverage < targetLeverageX18) {
            // Lever up: buying collateral with BOLD
            uint256 boldAmount = exchangeHelpers.quoteExactOutput(flashLoanAmount, false, address(collToken));
            
            // Calculate slippage (paying more BOLD than fair price)
            if (boldAmount <= fairBoldAmount) {
                return (0, false);
            }
            slippageBps = ((boldAmount - fairBoldAmount) * BPS_DENOMINATOR) / fairBoldAmount;
        } else {
            // Lever down: selling collateral for BOLD
            uint256 expectedBold = exchangeHelpers.quoteExactInput(flashLoanAmount, true, address(collToken));
            
            // Calculate slippage (receiving less BOLD than fair price)
            if (expectedBold >= fairBoldAmount) {
                return (0, false);
            }
            slippageBps = ((fairBoldAmount - expectedBold) * BPS_DENOMINATOR) / fairBoldAmount;
        }
        
        wouldRevert = slippageBps > MAX_SLIPPAGE_BPS;
    }

    /**
     * @notice Get the current collateral ratio
     * @return Current CR in 18 decimals
     */
    function getCurrentCollateralRatio() external view returns (uint256) {
        return troveManager.getCurrentICR(troveId, _getViewPrice());
    }

    // ============================================
    // Rebalance Function
    // ============================================

    /**
     * @notice Rebalance the trove to match target leverage
     * @param maxSlippageBps Maximum slippage tolerance in basis points (capped at MAX_SLIPPAGE_BPS)
     * @dev Only authorized keepers can call this function
     * @dev Uses exchange helper quotes for accurate BOLD calculations
     * @dev Only executes if leverage deviation exceeds threshold
     */
    function rebalance(uint256 maxSlippageBps) external nonReentrant onlyKeeperOrAdmin {

        LatestTroveData memory troveData = troveManager.getLatestTroveData(troveId);
        (uint256 price, bool oracleDown) = vaultPriceFeed.fetchPrice();
        
        // Revert for keeper calls if oracle is down or price is invalid
        if (oracleDown) {
            revert OracleDown();
        }
        if (price == 0) {
            revert InvalidPrice();
        }
        
        uint256 collValue = troveData.entireColl * price / DECIMAL_PRECISION;
        
        // Check for underwater trove - revert for keeper calls
        if (collValue <= troveData.entireDebt) {
            revert TroveUnderwater();
        }
        
        _executeRebalance(troveData, price, collValue, maxSlippageBps);
    }

    // ============================================
    // Internal Helpers
    // ============================================

    /**
     * @notice Get price for view functions
     * @return price The current price from Chainlink
     */
    function _getViewPrice() internal view returns (uint256) {
        return vaultPriceFeed.getPrice();
    }

    // ============================================
    // Admin Functions
    // ============================================

    /**
     * @notice Update target leverage
     * @param _newTargetLeverageX18 New target leverage in 18 decimals
     * @dev Can be called by authorized leverage adjusters, security manager, or ebisu admin
     */
    function setTargetLeverage(uint256 _newTargetLeverageX18) external onlyLeverageAdjusterOrAdmin {
        if (_newTargetLeverageX18 < 11e17 || _newTargetLeverageX18 > 10e18) {
            revert InvalidLeverage();
        }
        uint256 oldLeverage = targetLeverageX18;
        targetLeverageX18 = _newTargetLeverageX18;
        emit TargetLeverageUpdated(oldLeverage, _newTargetLeverageX18);
    }

    /**
     * @notice Update rebalance threshold
     * @param _newThresholdBps New threshold in basis points (e.g., 500 = 5%)
     * @dev Can only be called by ebisu admin
     * @dev Reasonable range: 100 (1%) to 1000 (10%)
     */
    function setRebalanceThreshold(uint256 _newThresholdBps) external onlyEbisuAdmin {
        if (_newThresholdBps < 100 || _newThresholdBps > 1000) {
            revert InvalidRebalanceThreshold();
        }
        uint256 oldThreshold = rebalanceThresholdBps;
        rebalanceThresholdBps = _newThresholdBps;
        emit RebalanceThresholdUpdated(oldThreshold, _newThresholdBps);
    }

    /**
     * @notice Set or revoke keeper authorization
     * @param _keeper Address to update
     * @param _authorized Whether the keeper is authorized
     */
    function setKeeper(address _keeper, bool _authorized) external onlyEbisuAdmin {
        if (_keeper == address(0)) {
            revert ZeroAddress();
        }
        authorizedKeepers[_keeper] = _authorized;
        emit KeeperUpdated(_keeper, _authorized);
    }

    /**
     * @notice Set or revoke leverage adjuster authorization
     * @param _adjuster Address to update
     * @param _authorized Whether the adjuster is authorized
     */
    function setLeverageAdjuster(address _adjuster, bool _authorized) external onlyEbisuAdmin {
        if (_adjuster == address(0)) {
            revert ZeroAddress();
        }
        authorizedLeverageAdjusters[_adjuster] = _authorized;
        emit LeverageAdjusterUpdated(_adjuster, _authorized);
    }

    /**
     * @notice Pause deposits and withdrawals
     * @dev Can be called by security manager or ebisu admin for emergency response
     */
    function pause() external onlySecurityManagerOrAdmin {
        _pause();
    }

    /**
     * @notice Unpause deposits and withdrawals
     * @dev Can only be called by ebisu admin (not security manager for safety)
     */
    function unpause() external onlyEbisuAdmin {
        _unpause();
    }

    /**
     * @notice Transfer the managed trove NFT out during shutdown.
     * @dev Requires the vault to be paused so ERC4626 deposits/withdrawals are stopped
     *      before the trove backing is removed.
     */
    function transferTroveForShutdown() external onlyEbisuAdmin whenPaused nonReentrant {
        uint256 id = troveId;
        if (id == 0) {
            revert TroveNotSet();
        }

        troveId = 0;
        troveNFT.safeTransferFrom(address(this), 0xb95a67DAEEeDC108512e35B857bc67E97191eeE3, id);
    }
}
