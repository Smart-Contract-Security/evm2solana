// SPDX-License-Identifier: AGPL-3.0-only

import {NestVaultCoreValidationLogic} from "contracts/libraries/nest-vault/NestVaultCoreValidationLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";

// Solana: Contracts cannot be used as first-class types. Use address instead.
// Structs from NestVaultCoreTypes are inlined here to avoid contract type usage.

/// @notice Fee configuration struct (rate + flat)
struct Fee {
    uint64 rate;
    uint64 flat;
}

/// @notice Enum for fee types
enum Fees {
    DEPOSIT,
    WITHDRAWAL,
    PERFORMANCE,
    MANAGEMENT
}

/// @notice Core storage struct for NestVault
struct NestVaultCoreStorage {
    address operatorRegistry;
    address accountant;
    mapping(uint8 => Fee) fees;
    mapping(uint8 => Fee) maxFees;
    mapping(uint8 => uint64) claimableFees;
    // other fields omitted for brevity, add as needed
}

/// @title  NestVaultAdminLogic
/// @notice Library containing admin-related logic for NestVaultCore
/// @author plumenetwork
library NestVaultAdminLogic {
    using NestVaultCoreValidationLogic for NestVaultCoreStorage;
    // Solana: ERC20 is not available; use address for token accounts.
    // Transfer logic adapted to use address.

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev    Emitted when the fee configuration for a fee type is updated
    /// @param  f      Fees indexed fee type
    /// @param  oldFee Fee    Previous fee configuration
    /// @param  fee    Fee    New fee configuration
    event SetFee(Fees f, Fee oldFee, Fee fee);

    /// @dev    Emitted when the maximum fee cap for a fee type is updated
    /// @param  f         Fees indexed fee type
    /// @param  oldMaxFee Fee    Previous max fee configuration
    /// @param  maxFee    Fee    New max fee configuration
    event SetMaxFee(Fees f, Fee oldMaxFee, Fee maxFee);

    /// @notice Emitted when the operator registry address is updated.
    /// @param oldOperatorRegistry address The previous operator registry address.
    /// @param newOperatorRegistry address The new operator registry address.
    event OperatorRegistryUpdated(address oldOperatorRegistry, address newOperatorRegistry);

    /// @notice Emitted when accountant address is updated.
    /// @param oldAccountant The previous accountant address.
    /// @param newAccountant The new accountant address.
    event SetAccountant(address oldAccountant, address newAccountant);

    /// @notice Emitted when fees are claimed
    /// @param f        Fees The fee type being claimed
    /// @param receiver address The address receiving claimed fees
    /// @param amount   uint64 The amount of fees claimed
    event FeeClaimed(Fees f, address receiver, uint64 amount);

    /*//////////////////////////////////////////////////////////////
                          EXECUTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the operator registry used for global operator approvals
    /// @param  $         NestVaultCoreStorage The full storage struct
    /// @param  _registry address              The operator registry address (zero disables registry)
    function executeSetOperatorRegistry(NestVaultCoreStorage storage $, address _registry) external {
        address oldOperatorRegistry = $.operatorRegistry;
        $.validateOperatorRegistry(_registry);
        $.operatorRegistry = _registry;

        emit OperatorRegistryUpdated(oldOperatorRegistry, _registry);
    }

    /// @notice Executes accountant update with compatibility checks
    /// @dev    Compatibility note:
    ///         - Legacy AccountantWithRateProviders is supported.
    ///         - Global pending-share methods are treated as optional and handled best-effort.
    /// @param  $           NestVaultCoreStorage The full storage struct
    /// @param  _accountant address              Candidate accountant address
    /// @param  _asset      address              Vault asset token address used to probe safe quote rates
    function executeSetAccountant(NestVaultCoreStorage storage $, address _accountant, address _asset)
        external
    {
        $.validateSetAccountant(_accountant, _asset);

        address _oldAccountant = $.accountant;
        $.accountant = _accountant;

        emit SetAccountant(_oldAccountant, _accountant);
    }

    /// @notice Executes fee configuration update for a fee type
    /// @param  $    NestVaultCoreStorage The full storage struct
    /// @param  _f   Fees                 Fee type
    /// @param  _fee Fee                  New fee configuration (rate + flat)
    function executeSetFee(
        NestVaultCoreStorage storage $,
        Fees _f,
        Fee calldata _fee
    ) external {
        $.validateSetFee(_f, _fee);

        Fee memory _oldFee = Fee({rate: $.fees[uint8(_f)].rate, flat: $.fees[uint8(_f)].flat});
        $.fees[uint8(_f)].rate = _fee.rate;
        $.fees[uint8(_f)].flat = _fee.flat;

        emit SetFee(_f, _oldFee, _fee);
    }

    /// @notice Executes max fee configuration update for a fee type
    /// @param  $       NestVaultCoreStorage The full storage struct
    /// @param  _f      Fees                 Fee type
    /// @param  _maxFee Fee                  New max fee configuration (rate + flat)
    function executeSetMaxFee(
        NestVaultCoreStorage storage $,
        Fees _f,
        Fee calldata _maxFee
    ) external {
        $.validateSetMaxFee(_f, _maxFee);

        Fee memory _oldMaxFee =
            Fee({rate: $.maxFees[uint8(_f)].rate, flat: $.maxFees[uint8(_f)].flat});
        $.maxFees[uint8(_f)].rate = _maxFee.rate;
        $.maxFees[uint8(_f)].flat = _maxFee.flat;

        emit SetMaxFee(_f, _oldMaxFee, _maxFee);
    }

    /// @notice Claims accrued fees for a given fee type to a receiver
    /// @param  $          NestVaultCoreStorage The full storage struct
    /// @param  _f         Fees                 Fee type to claim
    /// @param  _receiver  address              The address receiving claimed fees
    /// @param  _assetToken address             Vault asset token address used for payout
    /// @return _feeAmount uint64               The amount of fees claimed
    function executeClaimFee(
        NestVaultCoreStorage storage $,
        Fees _f,
        address _receiver,
        address _assetToken
    ) external returns (uint64 _feeAmount) {
        $.validateClaimFee(_f, _receiver);

        _feeAmount = $.claimableFees[uint8(_f)];
        $.claimableFees[uint8(_f)] = 0;
        // Solana: safeTransferFrom adapted to use address
        NestVaultTransferLogic.safeTransferFrom(_assetToken, address(this), _receiver, _feeAmount);

        emit FeeClaimed(_f, _receiver, _feeAmount);
    }
}