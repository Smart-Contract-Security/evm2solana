// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestShareOFT} from "contracts/NestShareOFT.sol";

/// @title  NestVaultAccountingLogic
/// @notice Library containing common accounting utilities for NestVault operations
/// @dev    View/pure functions for share/asset conversions and fee calculations
/// @author plumenetwork
library NestVaultAccountingLogic {
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;

    enum Rounding { Floor, Ceil, Trunc, Expand }

    /// @notice Converts shares to assets using the provided rate
    /// @param  _shares   uint256 The shares to convert
    /// @param  _rate     uint256 The exchange rate
    /// @param  _share    NestShareOFT Share token used to derive decimals
    /// @param  _rounding Rounding The rounding direction
    /// @return _assets   uint256 The calculated assets
    function convertToAssets(uint256 _shares, uint256 _rate, NestShareOFT _share, Rounding _rounding)
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
    /// @param  _rounding Rounding The rounding direction
    /// @return _shares   uint256 The calculated shares
    function convertToShares(uint256 _assets, uint256 _rate, NestShareOFT _share, Rounding _rounding)
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
    /// @param  _share NestShareOFT Share token used to derive decimals
    /// @return uint256 The scaling factor representing one share
    function oneShare(NestShareOFT _share) internal pure returns (uint256) {
        return 10 ** _share.decimals();
    }

    /// @dev Reimplementation of OpenZeppelin's Math.mulDiv with rounding
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256 result) {
        // Handle zero denominator
        require(denominator > 0, "Math: division by zero");

        // Compute the product mod 2**256 and mod 2**256 - 1, then use the Chinese Remainder Theorem
        // to reconstruct the 512-bit result. The result is stored in two 256-bit variables.
        // This is a port of the Solidity implementation from OpenZeppelin.
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            if (rounding == Rounding.Floor) {
                return prod0 / denominator;
            } else if (rounding == Rounding.Ceil) {
                return prod0 / denominator + (prod0 % denominator > 0 ? 1 : 0);
            } else if (rounding == Rounding.Trunc) {
                return prod0 / denominator;
            } else { // Expand
                return prod0 / denominator + (prod0 % denominator > 0 ? 1 : 0);
            }
        }

        // Make sure the result is less than 2**256.
        require(denominator > prod1, "Math: mulDiv overflow");

        uint256 remainder;
        assembly {
            remainder := mulmod(x, y, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
        // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.
        uint256 twos = denominator & (~denominator + 1);
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256. Now that denominator is an odd number, it has an inverse modulo 2**256 such
        // that denominator * inv = 1 mod 2**256. Compute the inverse by starting with a seed that is correct for
        // four bits. That is, denominator * inv = 1 mod 2**4.
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
        // in modular arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
        // This will give us the correct result modulo 2**256. Since the preconditions guarantee that the outcome is
        // less than 2**256, this is the final result. We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;

        if (rounding == Rounding.Ceil || rounding == Rounding.Expand) {
            if (mulmod(x, y, denominator) > 0) {
                result += 1;
            }
        }
    }
}