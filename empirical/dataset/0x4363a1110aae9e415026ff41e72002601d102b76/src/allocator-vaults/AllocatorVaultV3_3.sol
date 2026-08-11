// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AllocatorVaultV3_3
 * @dev Implementation of an ERC4626 compliant Allocator Vault with fee management.
 * The vault delegates asset management to a strategy contract while handling deposits,
 * withdrawals, and fee calculations.
 */
contract AllocatorVaultV3_3 is ERC4626Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a harvest operation is executed
    /// @param caller The address that initiated the harvest
    /// @param sharesMinted The number of fee shares minted during the harvest
    /// @param previousTotalUnderlying The total underlying assets before harvest
    /// @param currentTotalUnderlying The total underlying assets after harvest
    event Harvested(
        address indexed caller, uint256 sharesMinted, uint256 previousTotalUnderlying, uint256 currentTotalUnderlying
    );

    /// @notice Emitted when the vault configuration is updated
    /// @param config The new configuration applied to the vault
    event VaultConfigured(AllocatorVaultConfig config);

    /// @notice Emitted when the vault is paused or unpaused
    /// @param paused The new paused state (true if paused)
    event PausedSet(bool paused);

    /// @notice Emitted when a target and selector are added to or removed from the whitelist
    /// @param target The address of the contract target
    /// @param selector The 4-byte function selector affected
    /// @param added True if added to whitelist, false if removed
    event Whitelisted(address indexed target, bytes4 selector, bool added);

    /// @notice Emitted when additional reward tokens are claimed and transferred
    /// @param target The address of the contract call used to claim rewards
    /// @param asset The address of the reward token claimed
    /// @param amount The amount of tokens successfully claimed
    event RewardsClaimed(address indexed target, address indexed asset, uint256 amount);

    /// @notice Emitted when miscellaneous ERC20 tokens are swept to the fee recipient
    /// @param asset The address of the token being swept
    /// @param amount The amount of tokens transferred
    event MiscellaneousRewardClaimed(address indexed asset, uint256 amount);

    /**
     * @dev Configuration for the vault's fee structure and behavior
     * @param depositFee Fee charged when depositing assets (in basis points)
     * @param performanceFee Fee charged on performance gains (in basis points)
     * @param managementFee Ongoing fee for management (in basis points)
     * @param feeRecipient Address that receives collected fees
     * @param hasCooldown Whether withdrawals are subject to a cooldown period
     */
    struct AllocatorVaultConfig {
        uint256 depositFee;
        uint256 performanceFee;
        uint256 managementFee;
        address feeRecipient;
        bool hasCooldown;
    }

    // Constants
    uint256 private constant MAX_BPS = 10_000_000_000;
    uint256 private constant MAX_PERF_FEE = 5_000_000_000;
    uint256 private constant MAX_MGMT_FEE = 1_000_000_000;
    uint256 private constant MAX_DEP_FEE = 500_000_000;
    uint256 private constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    uint256 private constant VIRTUAL_ASSETS = 1;
    uint256 private constant VIRTUAL_SHARES = 10 ** 6;
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

    // Variables
    bool public paused;
    address public underlying;
    AllocatorVaultConfig public config;
    IERC4626 public strategy;
    uint256 public lastStamp;
    uint256 public totalUnderlyingStamp;

    mapping(address target => mapping(bytes4 selector => bool isWhitelisted)) public whitelistedTargets;

    // modifiers
    /**
     * @dev Ensures the vault is not paused when executing function
     */
    modifier notPaused() {
        require(!paused, "Paused");
        _;
    }

    /**
     * @dev Initializes the vault with the specified parameters
     * @param _underlying Address of the underlying token
     * @param _strategy Strategy contract that will manage the assets
     * @param vaultTokenName Name for the vault's share token
     * @param vaultTokenSymbol Symbol for the vault's share token
     */
    function initialize(
        address _underlying,
        IERC4626 _strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol
    )
        public
        initializer
    {
        __ERC4626_init(IERC20(address(_strategy)));
        __ERC20_init(vaultTokenName, vaultTokenSymbol);
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(HARVESTER_ROLE, msg.sender);

        require(address(_strategy) != address(0), "Invalid strategy");
        require(_underlying != address(0), "Invalid underlying token");
        require(_underlying == _strategy.asset(), "Underlying token mismatch");
        assert(address(_strategy) == asset());
        strategy = _strategy;
        underlying = _underlying;
        lastStamp = block.timestamp;
    }

    /**
     * @dev Sets the configuration for the vault
     * @param _config New configuration to apply
     */
    function configureVault(AllocatorVaultConfig memory _config) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_config.depositFee <= MAX_DEP_FEE, "Deposit fee too high");
        require(_config.performanceFee <= MAX_PERF_FEE, "Performance fee too high");
        require(_config.managementFee <= MAX_MGMT_FEE, "Management fee too high");
        require(_config.feeRecipient != address(0), "Invalid fee recipient");
        config = _config;
        emit VaultConfigured(_config);
    }

    /**
     * @dev Pauses or unpauses the vault
     * @param _paused New paused state
     */
    function setPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = _paused;
        emit PausedSet(_paused);
    }

    /**
     * @dev Returns the total amount of assets in the vault
     * @notice the contract's assets are actually the strategy's shares. This function returns
     * the amount of strategy shares that this vault holds, not the underlying tokens.
     * @return Total strategy shares held by the vault
     */
    function totalAssets() public view override returns (uint256) {
        return strategy.balanceOf(address(this));
    }

    /**
     * @dev Converts an amount of assets to an equivalent amount of shares, with optional ceiling rounding
     * @param assets Amount of assets to convert
     * @param ceil If true, rounds up to ensure sufficient shares; if false, performs standard rounding
     * @return Amount of shares corresponding to the assets
     */
    function _convertToShares(uint256 assets, bool ceil) internal view returns (uint256) {
        if (ceil) {
            uint256 numerator = assets * (totalSupply() + VIRTUAL_SHARES);
            uint256 denominator = totalAssets() + VIRTUAL_ASSETS;
            uint256 shares = (numerator + denominator - 1) / denominator;
            return shares;
        } else {
            return (assets * (totalSupply() + VIRTUAL_SHARES)) / (totalAssets() + VIRTUAL_ASSETS);
        }
    }

    /**
     * @dev Converts an amount of assets to an equivalent amount of shares
     * @param assets Amount of assets to convert
     * @return Amount of shares
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, false);
    }

    /**
     * @dev Converts an amount of shares to an equivalent amount of assets, with optional ceiling rounding
     * @param shares Amount of shares to convert
     * @param ceil If true, rounds up to ensure sufficient assets; if false, performs standard rounding
     * @return Amount of assets corresponding to the shares
     */
    function _convertToAssets(uint256 shares, bool ceil) internal view returns (uint256) {
        if (ceil) {
            uint256 numerator = shares * (totalAssets() + VIRTUAL_ASSETS);
            uint256 denominator = totalSupply() + VIRTUAL_SHARES;
            uint256 assets = (numerator + denominator - 1) / denominator;
            return assets;
        } else {
            return (shares * (totalAssets() + VIRTUAL_ASSETS)) / (totalSupply() + VIRTUAL_SHARES);
        }
    }

    /**
     * @dev Converts an amount of shares to an equivalent amount of assets
     * @param shares Amount of shares to convert
     * @return Amount of assets
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /**
     * @dev Computes the user and fee share mints for a deposit given the amount of strategy shares
     *      the vault will receive.
     * @param assets The amount of strategy shares that will be credited to this vault.
     * @param totalAssetsBefore The vault's totalAssets() *before* the deposit is applied.
     * @param totalSharesBefore The vault's totalSupply() used for pricing (simulated or actual post-harvest).
     * @return userShares The shares to mint to the receiver.
     * @return feeShares The shares to mint to the fee recipient (0 if depositFee is 0).
     */
    function _calculateDepositShares(
        uint256 assets,
        uint256 totalAssetsBefore,
        uint256 totalSharesBefore
    )
        internal
        view
        returns (uint256, uint256)
    {
        uint256 grossShares = (assets * (totalSharesBefore + VIRTUAL_SHARES)) / (totalAssetsBefore + VIRTUAL_ASSETS);

        if (config.depositFee == 0) {
            return (grossShares, 0);
        }

        uint256 userShares = (grossShares * (MAX_BPS - config.depositFee)) / MAX_BPS;
        uint256 feeShares = grossShares - userShares;

        return (userShares, feeShares);
    }

    /**
     * @dev Simulates the effects of a deposit at the current block, returning the expected shares
     * @param _underlying Amount of underlying tokens to deposit
     * @return Expected amount of shares to be received
     */
    function previewDeposit(uint256 _underlying) public view override returns (uint256) {
        uint256 assets = strategy.previewDeposit(_underlying);

        uint256 totalSharesSimulated = previewHarvest();
        uint256 totalAssetsBefore = totalAssets();

        (uint256 userShares,) = _calculateDepositShares(assets, totalAssetsBefore, totalSharesSimulated);

        return userShares;
    }

    /**
     * @dev Returns the maximum amount of underlying tokens that can be deposited by the receiver
     * @param receiver Address that would receive the shares
     * @return Maximum amount of underlying tokens
     */
    function maxDeposit(address receiver) public view override returns (uint256) {
        if (paused) {
            return 0;
        }
        return super.maxDeposit(receiver);
    }

    /**
     * @dev Deposits underlying tokens into the vault
     * @param _underlying Amount of underlying tokens to deposit
     * @param receiver Address that will receive the shares
     * @notice Harvest is called before the deposit to ensure all accrued fees are
     * properly collected before changing the deposit state, maintaining accurate
     * accounting and fee distribution
     * @return Amount of shares minted
     */
    function deposit(uint256 _underlying, address receiver) public override notPaused nonReentrant returns (uint256) {
        uint256 maxUnderlying = maxDeposit(receiver);
        require(_underlying <= maxUnderlying, "Exceeded max deposit");

        uint256 expectedAssets = strategy.previewDeposit(_underlying);
        require(expectedAssets > 0, "Insufficient deposit amount");

        _harvest();

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), _underlying);
        uint256 previousTotalAssets = totalAssets();

        IERC20(underlying).forceApprove(address(strategy), _underlying);

        uint256 receivedAssets = strategy.deposit(_underlying, address(this));

        (uint256 userShares, uint256 feeShares) =
            _calculateDepositShares(receivedAssets, previousTotalAssets, totalSupply());

        totalUnderlyingStamp = strategy.previewRedeem(totalAssets());
        lastStamp = block.timestamp;

        _mint(receiver, userShares);
        if (feeShares > 0) {
            _mint(config.feeRecipient, feeShares);
        }

        emit Deposit(msg.sender, receiver, _underlying, userShares);
        return userShares;
    }

    /**
     * @dev Simulates the effects of a mint at the current block, returning the expected amount of underlying tokens
     * @param shares Amount of shares to mint
     * @return Expected amount of underlying tokens needed
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 newTotalShares = previewHarvest();
        uint256 actualShares = (shares * MAX_BPS) / (MAX_BPS - config.depositFee);

        // round up
        uint256 numerator = actualShares * (totalAssets() + VIRTUAL_ASSETS);
        uint256 denominator = newTotalShares + VIRTUAL_SHARES;
        uint256 assets = (numerator + denominator - 1) / denominator;
        return strategy.previewMint(assets);
    }

    /**
     * @dev Returns the maximum amount of shares that can be minted by the receiver
     * @param receiver Address that would receive the shares
     * @return Maximum amount of shares
     */
    function maxMint(address receiver) public view override returns (uint256) {
        if (paused) {
            return 0;
        }
        return super.maxMint(receiver);
    }

    /**
     * @dev Mints the specified amount of shares to the receiver by depositing underlying tokens
     * @param shares Amount of shares to mint
     * @param receiver Address that will receive the shares
     * @return Amount of underlying tokens deposited
     */
    function mint(uint256 shares, address receiver) public override notPaused nonReentrant returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        require(shares > 0, "Cannot mint 0");
        require(shares <= maxShares, "Exceeded max mint");

        uint256 _underlying = previewMint(shares);
        _harvest();

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), _underlying);

        IERC20(underlying).forceApprove(address(strategy), _underlying);
        strategy.deposit(_underlying, address(this));

        uint256 newShares = (shares * MAX_BPS) / (MAX_BPS - config.depositFee);
        uint256 feeShares = newShares - shares;

        totalUnderlyingStamp = strategy.previewRedeem(totalAssets());
        lastStamp = block.timestamp;

        _mint(receiver, shares);
        if (feeShares > 0) {
            _mint(config.feeRecipient, feeShares);
        }

        emit Deposit(msg.sender, receiver, _underlying, shares);
        return _underlying;
    }

    /**
     * @dev Returns the maximum amount of underlying tokens that can be withdrawn by the receiver
     * @param receiver Address that would receive the underlying tokens
     * @return Maximum amount of underlying tokens
     */
    function maxWithdraw(address receiver) public view override returns (uint256) {
        if (paused) return 0;
        uint256 shares = balanceOf(receiver);
        uint256 _underlying = previewRedeem(shares);
        return _underlying;
    }

    /**
     * @dev Simulates the effects of a withdrawal at the current block, returning the expected shares needed
     * @param _underlying Amount of underlying tokens to withdraw
     * @return Expected amount of shares to be burned
     */
    function previewWithdraw(uint256 _underlying) public view override returns (uint256) {
        uint256 assets = strategy.previewWithdraw(_underlying);
        uint256 newTotalShares = previewHarvest();

        if (newTotalShares == 0) {
            return 0;
        }

        uint256 numerator = assets * (newTotalShares + VIRTUAL_SHARES);
        uint256 denominator = totalAssets() + VIRTUAL_ASSETS;
        uint256 shares = (numerator + denominator - 1) / denominator;

        return shares;
    }

    /**
     * @dev Withdraws the specified amount of underlying tokens to the receiver
     * @param _underlying Amount of underlying tokens to withdraw
     * @param receiver Address that will receive the underlying tokens
     * @param owner Address that owns the shares to be burned
     * @return Amount of shares burned
     */
    function withdraw(
        uint256 _underlying,
        address receiver,
        address owner
    )
        public
        override
        notPaused
        nonReentrant
        returns (uint256)
    {
        uint256 maxUnderlying = maxWithdraw(owner);
        require(_underlying > 0, "Cannot withdraw 0");
        require(_underlying <= maxUnderlying, "Exceeded max withdraw");

        _harvest();

        uint256 assets = strategy.previewWithdraw(_underlying);
        uint256 shares = _convertToShares(assets, true);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        if (config.hasCooldown) {
            IERC20(address(strategy)).safeTransfer(receiver, assets);
        } else {
            strategy.withdraw(_underlying, receiver, address(this));
        }

        totalUnderlyingStamp = strategy.previewRedeem(totalAssets());
        lastStamp = block.timestamp;

        emit Withdraw(msg.sender, receiver, owner, _underlying, shares);

        return shares;
    }

    /**
     * @dev Returns the maximum amount of shares that can be redeemed by the owner
     * @param owner Address that owns the shares
     * @return Maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused) return 0;
        return balanceOf(owner);
    }

    /**
     * @dev Simulates the effects of a redemption at the current block, returning the expected amount of underlying
     * tokens
     * @param shares Amount of shares to redeem
     * @return Expected amount of underlying tokens to be received
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 newTotalShares = previewHarvest();
        if (newTotalShares == 0) {
            return 0;
        }

        uint256 strategyShares = shares * (totalAssets() + VIRTUAL_ASSETS) / (newTotalShares + VIRTUAL_SHARES);
        return strategy.previewRedeem(strategyShares);
    }

    /**
     * @dev Redeems the specified amount of shares for underlying tokens
     * @param shares Amount of shares to redeem
     * @param receiver Address that will receive the underlying tokens
     * @param owner Address that owns the shares to be burned
     * @return Amount of underlying tokens received
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override
        notPaused
        nonReentrant
        returns (uint256)
    {
        uint256 maxShares = maxRedeem(owner);
        require(shares > 0, "Cannot redeem 0");
        require(shares <= maxShares, "Exceeded max redeem");

        _harvest();

        uint256 assets = _convertToAssets(shares, false);
        uint256 _underlying = strategy.previewRedeem(assets);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        if (config.hasCooldown) {
            IERC20(address(strategy)).safeTransfer(receiver, assets);
        } else {
            strategy.redeem(assets, receiver, address(this));
        }

        totalUnderlyingStamp = strategy.previewRedeem(totalAssets());
        lastStamp = block.timestamp;

        emit Withdraw(msg.sender, receiver, owner, _underlying, shares);
        return _underlying;
    }

    /**
     * @dev Previews the effect of a harvest operation without executing it
     * @return Expected total supply after harvest fees are applied
     */
    function previewHarvest() internal view returns (uint256) {
        uint256 fee = computeHarvestFee();
        uint256 newShares = (totalSupply() + VIRTUAL_SHARES) * fee / (MAX_BPS - fee);
        return totalSupply() + newShares;
    }

    /**
     * @dev Internal harvest implementation that mints fee shares to the fee recipient
     * @return Amount of new shares minted as fees
     */
    function _harvest() internal returns (uint256) {
        uint256 previousTotalUnderlying = totalUnderlyingStamp;
        uint256 fee = computeHarvestFee();
        uint256 newShares = (totalSupply() + VIRTUAL_SHARES) * fee / (MAX_BPS - fee);
        if (newShares != 0) {
            _mint(config.feeRecipient, newShares);
        }
        totalUnderlyingStamp = strategy.previewRedeem(totalAssets());
        lastStamp = block.timestamp;
        emit Harvested(msg.sender, newShares, previousTotalUnderlying, totalUnderlyingStamp);
        return newShares;
    }

    /**
     * @dev Executes a harvest operation, minting fee shares to the fee recipient
     * @return Amount of new shares minted as fees
     */
    function harvest() public onlyRole(HARVESTER_ROLE) returns (uint256) {
        return _harvest();
    }

    /**
     * @dev Calculates the harvest fee based on management and performance parameters
     * @return Fee amount in basis points
     */
    function computeHarvestFee() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastStamp;

        uint256 mgmtFeeNum = config.managementFee * timeElapsed;
        uint256 perfFeeNum = config.performanceFee * SECONDS_IN_YEAR;

        if (timeElapsed == 0) {
            return 0;
        }

        uint256 currentTotalUnderlying = strategy.previewRedeem(totalAssets());

        if (currentTotalUnderlying == 0) {
            return 0;
        }

        uint256 gain = 0;
        if (currentTotalUnderlying > totalUnderlyingStamp) {
            gain = currentTotalUnderlying - totalUnderlyingStamp;
        }

        uint256 fee =
            (totalUnderlyingStamp * mgmtFeeNum + gain * perfFeeNum) / (currentTotalUnderlying * SECONDS_IN_YEAR);

        return fee;
    }

    /**
     * @dev Adds a contract and function selector to the whitelist
     * @param target The target contract address
     * @param functionSelector The 4-byte function selector
     */
    function addToWhitelist(address target, bytes4 functionSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(target != address(0), "Invalid target address");
        require(target != underlying, "Cannot whitelist underlying");
        require(functionSelector != bytes4(0), "Invalid function selector");
        require(!whitelistedTargets[target][functionSelector], "Already whitelisted");
        require(target != address(strategy), "Cannot whitelist strategy");
        whitelistedTargets[target][functionSelector] = true;
        emit Whitelisted(target, functionSelector, true);
    }

    /**
     * @dev Removes a contract and function selector from the whitelist
     * @param target The target contract address
     * @param functionSelector The 4-byte function selector
     */
    function removeFromWhitelist(address target, bytes4 functionSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistedTargets[target][functionSelector] = false;
        emit Whitelisted(target, functionSelector, false);
    }

    /// @dev Rewards tokens are sent directly to the fee recipient since they aren't the underlying asset.
    /// @param target The target contract to call (Morpho ETH Bundler V2).
    /// @param rewardsAsset The rewards asset to claim (MORPHO token).
    /// @param payload The payload to pass to the target.
    function claimAdditionalRewards(
        address target,
        address rewardsAsset,
        bytes calldata payload
    )
        external
        nonReentrant
        onlyRole(HARVESTER_ROLE)
    {
        require(target != address(0), "Invalid target");
        require(rewardsAsset != address(0), "Invalid rewards asset");
        require(payload.length >= 4, "Invalid payload");

        bytes4 functionSelector = bytes4(payload[:4]);
        require(whitelistedTargets[target][functionSelector], "Target not whitelisted");

        require(rewardsAsset != address(underlying), "Cannot claim underlying asset");
        require(rewardsAsset != address(strategy), "Cannot claim strategy asset");
        require(rewardsAsset != address(this), "Cannot claim vault asset");

        uint256 rewardsBalanceBefore = IERC20(rewardsAsset).balanceOf(address(this));
        uint256 sharesBefore = totalSupply();
        uint256 assetsBefore = totalAssets();
        (bool success,) = target.call(payload);
        require(success, "Call to target failed");

        uint256 rewardsBalanceAfter = IERC20(rewardsAsset).balanceOf(address(this));
        uint256 rewardsReceived = rewardsBalanceAfter - rewardsBalanceBefore;
        require(sharesBefore == totalSupply(), "Shares changed during claim");
        require(assetsBefore == totalAssets(), "Assets changed during claim");
        if (rewardsReceived > 0) {
            IERC20(rewardsAsset).safeTransfer(config.feeRecipient, rewardsReceived);
        }
        emit RewardsClaimed(target, rewardsAsset, rewardsReceived);
    }

    /**
     * @notice Transfers any non strategy related ERC-20 tokens from the vault to the fee recipient.
     * @dev Uses `safeTransfer` since the vault owns the tokens. No approval is needed.
     * @param tokenAddress The ERC-20 token contract address to sweep.
     */
    function claimMiscellaneousRewards(address tokenAddress) external nonReentrant onlyRole(HARVESTER_ROLE) {
        require(tokenAddress != address(0), "Invalid target");
        require(tokenAddress != address(underlying), "Cannot claim underlying");
        require(tokenAddress != address(strategy), "Cannot claim from strategy");
        require(tokenAddress != address(this), "Cannot claim from vault");

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No balance to claim");
        token.safeTransfer(config.feeRecipient, balance);
        emit MiscellaneousRewardClaimed(tokenAddress, balance);
    }
}
