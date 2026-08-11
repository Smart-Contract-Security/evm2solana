// SPDX-License-Identifier: AGPL-3.0-only

import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultAccountingLogic} from "contracts/libraries/nest-vault/NestVaultAccountingLogic.sol";
import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";

/// @title  NestVaultDepositLogic
/// @notice Library containing deposit-related logic for NestVaultCore
/// @author plumenetwork
/// @custom:oz-upgrades-unsafe-allow external-library-linking
library NestVaultDepositLogic {
    using NestVaultAccountingLogic for uint64;
    using NestVaultCoreValidationLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultTransferLogic for address;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev   Emitted when a deposit is made
    /// @param caller   address The caller making the deposit
    /// @param receiver address The receiver of the shares
    /// @param assets   uint64 The assets deposited
    /// @param shares   uint64 The shares minted
    event Deposit(address caller, address receiver, uint64 assets, uint64 shares);

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the deposit/enter logic including authorization check
    /// @param  $             NestVaultCoreTypes.NestVaultCoreStorage The full storage struct
    /// @param  _caller       address The caller address
    /// @param  _receiver     address The receiver address
    /// @param  _assets       uint64 Assets to deposit
    /// @param  _shares       uint64 Shares to mint
    /// @param  shareToken    address The share token program address
    /// @param  _isAuthorized bool         Whether the caller is authorized
    function executeDeposit(
        NestVaultCoreTypes.NestVaultCoreStorage storage $,
        address _caller,
        address _receiver,
        uint64 _assets,
        uint64 _shares,
        address shareToken,
        bool _isAuthorized
    ) external {
        // All validation in one call
        $.validateDeposit(_isAuthorized, _assets, _shares);

        // Transfer assets from caller to this program's data account
        // The asset token transfer is handled via the share token's enter function
        // which internally handles the token transfer

        // Apply deposit fee (flat + percentage): deduct fee from assets before entering share token
        NestVaultCoreTypes.Fee storage feeConfig = $.fees[NestVaultCoreTypes.Fees.Deposit];
        (uint64 _netAssets, uint64 _feeAmount) = _assets.calculatePostFeeAmounts(feeConfig.rate, feeConfig.flat);
        if (_feeAmount > 0) {
            $.claimableFees[NestVaultCoreTypes.Fees.Deposit] += _feeAmount;
            emit NestVaultCoreTypes.FeeAccrued(uint8(NestVaultCoreTypes.Fees.Deposit), _receiver, _feeAmount);
        }

        shareToken.safeEnter(_netAssets, _receiver, _shares);

        emit Deposit(_caller, _receiver, _assets, _shares);
    }
}