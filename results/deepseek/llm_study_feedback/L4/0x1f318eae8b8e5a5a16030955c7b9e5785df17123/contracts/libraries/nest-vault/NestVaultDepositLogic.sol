// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  NestVaultDepositLogic
/// @notice Library containing deposit-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultDepositLogic {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when a deposit is made
    /// @param caller   address The caller making the deposit
    /// @param receiver address The receiver of the shares
    /// @param assets   uint256 The assets deposited
    /// @param shares   uint256 The shares minted
    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    /// @dev   Emitted when a fee is accrued
    /// @param feeType  uint8   The fee type
    /// @param receiver address The receiver of the fee
    /// @param amount   uint256 The fee amount
    event FeeAccrued(uint8 feeType, address receiver, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    enum Fees {
        Deposit,
        Withdrawal,
        Performance
    }

    struct Fee {
        uint256 rate;
        uint256 flat;
    }

    struct NestVaultCoreStorage {
        mapping(uint8 => Fee) fees;
        mapping(uint8 => uint256) claimableFees;
        // other storage fields omitted for brevity
    }

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the deposit/enter logic including authorization check
    /// @param  $             NestVaultCoreStorage The full storage struct
    /// @param  _caller       address The caller address
    /// @param  _receiver     address The receiver address
    /// @param  _assets       uint256 Assets to deposit
    /// @param  _shares       uint256 Shares to mint
    /// @param  shareToken    address The share token address
    /// @param  assetToken    address The asset token address
    /// @param  _isAuthorized bool   Whether the caller is authorized
    function executeDeposit(
        NestVaultCoreStorage storage $,
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares,
        address shareToken,
        address assetToken,
        bool _isAuthorized
    ) external {
        // All validation in one call
        validateDeposit($, _isAuthorized, _assets, _shares);

        // Safe transferFrom using low-level call to IERC20
        _safeTransferFrom(IERC20(assetToken), _caller, address(this), _assets);

        // Apply deposit fee (flat + percentage): deduct fee from assets before entering share token
        Fee storage feeConfig = $.fees[uint8(Fees.Deposit)];
        (uint256 _netAssets, uint256 _feeAmount) = calculatePostFeeAmounts(_assets, feeConfig.rate, feeConfig.flat);
        if (_feeAmount > 0) {
            $.claimableFees[uint8(Fees.Deposit)] += _feeAmount;
            emit FeeAccrued(uint8(Fees.Deposit), _receiver, _feeAmount);
        }

        // Safe forceApprove using low-level call to IERC20
        _safeForceApprove(IERC20(assetToken), shareToken, _netAssets);

        // Call enter on share token (assumes shareToken implements enter)
        (bool success, ) = shareToken.call(
            abi.encodeWithSignature(
                "enter(address,uint256,address,uint256)",
                assetToken,
                _netAssets,
                _receiver,
                _shares
            )
        );
        require(success, "NestVaultDepositLogic: enter failed");

        // Reset approval
        _safeForceApprove(IERC20(assetToken), shareToken, 0);

        emit Deposit(_caller, _receiver, _assets, _shares);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function validateDeposit(
        NestVaultCoreStorage storage $,
        bool _isAuthorized,
        uint256 _assets,
        uint256 _shares
    ) internal view {
        require(_isAuthorized, "NestVaultDepositLogic: not authorized");
        require(_assets > 0, "NestVaultDepositLogic: zero assets");
        require(_shares > 0, "NestVaultDepositLogic: zero shares");
    }

    function calculatePostFeeAmounts(
        uint256 _amount,
        uint256 _rate,
        uint256 _flat
    ) internal pure returns (uint256 netAmount, uint256 feeAmount) {
        feeAmount = _flat + (_amount * _rate) / 1e18;
        netAmount = _amount - feeAmount;
    }

    /// @dev Safe transferFrom implementation
    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transferFrom failed");
    }

    /// @dev Safe forceApprove implementation
    function _safeForceApprove(IERC20 token, address spender, uint256 amount) private {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSignature("approve(address,uint256)", spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: approve failed");
    }
}