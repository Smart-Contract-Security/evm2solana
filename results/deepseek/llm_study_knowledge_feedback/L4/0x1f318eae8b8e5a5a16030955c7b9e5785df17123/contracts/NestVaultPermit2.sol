// SPDX-License-Identifier: AGPL-3.0-only

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";
import {Errors} from "contracts/types/Errors.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {NestVaultRedeemLogic} from "contracts/libraries/nest-vault/NestVaultRedeemLogic.sol";
import {NestVaultTransferLogic} from "contracts/libraries/nest-vault/NestVaultTransferLogic.sol";

abstract contract NestVaultPermit2 {
    using NestVaultRedeemLogic for NestVaultCoreTypes.NestVaultCoreStorage;
    using NestVaultTransferLogic for ERC20;

    address public immutable PERMIT2;
    address public immutable SHARE;

    constructor(address _share, address _permit2) {
        if (_permit2 == address(0)) {
            revert("ZeroAddress");
        }

        PERMIT2 = _permit2;
        SHARE = _share;
    }

    function requestRedeemWithPermit2(
        uint64 _shares,
        address _controller,
        address _owner,
        uint64 _nonce,
        uint64 _deadline,
        bytes calldata _signature
    ) external virtual returns (uint64 _requestId) {
        uint64 _sharesReceived = ERC20(SHARE)
            .safePermit2TransferFrom(PERMIT2, _owner, address(this), _shares, _nonce, _deadline, _signature);

        _requestId = _getNestVaultCoreStorage()
            .executeRequestRedeem(_sharesReceived, _controller, _owner, msg.sender, ERC20(SHARE));
    }

    function instantRedeemWithPermit2(
        uint64 _shares,
        address _receiver,
        address _owner,
        uint64 _nonce,
        uint64 _deadline,
        bytes calldata _signature
    ) external virtual returns (uint64 _postFeeAmount, uint64 _feeAmount) {
        uint64 _sharesReceived = ERC20(SHARE)
            .safePermit2TransferFrom(PERMIT2, _owner, address(this), _shares, _nonce, _deadline, _signature);

        (_postFeeAmount, _feeAmount) = _getNestVaultCoreStorage()
            .executeInstantRedeem(
                _sharesReceived, _receiver, _owner, msg.sender, SHARE, ERC20(asset()), _getValidatedRate()
            );
    }

    function _getNestVaultCoreStorage() internal virtual returns (NestVaultCoreTypes.NestVaultCoreStorage storage);
    function asset() internal virtual returns (address);
    function _getValidatedRate() internal virtual returns (uint64);
}