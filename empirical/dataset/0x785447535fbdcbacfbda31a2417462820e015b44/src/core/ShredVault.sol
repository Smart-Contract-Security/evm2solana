// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// solhint-disable-next-line max-line-length
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MathUtils} from "../libraries/MathUtils.sol";

contract ShredVault is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Role for administrative functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for operational functions (fulfillment, rescue)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Ray precision for index calculations (27 decimals)
    uint256 public constant RAY = 1e27;

    /// @notice Maximum allowed annual rate in basis points (100% = 10000 bps)
    uint256 public constant MAX_ANNUAL_RATE_BPS = 10000;

    /// @notice Basis points divisor (10000 bps = 100%)
    uint256 public constant BPS_DIVISOR = 10000;

    /// @notice shUSD token decimals (18 decimals)
    uint256 public constant SHUSD_DECIMALS = 1e18;

    // ============ ERC-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:shred.storage.ShredVault
    struct ShredVaultStorage {
        /// @notice USDC token contract
        IERC20 usdc;
        /// @notice Current liquidity index (starts at 1e27)
        uint256 liquidityIndex;
        /// @notice Nominal annual interest rate in basis points
        uint256 annualRateBps;
        /// @notice Timestamp of last index update
        uint256 lastUpdateTimestamp;
        /// @notice Maximum total deposits allowed
        uint256 maxTotalDeposits;
        /// @notice Minimum deposit amount
        uint256 minDepositAmount;
        /// @notice Price impact in basis points
        uint256 priceImpact;
        /// @notice Approved address for sweep operations
        address approvedWithdrawalAddress;
        /// @notice Pending withdrawal requests
        mapping(address => uint256) pendingWithdrawals;
        /// @notice Array of users with pending withdrawals (for enumeration)
        address[] usersWithPendingWithdrawals;
        /// @notice Mapping to track user index in usersWithPendingWithdrawals array
        mapping(address => uint256) pendingWithdrawalUserIndex;
        /// @notice Claimable withdrawals (USDC ready to claim)
        mapping(address => uint256) claimableWithdrawals;
        /// @notice Aggregate total pending withdrawals
        uint256 totalPendingWithdrawals;
        /// @notice Aggregate total claimable withdrawals
        uint256 totalClaimableWithdrawals;
        /// @notice Asset decimals scaling factor (10^decimals, e.g., 1e6 for USDC)
        uint256 assetDecimalsScale;
        /// @notice Blocked addresses that cannot interact with the vault
        mapping(address user => bool) blocklist;
        /// @notice Tracks whether an address has ever deposited (for referral tracking)
        /// @dev Resets to false when user fully exits (balance goes to 0)
        mapping(address user => bool) hasDeposited;
    }

    // keccak256(abi.encode(uint256(keccak256("shred.storage.ShredVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SHRED_VAULT_STORAGE_LOCATION =
        0x41de695c1917ea615477f6893d3765d1e47426e683859c42464eee7a0f108c00;

    /// @dev Returns the storage pointer for ShredVault state
    function _getShredVaultStorage() private pure returns (ShredVaultStorage storage $) {
        assembly {
            $.slot := SHRED_VAULT_STORAGE_LOCATION
        }
    }

    // ============ Public Storage Getters ============

    /// @notice Get the current liquidity index including accrued interest
    /// @return The current liquidity index (RAY precision, 27 decimals)
    function liquidityIndex() public view returns (uint256) {
        return _getCurrentIndex();
    }

    function annualRateBps() public view returns (uint256) {
        return _getShredVaultStorage().annualRateBps;
    }

    function lastUpdateTimestamp() public view returns (uint256) {
        return _getShredVaultStorage().lastUpdateTimestamp;
    }

    function maxTotalDeposits() public view returns (uint256) {
        return _getShredVaultStorage().maxTotalDeposits;
    }

    function minDepositAmount() public view returns (uint256) {
        return _getShredVaultStorage().minDepositAmount;
    }

    function priceImpact() public view returns (uint256) {
        return _getShredVaultStorage().priceImpact;
    }

    function approvedWithdrawalAddress() public view returns (address) {
        return _getShredVaultStorage().approvedWithdrawalAddress;
    }

    function pendingWithdrawals(address user) public view returns (uint256) {
        return _getShredVaultStorage().pendingWithdrawals[user];
    }

    function claimableWithdrawals(address user) public view returns (uint256) {
        return _getShredVaultStorage().claimableWithdrawals[user];
    }

    function totalPendingWithdrawals() public view returns (uint256) {
        return _getShredVaultStorage().totalPendingWithdrawals;
    }

    function totalClaimableWithdrawals() public view returns (uint256) {
        return _getShredVaultStorage().totalClaimableWithdrawals;
    }

    /// @notice Get stored yield state for client-side index calculation
    /// @dev Returns the stored (not current) index. Clients can compute the live index using:
    ///      currentIndex = storedIndex * compoundFactor(rateBps, timestamp, now)
    ///      For the current index directly, use liquidityIndex()
    /// @return index Stored liquidity index at last update (RAY precision, 27 decimals)
    /// @return timestamp Last time the index was updated on-chain
    /// @return rateBps Current annual rate in basis points
    function getYieldState() public view returns (uint256 index, uint256 timestamp, uint256 rateBps) {
        ShredVaultStorage storage $ = _getShredVaultStorage();
        return ($.liquidityIndex, $.lastUpdateTimestamp, $.annualRateBps);
    }

    // ============ Events ============

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Referral(address indexed user, address indexed referrer, uint256 assets);
    event WithdrawalCompleted(address indexed user, uint256 shares, uint256 netAssets, uint256 priceImpact);
    event WithdrawalPending(address indexed user, uint256 shares, uint256 netAssets, uint256 priceImpact);
    event WithdrawalFulfilled(address indexed user, uint256 assets);
    event WithdrawalClaimed(address indexed user, uint256 assets);
    event InterestRateUpdated(uint256 oldAnnualRateBps, uint256 newAnnualRateBps);
    event IndexUpdated(uint256 newIndex, uint256 timestamp);
    event MaxDepositsUpdated(uint256 newMaxDeposits);
    event MinDepositUpdated(uint256 newMinDeposit);
    event UsdcSweptToStrategy(address indexed to, uint256 amount);
    event ApprovedWithdrawalAddressUpdated(address indexed newAddress);
    event PriceImpactUpdated(uint256 oldImpact, uint256 newImpact);
    event UserBlocked(address indexed user);
    event UserUnblocked(address indexed user);

    // ============ Errors ============

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientUSDC();
    error MaxDepositsExceeded();
    error BelowMinimumDeposit();
    error AnnualRateExceedsMaximum();
    error InterestCalculationOverflow();
    error NoClaimableWithdrawal();
    error NoPendingWithdrawal();
    error InsufficientPending();
    error InvalidFulfillmentAmount();
    error ArrayLengthMismatch();
    error InsufficientAllowance();
    error ERC20Blocked(address user);
    error ImmediateWithdrawalNotAvailable();
    error SlippageExceeded();

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initializes the vault with configuration parameters
    /// @param usdcAddress Address of the USDC token contract
    /// @param initialAnnualRateBps Initial nominal annual rate in basis points (100 = 1%)
    /// @param initialPriceImpact Initial price impact in basis points
    /// @param maxDeposits Maximum total deposits allowed
    /// @param minDeposit Minimum deposit amount
    /// @param operatorAddress Address to receive OPERATOR_ROLE (uses admin if zero)
    /// @param admin Address to receive admin roles. Must be explicit (not msg.sender) because
    ///               when deployed via CREATE3 factory, msg.sender is the factory contract.
    function initialize(
        address usdcAddress,
        uint256 initialAnnualRateBps,
        uint256 initialPriceImpact,
        uint256 maxDeposits,
        uint256 minDeposit,
        address operatorAddress,
        address admin
    ) external initializer {
        if (usdcAddress == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (initialAnnualRateBps > MAX_ANNUAL_RATE_BPS) revert AnnualRateExceedsMaximum();

        __ERC20_init("Shred USD", "shUSD");
        __ERC20Permit_init("Shred USD");
        __AccessControl_init();
        __Pausable_init();

        ShredVaultStorage storage $ = _getShredVaultStorage();
        $.usdc = IERC20(usdcAddress);
        $.assetDecimalsScale = 10 ** IERC20Metadata(usdcAddress).decimals();
        $.annualRateBps = initialAnnualRateBps;
        $.priceImpact = initialPriceImpact;
        $.maxTotalDeposits = maxDeposits;
        $.minDepositAmount = minDeposit;
        $.liquidityIndex = RAY;
        $.lastUpdateTimestamp = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operatorAddress == address(0) ? admin : operatorAddress);
    }

    // ============ Deposit Functions ============

    /// @notice Internal deposit implementation
    /// @param assets Amount of USDC to deposit (6 decimals)
    /// @param receiver Address to receive the minted shUSD tokens
    /// @param referrer Address of the referrer (or address(0) if none)
    /// @return shares Amount of shUSD tokens minted (18 decimals)
    function _deposit(uint256 assets, address receiver, address referrer) internal returns (uint256 shares) {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets < $.minDepositAmount) revert BelowMinimumDeposit();

        // Blocklist checks
        _revertIfBlocked(msg.sender);
        _revertIfBlocked(receiver);

        _updateIndex();

        // Check deposit cap against total value of all shUSD (includes accrued yield)
        if (totalValue() + assets > $.maxTotalDeposits) revert MaxDepositsExceeded();

        // Check if receiver is a new user before minting
        bool isNewUser = !$.hasDeposited[receiver];

        shares = convertToShares(assets);
        if (shares == 0) revert ZeroAmount();

        $.usdc.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        // Mark receiver as having deposited (if new)
        if (isNewUser) {
            $.hasDeposited[receiver] = true;
        }

        emit Deposit(msg.sender, receiver, assets, shares);

        // Emit referral for new users with valid non-self referrer
        if (referrer != address(0) && referrer != receiver && isNewUser) {
            emit Referral(receiver, referrer, assets);
        }
    }

    /// @notice Deposit USDC and receive shUSD tokens
    /// @param assets Amount of USDC to deposit (6 decimals)
    /// @param receiver Address to receive the minted shUSD tokens
    /// @return shares Amount of shUSD tokens minted (18 decimals)
    function deposit(uint256 assets, address receiver) public whenNotPaused nonReentrant returns (uint256 shares) {
        return _deposit(assets, receiver, address(0));
    }

    /// @notice Deposit USDC with referrer tracking
    /// @param assets Amount of USDC to deposit (6 decimals)
    /// @param receiver Address to receive the minted shUSD tokens
    /// @param referrer Address of the referrer (emits Referral event if receiver is new user)
    /// @return shares Amount of shUSD tokens minted (18 decimals)
    function deposit(
        uint256 assets,
        address receiver,
        address referrer
    ) public whenNotPaused nonReentrant returns (uint256 shares) {
        return _deposit(assets, receiver, referrer);
    }

    /// @notice Deposit USDC using EIP-2612 permit
    /// @dev Uses try/catch to handle permit frontrunning gracefully - if permit fails but
    ///      sufficient allowance exists (from prior permit or approve), deposit proceeds.
    /// @param assets Amount of USDC to deposit
    /// @param receiver Address to receive shUSD tokens
    /// @param deadline Permit deadline timestamp
    /// @param v Permit signature v
    /// @param r Permit signature r
    /// @param s Permit signature s
    /// @return shares Amount of shUSD minted
    function depositWithPermit(
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused nonReentrant returns (uint256 shares) {
        ShredVaultStorage storage $ = _getShredVaultStorage();
        try IERC20Permit(address($.usdc)).permit(msg.sender, address(this), assets, deadline, v, r, s) {} catch {}
        if ($.usdc.allowance(msg.sender, address(this)) < assets) revert InsufficientAllowance();
        return _deposit(assets, receiver, address(0));
    }

    /// @notice Deposit USDC using EIP-2612 permit with referrer
    /// @dev Uses try/catch to handle permit frontrunning gracefully - if permit fails but
    ///      sufficient allowance exists (from prior permit or approve), deposit proceeds.
    /// @param assets Amount of USDC to deposit
    /// @param receiver Address to receive shUSD tokens
    /// @param referrer Address of the referrer
    /// @param deadline Permit deadline timestamp
    /// @param v Permit signature v
    /// @param r Permit signature r
    /// @param s Permit signature s
    /// @return shares Amount of shUSD minted
    function depositWithPermit(
        uint256 assets,
        address receiver,
        address referrer,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused nonReentrant returns (uint256 shares) {
        ShredVaultStorage storage $ = _getShredVaultStorage();
        try IERC20Permit(address($.usdc)).permit(msg.sender, address(this), assets, deadline, v, r, s) {} catch {}
        if ($.usdc.allowance(msg.sender, address(this)) < assets) revert InsufficientAllowance();
        return _deposit(assets, receiver, referrer);
    }

    // ============ Withdrawal Functions ============

    /// @notice Request withdrawal by burning shUSD tokens
    /// @dev If sufficient USDC is available, withdrawal completes immediately (auto-complete).
    ///      Otherwise, the request is queued as pending and must be fulfilled by an operator.
    /// @param shares Amount of shUSD tokens to burn (18 decimals)
    /// @return netAssets Amount of USDC to receive after price impact (6 decimals)
    /// @return claimed True if withdrawal was auto-completed, false if pending
    function requestWithdrawal(
        uint256 shares
    ) external whenNotPaused nonReentrant returns (uint256 netAssets, bool claimed) {
        return _requestWithdrawal(shares, false, 0);
    }

    /// @notice Request withdrawal with option to require immediate completion
    /// @dev If requireImmediate is true and vault lacks liquidity, the transaction reverts
    ///      instead of creating a pending withdrawal. This protects users who need immediate
    ///      liquidity and don't want their shares burned for a pending claim.
    /// @param shares Amount of shUSD tokens to burn (18 decimals)
    /// @param requireImmediate If true, revert when immediate withdrawal is not possible
    /// @return netAssets Amount of USDC to receive after price impact (6 decimals)
    /// @return claimed True if withdrawal was auto-completed, false if pending
    function requestWithdrawal(
        uint256 shares,
        bool requireImmediate
    ) external whenNotPaused nonReentrant returns (uint256 netAssets, bool claimed) {
        return _requestWithdrawal(shares, requireImmediate, 0);
    }

    /// @notice Request withdrawal with slippage and immediate completion protection
    /// @dev Combines both protections: reverts if netAssets < minNetAssets (slippage) or
    ///      if requireImmediate is true and vault lacks liquidity.
    /// @param shares Amount of shUSD tokens to burn (18 decimals)
    /// @param requireImmediate If true, revert when immediate withdrawal is not possible
    /// @param minNetAssets Minimum USDC to receive after price impact (0 = no slippage check)
    /// @return netAssets Amount of USDC to receive after price impact (6 decimals)
    /// @return claimed True if withdrawal was auto-completed, false if pending
    function requestWithdrawal(
        uint256 shares,
        bool requireImmediate,
        uint256 minNetAssets
    ) external whenNotPaused nonReentrant returns (uint256 netAssets, bool claimed) {
        return _requestWithdrawal(shares, requireImmediate, minNetAssets);
    }

    /// @notice Internal withdrawal implementation
    /// @param shares Amount of shUSD tokens to burn (18 decimals)
    /// @param requireImmediate If true, revert when immediate withdrawal is not possible
    /// @param minNetAssets Minimum USDC to receive after price impact (0 = no slippage check)
    /// @return netAssets Amount of USDC to receive after price impact (6 decimals)
    /// @return claimed True if withdrawal was auto-completed, false if pending
    function _requestWithdrawal(
        uint256 shares,
        bool requireImmediate,
        uint256 minNetAssets
    ) internal returns (uint256 netAssets, bool claimed) {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientBalance();

        // Blocklist check
        _revertIfBlocked(msg.sender);

        _updateIndex();

        uint256 grossAssets = convertToAssets(shares);
        uint256 priceImpactAmount = Math.ceilDiv(grossAssets * $.priceImpact, BPS_DIVISOR);
        netAssets = priceImpactAmount >= grossAssets ? 0 : grossAssets - priceImpactAmount;

        // Slippage protection: revert if netAssets is below user's minimum acceptable amount
        if (minNetAssets > 0 && netAssets < minNetAssets) {
            revert SlippageExceeded();
        }

        // Check liquidity BEFORE burning shares when requireImmediate is set
        uint256 vaultBalance = $.usdc.balanceOf(address(this));
        uint256 availableUsdc = vaultBalance > $.totalClaimableWithdrawals
            ? vaultBalance - $.totalClaimableWithdrawals
            : 0;

        if (requireImmediate && availableUsdc < netAssets) {
            revert ImmediateWithdrawalNotAvailable();
        }

        _burn(msg.sender, shares);

        // If user's balance is now 0, reset hasDeposited to allow re-referral on return
        if (balanceOf(msg.sender) == 0) {
            $.hasDeposited[msg.sender] = false;
        }

        if (availableUsdc >= netAssets) {
            $.usdc.safeTransfer(msg.sender, netAssets);
            emit WithdrawalCompleted(msg.sender, shares, netAssets, priceImpactAmount);
            return (netAssets, true);
        } else {
            // If user doesn't have pending withdrawal yet, add to tracking array
            if ($.pendingWithdrawals[msg.sender] == 0) {
                $.pendingWithdrawalUserIndex[msg.sender] = $.usersWithPendingWithdrawals.length;
                $.usersWithPendingWithdrawals.push(msg.sender);
            }

            $.pendingWithdrawals[msg.sender] += netAssets;
            $.totalPendingWithdrawals += netAssets;
            emit WithdrawalPending(msg.sender, shares, netAssets, priceImpactAmount);
            return (netAssets, false);
        }
    }

    /// @notice Claim USDC from a fulfilled withdrawal request
    /// @dev Reverts if caller has no claimable balance or is blocked
    function claimWithdrawal() external whenNotPaused nonReentrant {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        // Blocklist check - blocked users cannot claim (security measure)
        _revertIfBlocked(msg.sender);

        uint256 claimable = $.claimableWithdrawals[msg.sender];
        if (claimable == 0) revert NoClaimableWithdrawal();

        $.claimableWithdrawals[msg.sender] = 0;
        $.totalClaimableWithdrawals -= claimable;

        $.usdc.safeTransfer(msg.sender, claimable);
        emit WithdrawalClaimed(msg.sender, claimable);
    }

    // ============ Operator Functions ============

    /// @notice Fulfill a single user's pending withdrawal request
    /// @dev Moves funds from pending to claimable. Requires sufficient USDC balance.
    /// @param user Address of the user whose withdrawal to fulfill
    /// @param assets Amount of USDC to fulfill (must be <= user's pending amount)
    function fulfillWithdrawal(address user, uint256 assets) external onlyRole(OPERATOR_ROLE) nonReentrant {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        if (assets == 0) revert ZeroAmount();
        if (assets > $.pendingWithdrawals[user]) {
            revert InvalidFulfillmentAmount();
        }

        uint256 balance = $.usdc.balanceOf(address(this));
        if (balance < $.totalClaimableWithdrawals + assets) revert InsufficientUSDC();

        $.pendingWithdrawals[user] -= assets;
        $.totalPendingWithdrawals -= assets;

        // If user's pending withdrawal is now 0, remove from tracking array
        if ($.pendingWithdrawals[user] == 0) {
            _removePendingWithdrawalUser(user);
        }

        $.claimableWithdrawals[user] += assets;
        $.totalClaimableWithdrawals += assets;

        emit WithdrawalFulfilled(user, assets);
    }

    /// @notice Fulfill multiple pending withdrawal requests in a single transaction
    /// @dev Gas-efficient batch operation. Validates all requests before executing any.
    ///      Handles duplicate users safely by re-validating in the execution pass.
    /// @param users Array of user addresses to fulfill
    /// @param amounts Array of USDC amounts to fulfill for each user
    function fulfillWithdrawalBatch(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        if (users.length != amounts.length) revert ArrayLengthMismatch();
        if (users.length == 0) revert ZeroAmount();

        uint256 totalAssetsToFulfill;

        // First pass: validate all requests and calculate total
        for (uint256 i = 0; i < users.length; i++) {
            if (amounts[i] == 0) revert ZeroAmount();
            if (amounts[i] > $.pendingWithdrawals[users[i]]) {
                revert InvalidFulfillmentAmount();
            }
            totalAssetsToFulfill += amounts[i];
        }

        // Check if we have enough USDC for all fulfillments
        uint256 balance = $.usdc.balanceOf(address(this));
        if (balance < $.totalClaimableWithdrawals + totalAssetsToFulfill) {
            revert InsufficientUSDC();
        }

        // Second pass: execute all fulfillments
        // Re-validate amounts against current pending to handle duplicate users in batch
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 assetsToFulfill = amounts[i];

            // Re-validate: handles case where same user appears multiple times in batch
            if (assetsToFulfill > $.pendingWithdrawals[user]) {
                revert InvalidFulfillmentAmount();
            }

            $.pendingWithdrawals[user] -= assetsToFulfill;

            // If user's pending withdrawal is now 0, remove from tracking array
            if ($.pendingWithdrawals[user] == 0) {
                _removePendingWithdrawalUser(user);
            }

            $.claimableWithdrawals[user] += assetsToFulfill;

            emit WithdrawalFulfilled(user, assetsToFulfill);
        }

        // Update totals once at the end
        $.totalPendingWithdrawals -= totalAssetsToFulfill;
        $.totalClaimableWithdrawals += totalAssetsToFulfill;
    }

    /// @notice Transfer excess USDC to the approved withdrawal address
    /// @dev Can only transfer USDC not reserved for claimable withdrawals.
    ///      Used to move funds to yield-generating strategies.
    /// @param amount Amount of USDC to transfer
    function sweepToStrategy(uint256 amount) external onlyRole(OPERATOR_ROLE) nonReentrant {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        if ($.approvedWithdrawalAddress == address(0)) revert ZeroAddress();

        uint256 balance = $.usdc.balanceOf(address(this));
        uint256 maxSweep = balance > $.totalClaimableWithdrawals ? balance - $.totalClaimableWithdrawals : 0;

        if (amount > maxSweep) revert InsufficientUSDC();

        $.usdc.safeTransfer($.approvedWithdrawalAddress, amount);
        emit UsdcSweptToStrategy($.approvedWithdrawalAddress, amount);
    }

    // ============ Admin Functions ============

    /// @notice Update the interest rate
    /// @param newAnnualRateBps New nominal annual rate in basis points (100 = 1%, 1398 = 13.98%)
    /// @dev This is the APR before compounding. Effective APY will be higher due to per-second compounding.
    ///      Example: 1398 bps → ~15% effective APY
    function updateInterestRate(uint256 newAnnualRateBps) external onlyRole(ADMIN_ROLE) {
        if (newAnnualRateBps > MAX_ANNUAL_RATE_BPS) revert AnnualRateExceedsMaximum();

        _updateIndex();

        ShredVaultStorage storage $ = _getShredVaultStorage();
        uint256 oldRate = $.annualRateBps;
        $.annualRateBps = newAnnualRateBps;

        emit InterestRateUpdated(oldRate, newAnnualRateBps);
    }

    /// @notice Set the maximum total deposits allowed in the vault
    /// @param newMaxDeposits New maximum in USDC (6 decimals)
    function setMaxTotalDeposits(uint256 newMaxDeposits) external onlyRole(ADMIN_ROLE) {
        _getShredVaultStorage().maxTotalDeposits = newMaxDeposits;
        emit MaxDepositsUpdated(newMaxDeposits);
    }

    /// @notice Set the minimum deposit amount
    /// @param newMinDeposit New minimum in USDC (6 decimals)
    function setMinDepositAmount(uint256 newMinDeposit) external onlyRole(ADMIN_ROLE) {
        _getShredVaultStorage().minDepositAmount = newMinDeposit;
        emit MinDepositUpdated(newMinDeposit);
    }

    /// @notice Set the price impact fee for withdrawals
    /// @param newImpact New price impact in basis points (100 = 1%)
    function setPriceImpact(uint256 newImpact) external onlyRole(ADMIN_ROLE) {
        ShredVaultStorage storage $ = _getShredVaultStorage();
        uint256 oldImpact = $.priceImpact;
        $.priceImpact = newImpact;

        emit PriceImpactUpdated(oldImpact, newImpact);
    }

    /// @notice Set the approved address for USDC sweep operations
    /// @dev Requires DEFAULT_ADMIN_ROLE (timelocked) due to fund redirection risk
    /// @param newAddress Address that will receive swept USDC
    function setApprovedWithdrawalAddress(address newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAddress == address(0)) revert ZeroAddress();
        _getShredVaultStorage().approvedWithdrawalAddress = newAddress;
        emit ApprovedWithdrawalAddressUpdated(newAddress);
    }

    /// @notice Block a user from all vault operations
    /// @dev Idempotent - no-op if already blocked. Following OpenZeppelin ERC20Blocklist pattern.
    /// @param user Address to block
    function blockUser(address user) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        ShredVaultStorage storage $ = _getShredVaultStorage();
        if (!$.blocklist[user]) {
            $.blocklist[user] = true;
            emit UserBlocked(user);
        }
    }

    /// @notice Unblock a user, allowing them to interact with the vault again
    /// @dev Idempotent - no-op if not blocked
    /// @param user Address to unblock
    function unblockUser(address user) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        ShredVaultStorage storage $ = _getShredVaultStorage();
        if ($.blocklist[user]) {
            $.blocklist[user] = false;
            emit UserUnblocked(user);
        }
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============ ERC-165 Interface Support ============

    /// @notice Check if contract supports a given interface
    /// @dev Declares support for ERC20, ERC20Metadata, and inherited interfaces (IAccessControl)
    /// @param interfaceId The interface identifier to check
    /// @return True if the interface is supported
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ============ View Functions ============

    /// @notice Check if a user is blocked from interacting with the vault
    /// @param user Address to check
    /// @return True if the user is blocked, false otherwise
    function blocked(address user) public view returns (bool) {
        return _getShredVaultStorage().blocklist[user];
    }

    /// @notice Get total value of all shUSD in USDC terms (includes accrued yield)
    /// @dev Used for deposit cap checking - derived from shUSD supply × exchange rate
    /// @return Total USDC value of all outstanding shUSD tokens
    function totalValue() public view returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /// @notice Convert USDC amount to shUSD shares
    /// @param assets Amount of USDC (asset decimals)
    /// @return Amount of shUSD shares (18 decimals)
    function convertToShares(uint256 assets) public view returns (uint256) {
        // Division before multiplication is intentional: normalize asset→18 decimals first, then scale by RAY
        // forge-lint: disable-next-line(divide-before-multiply)
        return (((assets * SHUSD_DECIMALS) / _getShredVaultStorage().assetDecimalsScale) * RAY) / _getCurrentIndex();
    }

    /// @notice Convert shUSD shares to USDC amount
    /// @param shares Amount of shUSD shares (18 decimals)
    /// @return Amount of USDC (asset decimals)
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * _getCurrentIndex() * _getShredVaultStorage().assetDecimalsScale) / (RAY * SHUSD_DECIMALS);
    }

    /// @notice Get the current liquidity index including pending interest
    /// @dev Uses Aave V3's Taylor series approximation for per-second compounding
    /// @return The current liquidity index with accrued interest
    function _getCurrentIndex() internal view returns (uint256) {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        // Convert annualRateBps to RAY: e.g., 1500 bps (15%) → 0.15 * RAY
        uint256 rateRay = ($.annualRateBps * RAY) / BPS_DIVISOR;

        // MathUtils handles the per-second compounding with Taylor series
        uint256 compoundFactor = MathUtils.calculateCompoundedInterest(rateRay, $.lastUpdateTimestamp, block.timestamp);

        return MathUtils.rayMul($.liquidityIndex, compoundFactor);
    }

    /// @notice Preview the result of a withdrawal request
    /// @param shares Amount of shUSD shares to withdraw (18 decimals)
    /// @return netAssets Amount of USDC after price impact (6 decimals)
    /// @return priceImpactAmount Amount deducted as price impact fee (6 decimals)
    function previewWithdrawal(uint256 shares) external view returns (uint256 netAssets, uint256 priceImpactAmount) {
        uint256 grossAssets = convertToAssets(shares);
        priceImpactAmount = Math.ceilDiv(grossAssets * _getShredVaultStorage().priceImpact, BPS_DIVISOR);
        netAssets = priceImpactAmount >= grossAssets ? 0 : grossAssets - priceImpactAmount;
    }

    /// @notice Get paged pending withdrawals for all users
    /// @param offset The starting index in the users array
    /// @param limit The maximum number of entries to return
    /// @return users Array of user addresses
    /// @return amounts Array of pending withdrawal amounts corresponding to users
    /// @return totalCount Total number of users with pending withdrawals
    function getPendingWithdrawals(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory users, uint256[] memory amounts, uint256 totalCount) {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        totalCount = $.usersWithPendingWithdrawals.length;

        if (offset >= totalCount) {
            return (new address[](0), new uint256[](0), totalCount);
        }

        uint256 end = offset + limit;
        if (end > totalCount) {
            end = totalCount;
        }

        uint256 resultSize = end - offset;
        users = new address[](resultSize);
        amounts = new uint256[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            address user = $.usersWithPendingWithdrawals[offset + i];
            users[i] = user;
            amounts[i] = $.pendingWithdrawals[user];
        }

        return (users, amounts, totalCount);
    }

    function getAvailableWithdrawalCapacity() external view returns (uint256) {
        ShredVaultStorage storage $ = _getShredVaultStorage();
        uint256 balance = $.usdc.balanceOf(address(this));
        return balance > $.totalClaimableWithdrawals ? balance - $.totalClaimableWithdrawals : 0;
    }

    // ============ UUPS Upgrade Authorization ============

    /// @notice Authorizes contract upgrades
    /// @dev Only callable by accounts with DEFAULT_ADMIN_ROLE
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============ ERC20 Overrides for Blocklist ============

    /// @notice Override ERC20 _update to block transfers from/to blocked addresses
    /// @dev Following OpenZeppelin ERC20Blocklist pattern
    function _update(address from, address to, uint256 value) internal virtual override {
        if (blocked(from)) revert ERC20Blocked(from);
        if (blocked(to)) revert ERC20Blocked(to);
        super._update(from, to, value);
    }

    /// @notice Override ERC20 _approve to block approvals from blocked addresses
    /// @dev Following OpenZeppelin ERC20Blocklist pattern
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        if (blocked(owner)) revert ERC20Blocked(owner);
        super._approve(owner, spender, value, emitEvent);
    }

    // ============ Internal Functions ============

    /// @notice Revert if the user is blocked
    /// @param user Address to check
    function _revertIfBlocked(address user) internal view {
        if (blocked(user)) revert ERC20Blocked(user);
    }

    /// @notice Updates the liquidity index with accrued compound interest
    /// @dev Called before deposits and withdrawals to ensure index reflects current yield.
    ///      Includes overflow protection limiting growth to 10x per update.
    function _updateIndex() internal {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        uint256 timeElapsed = block.timestamp - $.lastUpdateTimestamp;

        if (timeElapsed == 0) return;

        uint256 newIndex = _getCurrentIndex();

        // Overflow protection: index should not grow more than 10x in a single update
        if (newIndex > $.liquidityIndex * 10) {
            revert InterestCalculationOverflow();
        }

        $.liquidityIndex = newIndex;
        $.lastUpdateTimestamp = block.timestamp;

        emit IndexUpdated(newIndex, block.timestamp);
    }

    /// @notice Remove user from pending withdrawal tracking array
    /// @dev Uses swap-and-pop pattern for O(1) removal
    /// @param user Address of user to remove
    function _removePendingWithdrawalUser(address user) internal {
        ShredVaultStorage storage $ = _getShredVaultStorage();

        uint256 index = $.pendingWithdrawalUserIndex[user];
        uint256 lastIndex = $.usersWithPendingWithdrawals.length - 1;

        // If not the last element, swap with last element
        if (index != lastIndex) {
            address lastUser = $.usersWithPendingWithdrawals[lastIndex];
            $.usersWithPendingWithdrawals[index] = lastUser;
            $.pendingWithdrawalUserIndex[lastUser] = index;
        }

        // Remove last element
        $.usersWithPendingWithdrawals.pop();
        delete $.pendingWithdrawalUserIndex[user];
    }
}
