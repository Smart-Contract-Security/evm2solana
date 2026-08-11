// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import "../interfaces/IJudgmentOracleAdapter.sol";

/// @notice Single-feed Pyth adapter for ETH/USD judgment rounds.
contract PythEthUsdJudgmentOracleAdapter is IJudgmentOracleAdapter {
    using Math for uint256;

    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MAX_DECIMAL_EXPONENT = 77;

    IPyth public immutable pyth;
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
        bytes32 ethUsdPriceId_,
        uint256 maxPriceAge_,
        uint16 maxConfidenceBps_
    ) {
        if (pyth_ == address(0)) {
            revert InvalidAddress();
        }
        if (ethUsdPriceId_ == bytes32(0)) {
            revert InvalidPriceFeed();
        }
        if (maxPriceAge_ == 0) {
            revert InvalidMaxPriceAge();
        }
        if (maxConfidenceBps_ == 0 || maxConfidenceBps_ > BPS_DENOMINATOR) {
            revert InvalidConfidenceBps();
        }

        pyth = IPyth(pyth_);
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

        ethUsdPriceWad = _readPriceWad(ethUsdPriceId);
        marketPriceWad = ethUsdPriceWad;
    }

    function getRoundSettlementPrice(bytes[] calldata priceUpdateData)
        external
        payable
        override
        returns (uint256 marketPriceWad)
    {
        _updatePyth(priceUpdateData);

        marketPriceWad = _readPriceWad(ethUsdPriceId);
    }

    function getRoundSettlementPriceAt(
        bytes[] calldata priceUpdateData,
        uint64 minPublishTime,
        uint64 maxPublishTime
    )
        external
        payable
        override
        returns (IJudgmentOracleAdapter.OracleSnapshot memory snapshot)
    {
        PythStructs.PriceFeed[] memory feeds = _parsePriceFeedsAt(
            priceUpdateData,
            _singlePriceIdArray(ethUsdPriceId),
            minPublishTime,
            maxPublishTime
        );
        (uint256 ethUsdPriceWad, uint256 confidenceBps) = _priceWadAndConfidence(
            feeds[0].price
        );
        if (confidenceBps > maxConfidenceBps) {
            revert PythConfidenceTooWide();
        }

        uint64 publishTime = uint64(feeds[0].price.publishTime);
        snapshot = IJudgmentOracleAdapter.OracleSnapshot({
            marketPriceWad: ethUsdPriceWad,
            ethUsdPriceWad: ethUsdPriceWad,
            marketPublishTime: publishTime,
            ethUsdPublishTime: publishTime,
            marketPriceId: ethUsdPriceId,
            ethUsdPriceId: ethUsdPriceId,
            dataId: _oracleDataId(
                ethUsdPriceId,
                publishTime,
                ethUsdPriceWad,
                ethUsdPriceId,
                publishTime,
                ethUsdPriceWad
            )
        });
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

    function _parsePriceFeedsAt(
        bytes[] calldata priceUpdateData,
        bytes32[] memory priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) private returns (PythStructs.PriceFeed[] memory feeds) {
        uint256 updateFee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value != updateFee) {
            revert UnexpectedUpdateFee();
        }

        feeds = pyth.parsePriceFeedUpdatesUnique{value: updateFee}(
            priceUpdateData,
            priceIds,
            minPublishTime,
            maxPublishTime
        );
    }

    function _readPriceWad(bytes32 priceId) private view returns (uint256) {
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, maxPriceAge);
        (uint256 priceWad, uint256 confidenceBps) = _priceWadAndConfidence(price);
        if (confidenceBps > maxConfidenceBps) {
            revert PythConfidenceTooWide();
        }

        return priceWad;
    }

    function _priceWadAndConfidence(
        PythStructs.Price memory price
    ) private pure returns (uint256 priceWad, uint256 confidenceBps) {
        if (price.price <= 0) {
            revert InvalidPythPrice();
        }

        uint256 rawPrice = uint256(uint64(price.price));
        priceWad = _scaleToWad(rawPrice, price.expo);
        if (priceWad == 0) {
            revert InvalidPythPrice();
        }

        confidenceBps = uint256(price.conf).mulDiv(
            BPS_DENOMINATOR,
            rawPrice
        );
    }

    function _singlePriceIdArray(
        bytes32 priceId
    ) private pure returns (bytes32[] memory priceIds) {
        priceIds = new bytes32[](1);
        priceIds[0] = priceId;
    }

    function _oracleDataId(
        bytes32 marketPriceId,
        uint64 marketPublishTime,
        uint256 marketPriceWad,
        bytes32 ethUsdPriceId_,
        uint64 ethUsdPublishTime,
        uint256 ethUsdPriceWad
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    "ACE_PYTH_ORACLE_SNAPSHOT_V1",
                    marketPriceId,
                    marketPublishTime,
                    marketPriceWad,
                    ethUsdPriceId_,
                    ethUsdPublishTime,
                    ethUsdPriceWad
                )
            );
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
