// SPDX-License-Identifier: Unlicense
// All Rights Reserved © Yield
pragma solidity ^0.8.30;

// Inheritance
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPool } from "src/aave/interfaces/IPool.sol";
import { DataTypes } from "src/aave/interfaces/DataTypes.sol";

/// @title AaveV3Gateway
/// @notice ERC-4626 wrapper that routes deposits into Aave V3 and sources withdrawals from Aave V3 liquidity.
/// @dev
/// - Shares represent a pro-rata claim on this contract's aToken balance (see {totalAssets}).
/// - On deposit/mint, assets are first deposited into the ERC-4626 vault, then supplied to Aave via {IPool.supply}.
/// - On withdraw/redeem, shares are burned in the ERC-4626 vault, then assets are pulled from Aave via {IPool.withdraw}
///   and transferred to the receiver.
/// - maxDeposit/maxMint enforce Aave reserve status (active, not frozen, not paused) and the supply cap when set.
/// - maxWithdraw/maxRedeem additionally account for currently available underlying liquidity in the aToken contract.
/// - Upgradeable and intended for proxy use; constructor disables initializers and {initialize} must be called exactly
/// once.
contract AaveV3Gateway is ERC4626Upgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private constant ACTIVE_BIT = 56;
    uint256 private constant FROZEN_BIT = 57;
    uint256 private constant PAUSED_BIT = 60;
    uint256 private constant DECIMALS_SHIFT = 48;
    uint256 private constant DECIMALS_MASK = 0xFF;
    uint256 private constant SUPPLY_CAP_SHIFT = 116;
    uint256 private constant CAP_BITS = 36;
    uint256 private constant CAP_MASK = (uint256(1) << CAP_BITS) - 1;

    /// @notice Aave V3 Pool used for supplying and withdrawing the underlying asset.
    IPool public pool;

    /// @notice The Aave aToken corresponding to {asset} held by this vault.
    /// @dev {totalAssets} is defined as this contract's aToken balance.
    IERC20 public aToken;

    /// @notice Aave referral code forwarded to {IPool.supply}.
    uint16 public referralCode;

    /// @notice Event emitted when refferral code is updated.
    /// @param newReferralCode The new referral code.
    event ReferralCodeUpdated(uint16 newReferralCode);

    /// @notice Thrown when a required address is zero.
    error ZeroAddress();

    /// @notice Thrown when trying to work with zero assets
    error ZeroAssets();

    /// @notice Thrown when trying to work with zero shares
    error ZeroShares();

    /// @notice Address mismatch between aToken and asset
    error AddressMismatch();

    /// @dev Disables initializer on the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the upgradeable ERC-4626 vault wrapper.
    /// @dev
    /// - MUST be called exactly once (initializer).
    /// - Initializes ERC20 name/symbol, ERC4626 underlying asset, and AccessControl.
    /// - Grants {DEFAULT_ADMIN_ROLE} to specified initial admin
    /// - Stores the Aave `referralCode` used on supply operations.
    /// @param _asset The underlying ERC20 asset deposited into Aave.
    /// @param _name ERC20 share token name.
    /// @param _symbol ERC20 share token symbol.
    /// @param _admin Address to be granted {DEFAULT_ADMIN_ROLE}.
    /// @param _referralCode Aave referral code forwarded to {IPool.supply}.
    function initialize(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        IPool _pool,
        IERC20 _aToken,
        address _admin,
        uint16 _referralCode
    )
        external
        initializer
    {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __AccessControl_init();
        if (_admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // setup pool
        if (address(_pool) == address(0)) revert ZeroAddress();
        pool = _pool;

        // setup aToken
        if (address(_aToken) == address(0)) revert ZeroAddress();
        DataTypes.ReserveDataLegacy memory rd = _pool.getReserveData(address(_asset));
        if (rd.aTokenAddress != address(_aToken)) revert AddressMismatch();
        aToken = _aToken;
        referralCode = _referralCode;
    }

    /// @notice Reads a single bit from a packed Aave configuration word.
    /// @param data Packed configuration data.
    /// @param bit Bit index to read.
    /// @return True if the bit is set.
    function _bit(uint256 data, uint256 bit) internal pure returns (bool) {
        return ((data >> bit) & 1) == 1;
    }

    /// @notice Extracts the underlying asset decimals encoded in Aave configuration.
    /// @param data Packed configuration data.
    /// @return The decimals value.
    function _decimals(uint256 data) internal pure returns (uint8) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8((data >> DECIMALS_SHIFT) & DECIMALS_MASK);
    }

    /// @notice Extracts the supply cap (whole units) encoded in Aave configuration.
    /// @dev The returned value must be scaled by `10 ** decimals` to obtain the cap in underlying units.
    /// @param data Packed configuration data.
    /// @return Supply cap expressed in whole tokens (pre-decimal scaling).
    function _supplyCapWhole(uint256 data) internal pure returns (uint256) {
        return (data >> SUPPLY_CAP_SHIFT) & CAP_MASK;
    }

    /// @notice Updates the Aave referral code used for subsequent supplies.
    /// @param _referralCode The new referral code.
    /// @dev Only callable by {DEFAULT_ADMIN_ROLE}.
    function setReferralCode(uint16 _referralCode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        referralCode = _referralCode;
        emit ReferralCodeUpdated(_referralCode);
    }

    /// @notice Returns the total amount of underlying assets managed by the vault.
    /// @dev Defined as this contract's aToken balance (not the underlying balance).
    /// @return Total assets in underlying units.
    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice Maximum amount of assets that may be deposited for a receiver.
    /// @dev
    /// Returns 0 if the Aave reserve is inactive, frozen, or paused.
    /// If the reserve supply cap is 0 (interpreted by Aave as "no cap"), returns max uint256.
    /// Otherwise returns remaining cap headroom in underlying units.
    /// @return Maximum deposit amount in underlying units.
    function maxDeposit(address) public view override returns (uint256) {
        DataTypes.ReserveDataLegacy memory rd = pool.getReserveData(address(asset()));
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isFrozen = _bit(c, FROZEN_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isFrozen && !isPaused)) return 0;
        uint256 supplyCapWhole = _supplyCapWhole(c);
        if (supplyCapWhole == 0) return type(uint256).max;
        uint8 dec = _decimals(c);
        uint256 supplyCap = supplyCapWhole * 10 ** uint256(dec);
        uint256 totalSupply = aToken.totalSupply();
        if (totalSupply >= supplyCap) return 0;
        return supplyCap - totalSupply;
    }

    /// @notice Deposits `assets` and mints shares to `receiver`, then supplies assets into Aave.
    /// @dev
    /// - After ERC-4626 accounting, approves the Aave pool for `assets` and calls {IPool.supply}.
    /// @param _assets Amount of underlying assets to deposit.
    /// @param _receiver Address receiving minted shares.
    /// @return shares Amount of shares minted.
    function deposit(uint256 _assets, address _receiver) public override returns (uint256) {
        if (_assets == 0) revert ZeroAssets();
        uint256 shares = super.deposit(_assets, _receiver);
        IERC20(asset()).forceApprove(address(pool), _assets);
        pool.supply(asset(), _assets, address(this), referralCode);
        return shares;
    }

    /// @notice Maximum amount of shares that may be minted for a receiver.
    /// @dev
    /// Returns 0 if the Aave reserve is inactive, frozen, or paused.
    /// If the reserve supply cap is 0, returns max uint256.
    /// Otherwise returns share amount corresponding to remaining cap headroom.
    /// @return Maximum mint amount in shares.
    function maxMint(address) public view override returns (uint256) {
        DataTypes.ReserveDataLegacy memory rd = pool.getReserveData(address(asset()));
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isFrozen = _bit(c, FROZEN_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isFrozen && !isPaused)) return 0;
        uint256 supplyCapWhole = _supplyCapWhole(c);
        if (supplyCapWhole == 0) return type(uint256).max;

        uint8 dec = _decimals(c);
        uint256 supplyCap = supplyCapWhole * 10 ** uint256(dec);
        uint256 totalSupply = aToken.totalSupply();
        if (totalSupply >= supplyCap) return 0;
        return convertToShares(supplyCap - totalSupply);
    }

    /// @notice Mints `shares` to `receiver` by depositing assets, then supplies the assets into Aave.
    /// @dev
    /// - After ERC-4626 accounting, approves the Aave pool for `assets` and calls {IPool.supply}.
    /// @param _shares Amount of shares to mint.
    /// @param _receiver Address receiving minted shares.
    /// @return assets Amount of underlying assets deposited.
    function mint(uint256 _shares, address _receiver) public override returns (uint256) {
        if (_shares == 0) revert ZeroShares();
        uint256 assets = super.mint(_shares, _receiver);
        IERC20(asset()).forceApprove(address(pool), assets);
        pool.supply(asset(), assets, address(this), referralCode);
        return assets;
    }

    /// @notice Maximum amount of assets that may be withdrawn by `owner`.
    /// @dev
    /// Returns 0 if the Aave reserve is inactive or paused.
    /// Limited by:
    /// - the owner's redeemable assets (based on their share balance), and
    /// - current available underlying liquidity held by the aToken contract.
    /// @param _owner Address whose shares would be burned.
    /// @return Maximum withdrawable assets in underlying units.
    function maxWithdraw(address _owner) public view override returns (uint256) {
        DataTypes.ReserveDataLegacy memory rd = pool.getReserveData(address(asset()));
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isPaused)) return 0;
        uint256 availableLiquidity = IERC20(asset()).balanceOf(address(aToken));
        uint256 ownerAssets = previewRedeem(balanceOf(_owner));
        return availableLiquidity < ownerAssets ? availableLiquidity : ownerAssets;
    }

    /// @notice Withdraws `assets` to `receiver` by burning shares from `owner`, pulling liquidity from Aave.
    /// @dev
    /// - If `msg.sender != owner`, allowance is spent.
    /// - Calls {IPool.withdraw} specifying `receiver` as the destination
    /// @param _assets Amount of underlying assets to withdraw.
    /// @param _receiver Address receiving underlying assets.
    /// @param _owner Address whose shares are burned.
    /// @return shares Amount of shares burned.
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    )
        public
        override
        returns (uint256)
    {
        if (_assets == 0) revert ZeroAssets();
        uint256 maxAssets = maxWithdraw(_owner);
        if (_assets > maxAssets) revert ERC4626ExceededMaxWithdraw(_owner, _assets, maxAssets);
        uint256 shares = previewWithdraw(_assets);
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, shares);
        _burn(_owner, shares);
        pool.withdraw(address(asset()), _assets, _receiver);
        emit Withdraw(msg.sender, _receiver, _owner, _assets, shares);
        return shares;
    }

    /// @notice Maximum amount of shares that may be redeemed by `owner`.
    /// @dev
    /// Returns 0 if the Aave reserve is inactive or paused.
    /// Limited by:
    /// - the owner's share balance, and
    /// - current available underlying liquidity (converted to shares).
    /// @param _owner Address whose shares would be redeemed.
    /// @return Maximum redeemable shares.
    function maxRedeem(address _owner) public view override returns (uint256) {
        DataTypes.ReserveDataLegacy memory rd = pool.getReserveData(address(asset()));
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isPaused)) return 0;
        uint256 ownerShares = balanceOf(_owner);
        uint256 availableLiquidity = IERC20(asset()).balanceOf(address(aToken));
        uint256 availableShares = convertToShares(availableLiquidity);
        return availableShares < ownerShares ? availableShares : ownerShares;
    }

    /// @notice Redeems `shares` from `owner` to `receiver`, pulling underlying from Aave.
    /// @dev
    /// - If `msg.sender != owner`, allowance is spent before burning shares.
    /// - Calls {IPool.withdraw} specifying `receiver` as the destination
    /// @param _shares Amount of shares to redeem.
    /// @param _receiver Address receiving underlying assets.
    /// @param _owner Address whose shares are burned.
    /// @return assets Amount of underlying assets withdrawn.
    function redeem(uint256 _shares, address _receiver, address _owner) public override returns (uint256) {
        if (_shares == 0) revert ZeroShares();
        uint256 maxShares_ = maxRedeem(_owner);
        if (_shares > maxShares_) revert ERC4626ExceededMaxRedeem(_owner, _shares, maxShares_);
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, _shares);
        uint256 assets = previewRedeem(_shares);
        if (assets == 0) revert ZeroAssets();
        _burn(_owner, _shares);
        pool.withdraw(address(asset()), assets, _receiver);
        emit Withdraw(msg.sender, _receiver, _owner, assets, _shares);
        return assets;
    }
}