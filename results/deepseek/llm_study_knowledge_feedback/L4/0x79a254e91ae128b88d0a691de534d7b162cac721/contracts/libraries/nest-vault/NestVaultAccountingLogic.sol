// SPDX-License-Identifier: AGPL-3.0-only

/// @title  NestVaultAccountingLogic
/// @notice Library containing common accounting utilities for NestVault operations
/// @dev    View/pure functions for share/asset conversions and fee calculations
/// @author plumenetwork
library NestVaultAccountingLogic {
    uint64 internal constant FEE_DENOMINATOR = 1_000_000;

    /// @notice Converts shares to assets using the provided rate
    /// @param  _shares   uint64 The shares to convert
    /// @param  _rate     uint64 The exchange rate
    /// @param  _shareDecimals uint8 Decimals of the share token
    /// @param  _rounding Math.Rounding The rounding direction
    /// @return _assets   uint64 The calculated assets
    function convertToAssets(uint64 _shares, uint64 _rate, uint8 _shareDecimals, Math.Rounding _rounding)
        internal
        pure
        returns (uint64 _assets)
    {
        _assets = Math.mulDiv(_shares, _rate, oneShare(_shareDecimals), _rounding);
    }

    /// @notice Converts assets to shares using the provided rate
    /// @param  _assets   uint64 The assets to convert
    /// @param  _rate     uint64 The exchange rate
    /// @param  _shareDecimals uint8 Decimals of the share token
    /// @param  _rounding Math.Rounding The rounding direction
    /// @return _shares   uint64 The calculated shares
    function convertToShares(uint64 _assets, uint64 _rate, uint8 _shareDecimals, Math.Rounding _rounding)
        internal
        pure
        returns (uint64 _shares)
    {
        _shares = Math.mulDiv(_assets, oneShare(_shareDecimals), _rate, _rounding);
    }

    /// @notice Calculates combined flat + percentage fee amount from assets
    /// @param  _assets  uint64 The asset amount
    /// @param  _feeRate uint32 The percentage fee rate (denominated in 1e6)
    /// @param  _flatFee uint64 The flat fee in asset token units
    /// @return _fee     uint64 The total fee amount, capped at _assets
    function calculateFee(uint64 _assets, uint32 _feeRate, uint64 _flatFee) internal pure returns (uint64 _fee) {
        if (_flatFee >= _assets) return _assets;
        _fee = _flatFee;
        if (_feeRate != 0) {
            _fee += Math.mulDiv(_assets, uint64(_feeRate), FEE_DENOMINATOR, Math.Rounding.Floor);
        }
        if (_fee > _assets) _fee = _assets;
    }

    /// @notice Calculates post-fee amount and combined flat + percentage fee from assets
    /// @param  _assets        uint64 The asset amount
    /// @param  _feeRate       uint32 The percentage fee rate (denominated in 1e6)
    /// @param  _flatFee       uint64 The flat fee in asset token units
    /// @return _postFeeAmount uint64 The amount after fees
    /// @return _feeAmount     uint64 The total fee amount
    function calculatePostFeeAmounts(uint64 _assets, uint32 _feeRate, uint64 _flatFee)
        internal
        pure
        returns (uint64 _postFeeAmount, uint64 _feeAmount)
    {
        if (_feeRate == 0 && _flatFee == 0) return (_assets, 0);
        _feeAmount = calculateFee(_assets, _feeRate, _flatFee);
        _postFeeAmount = _assets - _feeAmount;
    }

    /// @notice Calculates the minimum gross asset amount needed to realize a target post-fee amount
    ///         under combined flat + percentage fees
    /// @dev    Solves `gross - flatFee - floor(gross * feeRate / 1e6) >= postFeeAmount` for the smallest integer `gross`.
    /// @param  _postFeeAmount uint64 Target amount after fees
    /// @param  _feeRate       uint32 The percentage fee rate (denominated in 1e6)
    /// @param  _flatFee       uint64 The flat fee in asset token units
    /// @return _grossAmount   uint64 The minimum gross amount that satisfies the target post-fee amount
    function calculatePreFeeAmount(uint64 _postFeeAmount, uint32 _feeRate, uint64 _flatFee)
        internal
        pure
        returns (uint64 _grossAmount)
    {
        if (_postFeeAmount == 0) return 0;

        uint64 _target = _postFeeAmount + _flatFee;

        if (_feeRate == 0) return _target;

        uint64 _postFeeDenominator = FEE_DENOMINATOR - uint64(_feeRate);
        _grossAmount = Math.mulDiv(_target - 1, FEE_DENOMINATOR, _postFeeDenominator, Math.Rounding.Ceil) + 1;
    }

    /// @notice Returns the scaling factor for one share based on its decimals
    /// @param  _shareDecimals uint8 Decimals of the share token
    /// @return uint64 The scaling factor representing one share
    function oneShare(uint8 _shareDecimals) internal pure returns (uint64) {
        return uint64(10 ** _shareDecimals);
    }
}

/// @notice Math library with mulDiv and Rounding enum
library Math {
    enum Rounding { Floor, Ceil }

    function mulDiv(uint64 a, uint64 b, uint64 denominator, Rounding rounding) internal pure returns (uint64 result) {
        if (denominator == 0) {
            revert();
        }
        uint128 prod = uint128(a) * uint128(b);
        result = uint64(prod / uint128(denominator));
        if (rounding == Rounding.Ceil && prod % uint128(denominator) != 0) {
            result += 1;
        }
    }
}