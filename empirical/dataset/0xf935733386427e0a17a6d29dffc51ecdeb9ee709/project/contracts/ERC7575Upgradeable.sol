// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (token/ERC20/extensions/ERC7575.sol)

pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC7575} from "./interfaces/IERC7575.sol";
import {IShare} from "./interfaces/IShare.sol";
import {ERC7575Store} from "./ERC7575Store.sol";
import {Helper} from "./Helper.sol";

/**
 * @title ERC7575Upgradeable
 * @author Sivo
 * @dev Implementation of the ERC-7575 "Multi-Asset Tokenized Vault Standard" as defined in
 * https://eips.ethereum.org/EIPS/eip-7575[ERC-7575].
 * @dev From @openzeppelin/contracts-upgradeable/ERC4626Upgradeable.sol, minus ERC-20
 */
abstract contract ERC7575Upgradeable is
    ContextUpgradeable,
    ERC165Upgradeable,
    ERC7575Store,
    IERC7575
{
    using Math for uint256;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, IERC165) returns (bool) {
        return
            interfaceId == type(IERC7575).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _share() internal view virtual returns (IShare) {
        ERC7575Storage storage $ = _getERC7575Storage();
        return IShare($._share);
    }

    function _asset() internal view virtual returns (IERC20) {
        ERC7575Storage storage $ = _getERC7575Storage();
        return IERC20($._asset);
    }

    /** @dev See {IERC7575-share}. */
    function share() public view virtual returns (address) {
        ERC7575Storage storage $ = _getERC7575Storage();
        return address($._share);
    }

    /** @dev See {IERC7575-asset}. */
    function asset() public view virtual returns (address) {
        ERC7575Storage storage $ = _getERC7575Storage();
        return address($._asset);
    }

    /** @dev See {IERC7575-totalAssets}. */
    function totalAssets() public view virtual returns (uint256) {
        IShare share_ = _share();
        return share_.assetTotalDeployed() + share_.assetTotalIdle();
    }

    /** @dev See {IERC7575-convertToShares}. */
    function convertToShares(
        uint256 assets
    ) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /** @dev See {IERC7575-convertToAssets}. */
    function convertToAssets(
        uint256 shares
    ) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /** @dev See {IERC7575-maxDeposit}. */
    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC7575-maxMint}. */
    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC7575-maxWithdraw}. */
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        uint assets = _convertToAssets(
            _share().balanceOf(owner),
            Math.Rounding.Floor
        );
        return _toNet(assets);
    }

    /** @dev See {IERC7575-maxRedeem}. */
    function maxRedeem(address owner) public view virtual returns (uint256) {
        return _share().balanceOf(owner);
    }

    /** @dev See {IERC7575-previewDeposit}. */
    function previewDeposit(
        uint256 assets
    ) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /** @dev See {IERC7575-previewMint}. */
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    function _previewWithdraw(
        uint256 assets
    ) internal view returns (uint256 shares, uint256 fees) {
        uint256 gross = _toGross(assets);
        fees = gross - assets;
        shares = _convertToShares(gross, Math.Rounding.Ceil);
    }

    function _previewRedeem(
        uint256 shares
    ) internal view returns (uint256 assets, uint256 fees) {
        uint256 gross = _convertToAssets(shares, Math.Rounding.Floor);
        assets = _toNet(gross);
        fees = gross - assets;
    }

    /** @dev See {IERC7575-previewWithdraw}. */
    function previewWithdraw(
        uint256 assets
    ) public view virtual returns (uint256) {
        (uint256 shares, ) = _previewWithdraw(assets);
        return shares;
    }

    /** @dev See {IERC7575-previewRedeem}. */
    function previewRedeem(
        uint256 shares
    ) public view virtual returns (uint256) {
        (uint256 assets, ) = _previewRedeem(shares);
        return assets;
    }

    /** @dev See {IERC7575-deposit}. */
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC7575ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /** @dev See {IERC7575-mint}. */
    function mint(
        uint256 shares,
        address receiver
    ) public virtual returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC7575ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC7575-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC7575ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        (uint256 shares, uint256 fees) = _previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares, fees);
        return shares;
    }

    /** @dev See {IERC7575-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC7575ExceededMaxRedeem(owner, shares, maxShares);
        }

        (uint256 assets, uint256 fees) = _previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares, fees);
        return assets;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        return
            assets.mulDiv(
                _share().totalSupply() + 10 ** _decimalsOffset(),
                totalAssets() + 1,
                rounding
            );
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        return
            shares.mulDiv(
                totalAssets() + 1,
                _share().totalSupply() + 10 ** _decimalsOffset(),
                rounding
            );
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets_,
        uint256 shares
    ) internal virtual {
        // If asset() is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        uint256 balance_ = _asset().balanceOf(address(this));
        SafeERC20.safeTransferFrom(_asset(), caller, address(this), assets_);
        uint256 assets = _asset().balanceOf(address(this)) - balance_;
        if (assets < assets_)
            revert ERC7575InsufficientTransfer(assets_, assets);
        if (shares == 0) revert ERC7575ExceededMaxDeposit(receiver, assets, 0);
        _share().mint(receiver, shares, assets);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 fees
    ) internal virtual {
        IShare share_ = _share();
        if (caller != owner) {
            share_.spendAllowance(owner, caller, shares);
        }

        // If asset() is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        share_.burn(owner, shares, assets + fees);
        if (fees != 0) {
            _getERC7575Storage()._accumulatedFees += fees;
            emit InstantRedeemFee(owner, assets, fees);
        }
        SafeERC20.safeTransfer(_asset(), receiver, assets);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Returns the total accumulated instant redeem fees not yet claimed
    function accumulatedFees() public view returns (uint) {
        return _getERC7575Storage()._accumulatedFees;
    }

    function _toNet(uint gross) internal view returns (uint) {
        uint64 net_ = Helper.FactorScale - _redeemFee();
        return Math.mulDiv(gross, net_, Helper.FactorScale);
    }

    function _toGross(uint net) internal view returns (uint) {
        uint64 net_ = Helper.FactorScale - _redeemFee();
        return Math.mulDiv(net, Helper.FactorScale, net_, Math.Rounding.Ceil);
    }

    function _redeemFee() internal view virtual returns (uint64) {
        return 0;
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        ERC7575Storage storage $ = _getERC7575Storage();
        return IShare($._share).decimals() - $._assetDecimals;
    }
}
