// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import "../interfaces/IJudgmentOracleAdapter.sol";

/// @notice Derived Pyth adapter for ACE v1/v2 BTC/ETH judgment rounds.
contract PythDerivedJudgmentOracleAdapter is IJudgmentOracleAdapter {
    using Math for uint256;

    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MAX_DECIMAL_EXPONENT = 77;

    IPyth public immutable pyth;
    bytes32 public immutable btcUsdPriceId;
    bytes32 public immutable ethUsdPriceId;
    uint256 public immutable maxPriceAge;
    uint16 public immutable maxConfidenceBps;

    error InvalidAddress();
    error InvalidPriceFeed();
    error InvalidMaxPriceAge();
    error InvalidConfidenceBps();
    error UnexpectedUpdateFee();
    error InvalidPythPrice();
    error InvalidPythExponent();
    error PythConfidenceTooWide();

    constructor(
        address pyth_,
        bytes32 btcUsdPriceId_,
        bytes32 ethUsdPriceId_,
        uint256 maxPriceAge_,
        uint16 maxConfidenceBps_
    ) {
        if (pyth_ == address(0)) {
            revert InvalidAddress();
        }
        if (
            btcUsdPriceId_ == bytes32(0) || ethUsdPriceId_ == bytes32(0)
                || btcUsdPriceId_ == ethUsdPriceId_
        ) {
            revert InvalidPriceFeed();
        }
        if (maxPriceAge_ == 0) {
            revert InvalidMaxPriceAge();
        }
        if (maxConfidenceBps_ == 0 || maxConfidenceBps_ > BPS_DENOMINATOR) {
            revert InvalidConfidenceBps();
        }

        pyth = IPyth(pyth_);
        btcUsdPriceId = btcUsdPriceId_;
        ethUsdPriceId = ethUsdPriceId_;
        maxPriceAge = maxPriceAge_;
        maxConfidenceBps = maxConfidenceBps_;
    }

    function getRoundStartPrices(bytes[] calldata priceUpdateData)
        external
        payable
        override
        returns (uint256 marketPriceWad, uint256 ethUsdPriceWad)
    {
        _updatePyth(priceUpdateData);

        (uint256 btcUsdPriceWad, uint256 btcConfidenceBps) = _readPriceWad(btcUsdPriceId);
        uint256 ethConfidenceBps;
        (ethUsdPriceWad, ethConfidenceBps) = _readPriceWad(ethUsdPriceId);
        _validateDerivedConfidence(btcConfidenceBps, ethConfidenceBps);
        marketPriceWad = _deriveBtcEthPrice(btcUsdPriceWad, ethUsdPriceWad);
    }

    function getRoundSettlementPrice(bytes[] calldata priceUpdateData)
        external
        payable
        override
        returns (uint256 marketPriceWad)
    {
        _updatePyth(priceUpdateData);

        (uint256 btcUsdPriceWad, uint256 btcConfidenceBps) = _readPriceWad(btcUsdPriceId);
        (uint256 ethUsdPriceWad, uint256 ethConfidenceBps) = _readPriceWad(ethUsdPriceId);
        _validateDerivedConfidence(btcConfidenceBps, ethConfidenceBps);
        marketPriceWad = _deriveBtcEthPrice(btcUsdPriceWad, ethUsdPriceWad);
    }

    function getUpdateFee(bytes[] calldata priceUpdateData) external view override returns (uint256) {
        return pyth.getUpdateFee(priceUpdateData);
    }

    function _updatePyth(bytes[] calldata priceUpdateData) private {
        uint256 updateFee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value != updateFee) {
            revert UnexpectedUpdateFee();
        }
        if (priceUpdateData.length != 0) {
            pyth.updatePriceFeeds{value: updateFee}(priceUpdateData);
        }
    }

    function _readPriceWad(bytes32 priceId) private view returns (uint256 priceWad, uint256 confidenceBps) {
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, maxPriceAge);
        priceWad = _toWad(price.price, price.expo);
        if (priceWad == 0) {
            revert InvalidPythPrice();
        }

        confidenceBps = uint256(price.conf).mulDiv(BPS_DENOMINATOR, uint256(uint64(price.price)));
    }

    function _validateDerivedConfidence(uint256 btcConfidenceBps, uint256 ethConfidenceBps) private view {
        // BTC/ETH is derived as BTC/USD divided by ETH/USD; use additive relative confidence as a conservative bound.
        if (btcConfidenceBps + ethConfidenceBps > maxConfidenceBps) {
            revert PythConfidenceTooWide();
        }
    }

    function _deriveBtcEthPrice(uint256 btcUsdPriceWad, uint256 ethUsdPriceWad) private pure returns (uint256) {
        uint256 derivedPriceWad = btcUsdPriceWad.mulDiv(WAD, ethUsdPriceWad);
        if (derivedPriceWad == 0) {
            revert InvalidPythPrice();
        }
        return derivedPriceWad;
    }

    function _toWad(int64 value, int32 expo) private pure returns (uint256) {
        if (value <= 0) {
            revert InvalidPythPrice();
        }

        return _scaleToWad(uint256(uint64(value)), expo);
    }

    function _scaleToWad(uint256 value, int32 expo) private pure returns (uint256) {
        if (value == 0) {
            return 0;
        }

        if (expo >= 0) {
            uint256 positiveExpo = uint256(uint32(expo));
            if (positiveExpo > MAX_DECIMAL_EXPONENT) {
                revert InvalidPythExponent();
            }
            return value * _pow10(positiveExpo) * WAD;
        }

        uint256 decimals = uint256(-int256(expo));
        if (decimals <= 18) {
            return value * _pow10(18 - decimals);
        }

        return value / _pow10(decimals - 18);
    }

    function _pow10(uint256 exponent) private pure returns (uint256) {
        if (exponent > MAX_DECIMAL_EXPONENT) {
            revert InvalidPythExponent();
        }

        return 10 ** exponent;
    }
}
