// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

/// @title  NestVaultAccountingLogic
/// @notice Library containing common accounting utilities for NestVault operations
/// @dev    View/pure functions for share/asset conversions and fee calculations
/// @author plumenetwork
library NestVaultAccountingLogic {
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;

    enum Rounding {
        Floor,
        Ceil,
        Trunc,
        Expand
    }

    /// @notice Converts shares to assets using the provided rate
    /// @param  _shares   uint256 The shares to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _shareDecimals uint8 Decimals of the share token
    /// @param  _rounding Rounding The rounding direction
    /// @return _assets   uint256 The calculated assets
    function convertToAssets(uint256 _shares, uint256 _rate, uint8 _shareDecimals, Rounding _rounding)
        internal
        pure
        returns (uint256 _assets)
    {
        _assets = mulDiv(_shares, _rate, oneShare(_shareDecimals), _rounding);
    }

    /// @notice Converts assets to shares using the provided rate
    /// @param  _assets   uint256 The assets to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _shareDecimals uint8 Decimals of the share token
    /// @param  _rounding Rounding The rounding direction
    /// @return _shares   uint256 The calculated shares
    function convertToShares(uint256 _assets, uint256 _rate, uint8 _shareDecimals, Rounding _rounding)
        internal
        pure
        returns (uint256 _shares)
    {
        _shares = mulDiv(_assets, oneShare(_shareDecimals), _rate, _rounding);
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
            _fee += mulDiv(_assets, uint256(_feeRate), FEE_DENOMINATOR, Rounding.Floor);
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
        _grossAmount = mulDiv(_target - 1, FEE_DENOMINATOR, _postFeeDenominator, Rounding.Ceil) + 1;
    }

    /// @notice Returns the scaling factor for one share based on its decimals
    /// @param  _shareDecimals uint8 Decimals of the share token
    /// @return uint256 The scaling factor representing one share
    function oneShare(uint8 _shareDecimals) internal pure returns (uint256) {
        return 10 ** _shareDecimals;
    }

    /// @dev Reimplementation of OpenZeppelin's Math.mulDiv with rounding
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256 result) {
        if (denominator == 0) {
            revert("division by zero");
        }

        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            result = prod0 / denominator;
            if (rounding == Rounding.Ceil && mulmod(x, y, denominator) > 0) {
                result += 1;
            } else if (rounding == Rounding.Floor) {
                // already floored by integer division
            } else if (rounding == Rounding.Trunc) {
                // already truncated
            } else if (rounding == Rounding.Expand) {
                if (mulmod(x, y, denominator) > 0) {
                    result += 1;
                }
            }
            return result;
        }

        if (prod1 >= denominator) {
            revert("overflow");
        }

        uint256 remainder;
        assembly {
            remainder := mulmod(x, y, denominator)
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        unchecked {
            uint256 lpotdod = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, lpotdod)
                prod0 := div(prod0, lpotdod)
                lpotdod := add(div(sub(0, lpotdod), lpotdod), 1)
            }
            prod0 |= prod1 * lpotdod;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            if (rounding == Rounding.Ceil && remainder > 0) {
                result += 1;
            } else if (rounding == Rounding.Floor) {
                // already floored
            } else if (rounding == Rounding.Trunc) {
                // already truncated
            } else if (rounding == Rounding.Expand) {
                if (remainder > 0) {
                    result += 1;
                }
            }
        }
    }
}