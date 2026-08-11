// SPDX-License-Identifier: AGPL-3.0-only

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Errors} from "contracts/types/Errors.sol";

library NestVaultTransferLogic {
    using SafeTransferLib for address;

    function safeTransferFrom(address token, address _owner, address _receiver, uint64 _amount)
        external
        returns (uint64 _amountReceived)
    {
        if (_owner == _receiver) return _amount;

        uint64 _balanceBefore = token.balanceOf(_receiver);
        if (_owner == address(this)) {
            token.safeTransfer(_receiver, _amount);
        } else {
            token.safeTransferFrom(_owner, _receiver, _amount);
        }
        uint64 _balanceAfter = token.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _amount) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }

    function safePermit2TransferFrom(
        address token,
        address permit2,
        address _owner,
        address _receiver,
        uint64 _amount,
        uint64 _nonce,
        uint64 _deadline,
        bytes memory _signature
    ) external returns (uint64 _amountReceived) {
        uint64 _balanceBefore = token.balanceOf(_receiver);
        permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: _amount}),
                nonce: _nonce,
                deadline: _deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({to: _receiver, requestedAmount: _amount}),
            _owner,
            _signature
        );
        uint64 _balanceAfter = token.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _amount) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }

    function safeEnter(address shareToken, address assetToken, uint64 _assets, address _receiver, uint64 _shares)
        external
    {
        uint64 _balanceBefore = shareToken.balanceOf(_receiver);
        shareToken.enter(address(this), assetToken, _assets, _receiver, _shares);
        uint64 _balanceAfter = shareToken.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _shares) revert Errors.TransferInsufficient();
    }

    function safeExit(address shareToken, address assetToken, address _receiver, uint64 _assets, uint64 _shares)
        external
        returns (uint64 _amountReceived)
    {
        uint64 _balanceBefore = assetToken.balanceOf(_receiver);
        shareToken.exit(_receiver, assetToken, _assets, address(this), _shares);
        uint64 _balanceAfter = assetToken.balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _assets) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }
}