// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC7540Deposit, IERC7540Redeem, IERC7540Operator} from "./interfaces/IERC7540.sol";
import {ERC7575Upgradeable} from "./ERC7575Upgradeable.sol";

/**
 * @title ERC7540Upgradeable
 * @author Sivo
 * @dev Implementation of the ERC-7540 "Asynchronous ERC-4626 Tokenized Vaults" as defined in
 * https://eips.ethereum.org/EIPS/eip-7540[ERC-7540].
 */
abstract contract ERC7540Upgradeable is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    ERC7575Upgradeable,
    IERC7540Deposit,
    IERC7540Redeem,
    IERC7540Operator
{
    using Math for uint256;

    struct Claimable {
        uint256 assets;
        uint256 shares;
    }

    /// @custom:storage-location erc7201:sivo.storage.ERC7540
    struct ERC7540Storage {
        mapping(address controller => mapping(address operator => bool)) _isOperator;
        mapping(address => uint256) _pendingDeposit;
        uint256 _totalPendingDeposit;
        mapping(address => Claimable) _claimableDeposit;
        Claimable _totalClaimableDeposit;
        mapping(address => uint256) _pendingRedeem;
        uint256 _totalPendingRedeem;
        mapping(address => Claimable) _claimableRedeem;
        Claimable _totalClaimableRedeem;
    }

    // keccak256(abi.encode(uint256(keccak256("sivo.storage.ERC7540")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC7540StorageLocation =
        0xf5d2f41a999c1144bf8aecf5f175bd2b2374bdc6361a14b1c4bce35d5759aa00;

    function _getERC7540Storage()
        internal
        pure
        returns (ERC7540Storage storage $)
    {
        assembly {
            $.slot := ERC7540StorageLocation
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, ERC7575Upgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC7540Deposit).interfaceId ||
            interfaceId == type(IERC7540Redeem).interfaceId ||
            interfaceId == type(IERC7540Operator).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function isOperator(
        address controller,
        address operator
    ) external view returns (bool status) {
        ERC7540Storage storage $ = _getERC7540Storage();
        return $._isOperator[controller][operator];
    }

    function setOperator(
        address operator,
        bool approved
    ) external returns (bool success) {
        ERC7540Storage storage $ = _getERC7540Storage();
        $._isOperator[_msgSender()][operator] = approved;
        emit OperatorSet(_msgSender(), operator, approved);
        return true;
    }

    modifier onlyOperator(address subject) {
        _checkOperator(subject);
        _;
    }

    function _checkOperator(address subject) internal view virtual {
        if (subject == _msgSender()) return;
        ERC7540Storage storage $ = _getERC7540Storage();
        if ($._isOperator[subject][_msgSender()]) return;
        revert ERC7540UnauthorizedSender(_msgSender(), subject);
    }

    function requestDeposit(
        uint256 assets_,
        address controller,
        address owner
    ) external onlyOperator(owner) returns (uint256 requestId) {
        requestId = 0;
        ERC7540Storage storage $ = _getERC7540Storage();
        uint256 balance_ = _asset().balanceOf(address(this));
        SafeERC20.safeTransferFrom(_asset(), owner, address(this), assets_);
        uint256 assets = _asset().balanceOf(address(this)) - balance_;
        $._pendingDeposit[controller] += assets;
        $._totalPendingDeposit += assets;
        emit DepositRequest(controller, owner, requestId, _msgSender(), assets);
    }

    function cancelDeposit(
        uint256 assets,
        address receiver,
        address controller
    ) external onlyOperator(controller) {
        ERC7540Storage storage $ = _getERC7540Storage();
        $._pendingDeposit[controller] -= assets;
        $._totalPendingDeposit -= assets;
        SafeERC20.safeTransfer(_asset(), receiver, assets);
        emit DepositCancel(controller, receiver, _msgSender(), assets);
    }

    function pendingDepositRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 assets) {
        if (requestId != 0) return 0;
        ERC7540Storage storage $ = _getERC7540Storage();
        return $._pendingDeposit[controller];
    }

    function _claimableDeposit(
        uint256 assets,
        address controller
    ) internal returns (uint256 shares) {
        ERC7540Storage storage $ = _getERC7540Storage();
        $._pendingDeposit[controller] -= assets;
        $._totalPendingDeposit -= assets;
        shares = previewDeposit(assets);
        _share().mint(address(this), shares, assets);
        $._claimableDeposit[controller].assets += assets;
        $._totalClaimableDeposit.assets += assets;
        $._claimableDeposit[controller].shares += shares;
        $._totalClaimableDeposit.shares += shares;
        emit DepositClaimable(controller, assets, shares);
    }

    function claimableDepositRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 assets) {
        if (requestId != 0) return 0;
        ERC7540Storage storage $ = _getERC7540Storage();
        return $._claimableDeposit[controller].assets;
    }

    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) external onlyOperator(controller) returns (uint256 shares) {
        ERC7540Storage storage $ = _getERC7540Storage();
        Claimable storage $$ = $._claimableDeposit[controller];
        shares = $$.shares.mulDiv(assets, $$.assets);
        $$.assets -= assets;
        $._totalClaimableDeposit.assets -= assets;
        $$.shares -= shares;
        $._totalClaimableDeposit.shares -= shares;
        SafeERC20.safeTransfer(_share(), receiver, shares);
        emit Deposit(controller, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver,
        address controller
    ) external onlyOperator(controller) returns (uint256 assets) {
        ERC7540Storage storage $ = _getERC7540Storage();
        Claimable storage $$ = $._claimableDeposit[controller];
        assets = $$.assets.mulDiv(shares, $$.shares);
        $$.shares -= shares;
        $._totalClaimableDeposit.shares -= shares;
        $$.assets -= assets;
        $._totalClaimableDeposit.assets -= assets;
        SafeERC20.safeTransfer(_share(), receiver, shares);
        emit Deposit(controller, receiver, assets, shares);
    }

    function requestRedeem(
        uint256 shares_,
        address controller,
        address owner
    ) external onlyOperator(owner) returns (uint256 requestId) {
        requestId = 0;
        ERC7540Storage storage $ = _getERC7540Storage();
        uint256 balance_ = _share().balanceOf(address(this));
        SafeERC20.safeTransferFrom(_share(), owner, address(this), shares_);
        uint256 shares = _share().balanceOf(address(this)) - balance_;
        $._pendingRedeem[controller] += shares;
        $._totalPendingRedeem += shares;
        emit RedeemRequest(controller, owner, requestId, _msgSender(), shares);
    }

    function cancelRedeem(
        uint256 shares,
        address receiver,
        address controller
    ) external onlyOperator(controller) {
        ERC7540Storage storage $ = _getERC7540Storage();
        $._pendingRedeem[controller] -= shares;
        $._totalPendingRedeem -= shares;
        SafeERC20.safeTransfer(_share(), receiver, shares);
        emit RedeemCancel(controller, receiver, _msgSender(), shares);
    }

    function pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 shares) {
        if (requestId != 0) return 0;
        ERC7540Storage storage $ = _getERC7540Storage();
        return $._pendingRedeem[controller];
    }

    function _claimableRedeem(
        uint256 shares,
        address controller
    ) internal returns (uint256 assets) {
        ERC7540Storage storage $ = _getERC7540Storage();
        $._pendingRedeem[controller] -= shares;
        $._totalPendingRedeem -= shares;
        assets = _convertToAssets(shares, Math.Rounding.Floor);
        _share().burn(address(this), shares, assets);
        $._claimableRedeem[controller].assets += assets;
        $._totalClaimableRedeem.assets += assets;
        $._claimableRedeem[controller].shares += shares;
        $._totalClaimableRedeem.shares += shares;
        emit RedeemClaimable(controller, assets, shares);
    }

    function claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 shares) {
        if (requestId != 0) return 0;
        ERC7540Storage storage $ = _getERC7540Storage();
        return $._claimableRedeem[controller].shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    )
        public
        virtual
        override
        onlyOperator(controller)
        returns (uint256 shares)
    {
        ERC7540Storage storage $ = _getERC7540Storage();
        Claimable storage $$ = $._claimableRedeem[controller];
        if ($$.assets == 0) return super.withdraw(assets, receiver, controller);
        shares = $$.shares.mulDiv(assets, $$.assets);
        $$.assets -= assets;
        $._totalClaimableRedeem.assets -= assets;
        $$.shares -= shares;
        $._totalClaimableRedeem.shares -= shares;
        SafeERC20.safeTransfer(_asset(), receiver, assets);
        emit Withdraw(_msgSender(), receiver, controller, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    )
        public
        virtual
        override
        onlyOperator(controller)
        returns (uint256 assets)
    {
        ERC7540Storage storage $ = _getERC7540Storage();
        Claimable storage $$ = $._claimableRedeem[controller];
        if ($$.shares == 0) return super.redeem(shares, receiver, controller);
        assets = $$.assets.mulDiv(shares, $$.shares);
        $$.shares -= shares;
        $._totalClaimableRedeem.shares -= shares;
        $$.assets -= assets;
        $._totalClaimableRedeem.assets -= assets;
        SafeERC20.safeTransfer(_asset(), receiver, assets);
        emit Withdraw(_msgSender(), receiver, controller, assets, shares);
    }
}
