// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "@uniswap/permit2/interfaces/ISignatureTransfer.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {Errors} from "contracts/types/Errors.sol";

library NestVaultTransferLogic {
    using SafeTransferLib for address;

    function safeTransferFrom(address token, address _owner, address _receiver, uint256 _amount)
        external
        returns (uint256 _amountReceived)
    {
        if (_owner == _receiver) return _amount;

        uint256 _balanceBefore = ERC20(token).balanceOf(_receiver);
        if (_owner == address(this)) {
            SafeTransferLib.safeTransfer(token, _receiver, _amount);
        } else {
            SafeTransferLib.safeTransferFrom(token, _owner, _receiver, _amount);
        }
        uint256 _balanceAfter = ERC20(token).balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _amount) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }

    function safePermit2TransferFrom(
        address token,
        address permit2,
        address _owner,
        address _receiver,
        uint256 _amount,
        uint256 _nonce,
        uint256 _deadline,
        bytes memory _signature
    ) external returns (uint256 _amountReceived) {
        uint256 _balanceBefore = ERC20(token).balanceOf(_receiver);
        ISignatureTransfer(permit2).permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: _amount}),
                nonce: _nonce,
                deadline: _deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({to: _receiver, requestedAmount: _amount}),
            _owner,
            _signature
        );
        uint256 _balanceAfter = ERC20(token).balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _amount) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }

    function safeEnter(address shareToken, address assetToken, uint256 _assets, address _receiver, uint256 _shares)
        external
    {
        uint256 _balanceBefore = NestShareOFT(shareToken).balanceOf(_receiver);
        NestShareOFT(shareToken).enter(address(this), assetToken, _assets, _receiver, _shares);
        uint256 _balanceAfter = NestShareOFT(shareToken).balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _shares) revert Errors.TransferInsufficient();
    }

    function safeExit(address shareToken, address assetToken, address _receiver, uint256 _assets, uint256 _shares)
        external
        returns (uint256 _amountReceived)
    {
        uint256 _balanceBefore = ERC20(assetToken).balanceOf(_receiver);
        NestShareOFT(shareToken).exit(_receiver, assetToken, _assets, address(this), _shares);
        uint256 _balanceAfter = ERC20(assetToken).balanceOf(_receiver);

        if (_balanceAfter < _balanceBefore + _assets) revert Errors.TransferInsufficient();
        _amountReceived = _balanceAfter - _balanceBefore;
    }
}