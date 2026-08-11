// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC7540Upgradeable} from "./ERC7540Upgradeable.sol";
import {ERC7575Upgradeable} from "./ERC7575Upgradeable.sol";
import {Helper} from "./Helper.sol";
import {IERC7575} from "./interfaces/IERC7575.sol";
import {IVault} from "./interfaces/IVault.sol";
import {VaultOptions} from "./VaultOptions.sol";

/// @title Vault Contract
/// @author Sivo
/// @notice This contract manages the tokenization of receivables. As receivables become available the can be purchased with a stablecoin like USDC, USDT, EURC, etc. The contract is [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) compliant. The `asset()` function returns the asset contract address. The contract also handles redemption of receivable tokens (a.k.a. sTokens depending on the asset: sivoUSDC, sivoUSDT, sEURC, etc.). Pricing increases dynamically based on the amount of receivables that are sold.
/// @notice Deployed contract addresses:
/// | Chain Type | Name | ID | Contract Address |
/// | ------------ | ---------- | -------- | ---------------- |
/// | Mainnet      | Base       | 8453     | [0x63001191a63B9458D3Eafe7Ad704042B1Ae9C60B](https://basescan.org/token/0x63001191a63B9458D3Eafe7Ad704042B1Ae9C60B) |
/// | Testnet      | Base Sepolia | 84532   | [0xc8Bc7A069493fFb1953a6bf17B26c670CCEC54b6](https://sepolia.basescan.org/token/0xc8Bc7A069493fFb1953a6bf17B26c670CCEC54b6) |
/// @custom:security-contact security@sivo.com
contract Vault is
    Initializable,
    AccessControlEnumerableUpgradeable,
    ERC7540Upgradeable,
    IVault,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    UUPSUpgradeable,
    VaultOptions
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Options memory options) public virtual initializer {
        if (options.owner == address(0)) revert VaultZeroAddress();
        __ERC7575_init(options.asset, options.share);
        __AccessControl_init();
        __Pausable_init();
        __VaultOptions_init(
            options.oracle,
            options.price_min,
            options.price_max,
            options.max_staleness,
            options.instant_redeem_fee
        );
        _grantRole(DEFAULT_ADMIN_ROLE, options.owner);
        _grantRole(MANAGER_ROLE, options.owner);
        _grantRole(OPERATOR_ROLE, options.owner);
        _grantRole(PAUSER_ROLE, options.owner);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            AccessControlEnumerableUpgradeable,
            ERC7540Upgradeable,
            IERC165
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        _requirePriceInRange();
    }

    function _requirePriceInRange() internal view {
        VaultOptionsStorage storage $ = _getVaultOptionsStorage();
        address oracle = $._oracle;
        if (oracle == address(0)) return;
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(oracle).latestRoundData();
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert VaultOracleIncompleteRound(roundId, answeredInRound);
        }
        uint256 maxStaleness_ = $._maxStaleness;
        if (maxStaleness_ != 0 && block.timestamp - updatedAt > maxStaleness_) {
            revert VaultOracleStale(updatedAt, maxStaleness_);
        }
        if (price < $._priceMin || price > $._priceMax) {
            revert VaultPriceOutOfRange(price, $._priceMin, $._priceMax);
        }
    }

    /// @notice Updates the Chainlink oracle address and staleness duration
    /// @dev Can only be called by MANAGER_ROLE
    /// @dev Set maxStaleness_ to 0 to disable staleness check
    /// @param oracle_ The new Chainlink oracle address
    /// @param maxStaleness_ The new maximum staleness in seconds
    function setOracle(
        address oracle_,
        uint256 maxStaleness_
    ) external onlyRole(MANAGER_ROLE) {
        VaultOptionsStorage storage $ = _getVaultOptionsStorage();
        $._oracle = oracle_;
        $._maxStaleness = maxStaleness_;
        emit VaultOracleChange(oracle_, maxStaleness_);
    }

    /// @inheritdoc IVault
    function setInstantRedeemFee(uint64 fee) external onlyRole(MANAGER_ROLE) {
        _validateInstantRedeemFee(fee);
        VaultOptionsStorage storage $ = _getVaultOptionsStorage();
        $._instantRedeemFee = fee;
        emit VaultInstantRedeemFeeChange(fee);
    }

    /// @notice Updates the acceptable price range
    /// @dev Can only be called by MANAGER_ROLE
    /// @param priceMin_ The new minimum acceptable price
    /// @param priceMax_ The new maximum acceptable price
    function setPriceRange(
        int256 priceMin_,
        int256 priceMax_
    ) external onlyRole(MANAGER_ROLE) {
        _validatePriceRange(priceMin_, priceMax_);
        VaultOptionsStorage storage $ = _getVaultOptionsStorage();
        $._priceMin = priceMin_;
        $._priceMax = priceMax_;
        emit VaultPriceRangeChange(priceMin_, priceMax_);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Pauses the contract, preventing deposits and withdrawals
    /// @dev Can only be called by PAUSER_ROLE
    /// @dev When paused, the deposit and withdraw functions will revert
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract, allowing deposits and withdrawals
    /// @dev Can only be called by PAUSER_ROLE
    /// @dev Re-enables deposit and withdraw functionality after a pause
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _assetTotalInVault() internal view returns (uint) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function _shareTotalInVault() internal view returns (uint) {
        return _convertToShares(_assetTotalInVault(), Math.Rounding.Ceil);
    }

    function _redeemFee() internal view override returns (uint64) {
        return instantRedeemFee();
    }

    /// @inheritdoc IERC7575
    function maxWithdraw(
        address owner
    ) public view override(ERC7575Upgradeable, IERC7575) returns (uint256) {
        if (paused()) return 0;
        return Math.min(super.maxWithdraw(owner), _toNet(_assetTotalInVault()));
    }

    /// @inheritdoc IERC7575
    function maxRedeem(
        address owner
    ) public view override(ERC7575Upgradeable, IERC7575) returns (uint256) {
        if (paused()) return 0;
        return Math.min(super.maxRedeem(owner), _shareTotalInVault());
    }

    /// @inheritdoc IERC7575
    function maxDeposit(
        address
    ) public view override(ERC7575Upgradeable, IERC7575) returns (uint256) {
        if (paused()) return 0;
        uint assetTotalDeployed_ = _share().assetTotalDeployed();
        uint assetTotalIdle_ = _share().assetTotalIdle();
        uint assetTotal_ = assetTotalDeployed_ + assetTotalIdle_;
        if (assetTotal_ == 0) return type(uint).max;
        uint minDeployedFactor = Helper.FactorScale - _share().maxIdleFactor();
        if (minDeployedFactor == 0) return type(uint).max;
        uint maxTotalAssets = Math.mulDiv(
            assetTotalDeployed_,
            Helper.FactorScale,
            minDeployedFactor
        );
        return assetTotal_ > maxTotalAssets ? 0 : maxTotalAssets - assetTotal_;
    }

    /// @inheritdoc IERC7575
    function maxMint(
        address receiver
    ) public view override(ERC7575Upgradeable, IERC7575) returns (uint256) {
        if (paused()) return 0;
        return convertToShares(maxDeposit(receiver));
    }

    /// @inheritdoc IERC7575
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override(ERC7575Upgradeable, IERC7575)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _share().accrue();
        if (assets == type(uint).max) assets = maxDeposit(receiver);
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc IERC7575
    function mint(
        uint256 shares,
        address receiver
    )
        public
        override(ERC7575Upgradeable, IERC7575)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _share().accrue();
        if (shares == type(uint).max) shares = maxMint(receiver);
        return super.mint(shares, receiver);
    }

    /// @inheritdoc IERC7575
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override(ERC7540Upgradeable, IERC7575)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _share().accrue();
        if (assets == type(uint).max) {
            (uint shares, ) = _redeem(type(uint).max, receiver, owner);
            return shares;
        }
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC7575
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override(ERC7540Upgradeable, IERC7575)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _share().accrue();
        (, uint assets) = _redeem(shares, receiver, owner);
        return assets;
    }

    function _redeem(
        uint256 shares,
        address receiver,
        address owner
    ) private returns (uint256, uint256) {
        if (shares == type(uint).max) shares = maxRedeem(owner);
        uint assets = super.redeem(shares, receiver, owner);
        return (shares, assets);
    }

    /// @inheritdoc IVault
    function maxDeploy() public view returns (uint) {
        return Math.min(_share().maxDeploy(), _assetTotalInVault());
    }

    /// @inheritdoc IVault
    function deploy(
        uint assets,
        bytes calldata data
    ) external nonReentrant onlyRole(OPERATOR_ROLE) returns (uint) {
        _share().accrue();
        if (assets == type(uint).max) assets = maxDeploy();
        assets = _share().deploy(assets, data);
        address to = _msgSender();
        SafeERC20.safeTransfer(_asset(), to, assets);
        emit VaultDeployAsset(to, assets, data);
        return assets;
    }

    /// @inheritdoc IVault
    function recall(
        uint assets,
        bytes calldata data
    ) external nonReentrant onlyRole(OPERATOR_ROLE) returns (uint) {
        _share().accrue();
        address from = _msgSender();
        assets = _share().recall(assets, data);
        SafeERC20.safeTransferFrom(_asset(), from, address(this), assets);
        emit VaultRecallAsset(from, assets, data);
        return assets;
    }

    /// @inheritdoc IVault
    function claimableDeposit(
        uint256 assets,
        address controller
    ) external nonReentrant onlyRole(OPERATOR_ROLE) returns (uint256 shares) {
        _share().accrue();
        return _claimableDeposit(assets, controller);
    }

    /// @inheritdoc IVault
    function claimableRedeem(
        uint256 shares,
        address controller
    ) external nonReentrant onlyRole(OPERATOR_ROLE) returns (uint256 assets) {
        _share().accrue();
        return _claimableRedeem(shares, controller);
    }

    /// @inheritdoc IVault
    function claimFees(
        address to
    ) external nonReentrant onlyRole(OPERATOR_ROLE) returns (uint) {
        ERC7575Storage storage $ = _getERC7575Storage();
        uint fees = $._accumulatedFees;
        delete $._accumulatedFees;
        if (fees != 0) SafeERC20.safeTransfer(_asset(), to, fees);
        emit VaultClaimFees(to, fees);
        return fees;
    }
}
