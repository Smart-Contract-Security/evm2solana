// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Helper} from "./Helper.sol";
import {IShare} from "./interfaces/IShare.sol";
import {ShareOptions} from "./ShareOptions.sol";
import {ShareStore} from "./ShareStore.sol";

/// @custom:security-contact security@sivo.com
contract Share is
    Initializable,
    AccessControlEnumerableUpgradeable,
    ERC20PausableUpgradeable,
    ERC20PermitUpgradeable,
    IShare,
    ReentrancyGuardTransient,
    ShareOptions,
    ShareStore,
    UUPSUpgradeable
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Options memory options) public initializer {
        if (options.owner == address(0)) revert ShareZeroAddress();
        _validateIdleFactor(options.minIdleFactor, options.maxIdleFactor);
        __ERC20_init(options.name, options.symbol);
        __ERC20Pausable_init();
        __ERC20Permit_init(options.name);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, options.owner);
        _grantRole(MANAGER_ROLE, options.owner);
        _grantRole(OPERATOR_ROLE, options.owner);
        _grantRole(PAUSER_ROLE, options.owner);
        ShareStorage storage $ = _getShareStorage();
        $.decimals = options.decimals;
        $.lastAccrualTime = time();
        $.discountRateSlope =
            options.annualDiscountRateSlope /
            Helper.SecondsPerYear;
        $.discountRateBase =
            options.annualDiscountRateBase /
            Helper.SecondsPerYear;
        emit DiscountChange($.discountRateBase, $.discountRateSlope);
        $.minIdleFactor = options.minIdleFactor;
        $.maxIdleFactor = options.maxIdleFactor;
        emit IdleFactorChange($.minIdleFactor, $.maxIdleFactor);
    }

    /// @notice Validates the idle factor range invariant: 0 <= min <= max <= FactorScale
    /// @dev Reverts with ShareInvalidIdleFactorRange or ShareIdleFactorExceedsScale
    /// @param minIdleFactor_ The candidate minimum idle factor
    /// @param maxIdleFactor_ The candidate maximum idle factor
    function _validateIdleFactor(
        uint64 minIdleFactor_,
        uint64 maxIdleFactor_
    ) private pure {
        if (minIdleFactor_ > maxIdleFactor_) {
            revert ShareInvalidIdleFactorRange(minIdleFactor_, maxIdleFactor_);
        }
        if (maxIdleFactor_ > Helper.FactorScale) {
            revert ShareIdleFactorExceedsScale(maxIdleFactor_);
        }
    }

    /**
     * @dev Throws if the sender is not a vault.
     */
    modifier onlyVault() {
        _checkVault();
        _;
    }

    /**
     * @dev Throws if the sender is not a vault or OPERATOR_ROLE.
     */
    modifier onlyOperatorOrVault() {
        if (!_isVault()) _checkRole(OPERATOR_ROLE);
        _;
    }

    /**
     * @dev Throws if the sender is not a vault.
     */
    function _checkVault() internal view virtual {
        if (_isVault()) return;
        revert ShareUnauthorizedVault();
    }

    function _isVault() internal view virtual returns (bool) {
        ShareStorage storage $ = _getShareStorage();
        return $.isVault[_msgSender()];
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Updates the discount rate parameters
    /// @dev Can only be called by MANAGER_ROLE
    /// @dev Accrues before updating parameters
    /// @dev Emits a DiscountChange event with the new values
    /// @param annualDiscountRateBase The new annual discount rate base
    /// @param annualDiscountRateSlope The new annual discount rate slope
    function updateDiscount(
        uint64 annualDiscountRateBase,
        uint64 annualDiscountRateSlope
    ) external onlyRole(MANAGER_ROLE) {
        _accrue();
        ShareStorage storage $ = _getShareStorage();
        $.discountRateSlope = annualDiscountRateSlope / Helper.SecondsPerYear;
        $.discountRateBase = annualDiscountRateBase / Helper.SecondsPerYear;
        emit DiscountChange($.discountRateBase, $.discountRateSlope);
    }

    /// @notice Updates the idle factor parameters
    /// @dev Can only be called by MANAGER_ROLE
    /// @dev Accrues before updating parameters
    /// @dev Emits an IdleFactorChange event with the new values
    /// @param minIdleFactor_ The new minimum idle factor
    /// @param maxIdleFactor_ The new maximum idle factor
    function updateIdleFactor(
        uint64 minIdleFactor_,
        uint64 maxIdleFactor_
    ) external onlyRole(MANAGER_ROLE) {
        _validateIdleFactor(minIdleFactor_, maxIdleFactor_);
        ShareStorage storage $ = _getShareStorage();
        $.minIdleFactor = minIdleFactor_;
        $.maxIdleFactor = maxIdleFactor_;
        emit IdleFactorChange($.minIdleFactor, $.maxIdleFactor);
    }

    function updateVault(
        address vault,
        bool isVault
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        ShareStorage storage $ = _getShareStorage();
        $.isVault[vault] = isVault;
        emit UpdateVault(vault, isVault);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function accrue() public onlyOperatorOrVault {
        _accrue();
    }

    function mint(
        address to,
        uint256 shares,
        uint256 assets
    ) public onlyVault onlyIfAccrued {
        ShareStorage storage $ = _getShareStorage();
        $.assetTotalIdle += assets;
        _mint(to, shares);
    }

    function burn(
        address owner,
        uint256 shares,
        uint256 assets
    ) public onlyVault onlyIfAccrued {
        ShareStorage storage $ = _getShareStorage();
        $.assetTotalIdle -= assets;
        _burn(owner, shares);
    }

    function spendAllowance(
        address owner,
        address spender,
        uint256 shares
    ) public onlyVault onlyIfAccrued {
        _spendAllowance(owner, spender, shares);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override(ERC20Upgradeable, IERC20) returns (bool) {
        if (!_isVault()) return super.transferFrom(from, to, value);
        _transfer(from, to, value);
        return true;
    }

    /// @notice Returns max assets that can be deployed to rwa
    /// @dev Calculates based on the minimum in-vault factor
    /// @return Max assets that can be deployed to rwa
    function maxDeploy() public view returns (uint) {
        ShareStorage storage $ = _getShareStorage();
        uint assetTotal_ = $.assetTotalDeployed + $.assetTotalIdle;
        uint minTotalIdle = Math.mulDiv(
            assetTotal_,
            $.minIdleFactor,
            Helper.FactorScale
        );
        if ($.assetTotalIdle < minTotalIdle) return 0;
        return $.assetTotalIdle - minTotalIdle;
    }

    function deploy(
        uint256 assets,
        bytes calldata data
    ) public onlyVault onlyIfAccrued returns (uint256) {
        uint maxDeploy_ = maxDeploy();
        if (assets == type(uint).max) assets = maxDeploy_;
        if (assets > maxDeploy_) {
            revert ShareInsufficientIdleAssets(assets, maxDeploy_);
        }
        ShareStorage storage $ = _getShareStorage();
        $.assetTotalIdle -= assets;
        $.assetTotalDeployed += assets;
        emit ShareDeployAsset(_msgSender(), assets, data);
        return assets;
    }

    function recall(
        uint256 assets,
        bytes calldata data
    ) public onlyVault onlyIfAccrued returns (uint256) {
        ShareStorage storage $ = _getShareStorage();
        if (assets == type(uint).max) assets = $.assetTotalDeployed;
        if (assets > $.assetTotalDeployed) {
            revert ShareInsufficientDeployedAssets(
                assets,
                $.assetTotalDeployed
            );
        }
        $.assetTotalDeployed -= assets;
        $.assetTotalIdle += assets;
        emit ShareRecallAsset(_msgSender(), assets, data);
        return assets;
    }

    function decimals()
        public
        view
        override(ERC20Upgradeable, IERC20Metadata)
        returns (uint8)
    {
        ShareStorage storage $ = _getShareStorage();
        return $.decimals;
    }

    function assetTotalIdle() public view returns (uint) {
        ShareStorage storage $ = _getShareStorage();
        return $.assetTotalIdle;
    }

    function discountRateBase() public view virtual returns (uint64) {
        ShareStorage storage $ = _getShareStorage();
        return $.discountRateBase;
    }

    function discountRateSlope() public view virtual returns (uint64) {
        ShareStorage storage $ = _getShareStorage();
        return $.discountRateSlope;
    }

    function minIdleFactor() public view virtual returns (uint64) {
        ShareStorage storage $ = _getShareStorage();
        return $.minIdleFactor;
    }

    function maxIdleFactor() public view virtual returns (uint64) {
        ShareStorage storage $ = _getShareStorage();
        return $.maxIdleFactor;
    }

    function lastAccrualTime() public view virtual returns (uint40) {
        ShareStorage storage $ = _getShareStorage();
        return $.lastAccrualTime;
    }

    function time() internal view virtual returns (uint40) {
        if (block.timestamp >= 2 ** 40)
            revert TimestampTooLarge(block.timestamp);
        return uint40(block.timestamp);
    }

    function utilization(
        uint assetTotalIdle_,
        uint assetTotalDeployed_
    ) internal pure returns (uint) {
        uint assetTotalSupplied_ = assetTotalDeployed_ + assetTotalIdle_;
        return
            assetTotalSupplied_ == 0
                ? 0
                : Math.mulDiv(
                    assetTotalDeployed_,
                    Helper.FactorScale,
                    assetTotalSupplied_
                );
    }

    /// @inheritdoc IShare
    function accrueRate(uint utilization_) public view returns (uint) {
        ShareStorage storage $ = _getShareStorage();
        return
            $.discountRateBase +
            Math.mulDiv($.discountRateSlope, utilization_, Helper.FactorScale);
    }

    function accrueDiscount(
        uint timeElapsed,
        uint assetTotalIdle_,
        uint assetTotalDeployed_
    ) internal view returns (uint) {
        uint utilization_ = utilization(assetTotalIdle_, assetTotalDeployed_);
        uint accrueRate_ = accrueRate(utilization_);
        return
            Math.mulDiv(
                assetTotalDeployed_,
                Helper.exp(accrueRate_ * timeElapsed),
                Helper.FactorScale
            );
    }

    function _timeElapsed() internal view returns (uint40, uint) {
        uint40 now_ = time();
        ShareStorage storage $ = _getShareStorage();
        return (now_, now_ - $.lastAccrualTime);
    }

    function _checkAccrued() internal view virtual {
        (, uint timeElapsed_) = _timeElapsed();
        if (timeElapsed_ > 0) {
            revert AccrualOutOfDate(timeElapsed_);
        }
    }

    /**
     * @dev Throws if accrual is not up-to-date.
     */
    modifier onlyIfAccrued() {
        _checkAccrued();
        _;
    }

    function _previewAccrue(
        uint timeElapsed_
    ) internal view returns (uint, uint, uint) {
        ShareStorage storage $ = _getShareStorage();
        uint assetTotalDeployed_ = accrueDiscount(
            timeElapsed_,
            $.assetTotalIdle,
            $.assetTotalDeployed
        );
        return ($.assetTotalDeployed, assetTotalDeployed_, $.assetTotalIdle);
    }

    function previewAccrue() public view returns (uint, uint, uint, uint) {
        (, uint timeElapsed_) = _timeElapsed();
        (
            uint assetTotalDeployedStart,
            uint assetTotalDeployedEnd,
            uint assetTotalIdle_
        ) = _previewAccrue(timeElapsed_);
        return (
            timeElapsed_,
            assetTotalDeployedStart,
            assetTotalDeployedEnd,
            assetTotalIdle_
        );
    }

    function annualAccrueFactor() public view returns (uint) {
        ShareStorage storage $ = _getShareStorage();
        uint utilization_ = utilization($.assetTotalIdle, $.assetTotalDeployed);
        uint accrueRate_ = accrueRate(utilization_);
        return Helper.exp(accrueRate_ * Helper.SecondsPerYear);
    }

    function _accrue() internal {
        (uint40 now_, uint timeElapsed_) = _timeElapsed();
        if (timeElapsed_ == 0) return;
        (
            uint assetTotalDeployedStart,
            uint assetTotalDeployedEnd,
            uint assetTotalIdle_
        ) = _previewAccrue(timeElapsed_);
        ShareStorage storage $ = _getShareStorage();
        $.assetTotalDeployed = assetTotalDeployedEnd;
        $.lastAccrualTime = now_;
        emit Accrue(
            timeElapsed_,
            assetTotalDeployedStart,
            assetTotalDeployedEnd,
            assetTotalIdle_,
            totalSupply()
        );
    }

    function assetTotalDeployed() public view virtual returns (uint) {
        (, , uint assetTotalDeployed_, ) = previewAccrue();
        return assetTotalDeployed_;
    }

    function totalAssets() public view returns (uint) {
        (, , uint assetTotalDeployed_, uint assetTotalIdle_) = previewAccrue();
        return assetTotalDeployed_ + assetTotalIdle_;
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._update(from, to, value);
    }
}
