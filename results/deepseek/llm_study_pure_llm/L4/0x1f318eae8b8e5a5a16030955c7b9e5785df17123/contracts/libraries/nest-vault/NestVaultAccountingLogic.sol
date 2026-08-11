// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestShareOFT} from "contracts/NestShareOFT.sol";

/// @title  NestVaultAccountingLogic
/// @notice Library containing common accounting utilities for NestVault operations
/// @dev    View/pure functions for share/asset conversions and fee calculations
/// @author plumenetwork
library NestVaultAccountingLogic {
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;

    /// @notice Converts shares to assets using the provided rate
    /// @param  _shares   uint256 The shares to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _share    NestShareOFT Share token used to derive decimals
    /// @param  _rounding uint8 The rounding direction (0=Floor, 1=Ceil, 2=Expand)
    /// @return _assets   uint256 The calculated assets
    function convertToAssets(uint256 _shares, uint256 _rate, NestShareOFT _share, uint8 _rounding)
        internal
        pure
        returns (uint256 _assets)
    {
        _assets = mulDiv(_shares, _rate, oneShare(_share), _rounding);
    }

    /// @notice Converts assets to shares using the provided rate
    /// @param  _assets   uint256 The assets to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _share    NestShareOFT Share token used to derive decimals
    /// @param  _rounding uint8 The rounding direction (0=Floor, 1=Ceil, 2=Expand)
    /// @return _shares   uint256 The calculated shares
    function convertToShares(uint256 _assets, uint256 _rate, NestShareOFT _share, uint8 _rounding)
        internal
        pure
        returns (uint256 _shares)
    {
        _shares = mulDiv(_assets, oneShare(_share), _rate, _rounding);
    }

    /// @notice Calculates combined flat + percentage fee amount from assets
    /// @param  _assets  uint256 The asset amount
    /// @param  _feeRate uint32  The percentage fee rate (denominated in 1e6)
    /// @param  _flatFee uint256 The flat fee in asset token units
    /// @return _fee     uint256 The total fee amount, capped at _assets
    function calculateFee(uint256 _assets, uint32 _feeRate, uint256 _flatFee) internal pure returns (uint256 _fee) {
        if (_flatFee >= _assets) return _assets;
        _fee = _flatFee;
        if (_feeRate != 0) {
            _fee += mulDiv(_assets, uint256(_feeRate), FEE_DENOMINATOR, 0);
        }
        if (_fee > _assets) _fee = _assets;
    }

    /// @notice Calculates post-fee amount and combined flat + percentage fee from assets
    /// @param  _assets        uint256 The asset amount
    /// @param  _feeRate       uint32  The percentage fee rate (denominated in 1e6)
    /// @param  _flatFee       uint256 The flat fee in asset token units
    /// @return _postFeeAmount uint256 The amount after fees
    /// @return _feeAmount     uint256 The total fee amount
    function calculatePostFeeAmounts(uint256 _assets, uint32 _feeRate, uint256 _flatFee)
        internal
        pure
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        if (_feeRate == 0 && _flatFee == 0) return (_assets, 0);
        _feeAmount = calculateFee(_assets, _feeRate, _flatFee);
        _postFeeAmount = _assets - _feeAmount;
    }

    /// @notice Calculates the minimum gross asset amount needed to realize a target post-fee amount
    ///         under combined flat + percentage fees
    /// @dev    Solves `gross - flatFee - floor(gross * feeRate / 1e6) >= postFeeAmount` for the smallest integer `gross`.
    /// @param  _postFeeAmount uint256 Target amount after fees
    /// @param  _feeRate       uint32  The percentage fee rate (denominated in 1e6)
    /// @param  _flatFee       uint256 The flat fee in asset token units
    /// @return _grossAmount   uint256 The minimum gross amount that satisfies the target post-fee amount
    function calculatePreFeeAmount(uint256 _postFeeAmount, uint32 _feeRate, uint256 _flatFee)
        internal
        pure
        returns (uint256 _grossAmount)
    {
        if (_postFeeAmount == 0) return 0;

        uint256 _target = _postFeeAmount + _flatFee;

        if (_feeRate == 0) return _target;

        uint256 _postFeeDenominator = FEE_DENOMINATOR - uint256(_feeRate);
        _grossAmount = mulDiv(_target - 1, FEE_DENOMINATOR, _postFeeDenominator, 0) + 1;
    }

    /// @notice Returns the scaling factor for one share based on its decimals
    /// @param  _share NestShareOFT Share token used to derive decimals
    /// @return uint256 The scaling factor representing one share
    function oneShare(NestShareOFT _share) internal pure returns (uint256) {
        return 10 ** _share.decimals();
    }

    /// @notice Internal mulDiv with rounding support
    /// @param  a         uint256 Numerator
    /// @param  b         uint256 Multiplier
    /// @param  denominator uint256 Denominator
    /// @param  rounding  uint8 0=Floor, 1=Ceil, 2=Expand
    /// @return result    uint256
    function mulDiv(uint256 a, uint256 b, uint256 denominator, uint8 rounding) internal pure returns (uint256 result) {
        // Floor division
        result = (a * b) / denominator;

        if (rounding == 1) {
            // Ceil: if there is any remainder, add 1
            if ((a * b) % denominator != 0) {
                result += 1;
            }
        } else if (rounding == 2) {
            // Expand: round away from zero (same as Ceil for positive numbers)
            if ((a * b) % denominator != 0) {
                result += 1;
            }
        }
        // Floor (0) is default, no adjustment needed
    }
}