// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseAdapter} from "./BaseAdapter.sol";
import {IPendleAdapter, IPendlePT, IPendleYT, IPendleSY, IPendlePtOracle} from "../interfaces/IPendleAdapter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title PendleAdapter
/// @notice Unified adapter for Pendle Principal Tokens (PT) and Yield Tokens (YT).
///         Single deployment handles all Pendle tokens via per-token config.
contract PendleAdapter is BaseAdapter, Initializable, UUPSUpgradeable, OwnableUpgradeable, IPendleAdapter {
    uint32 public constant MIN_TWAP_DURATION = 900;

    struct PendleConfig {
        Mode mode;
        address market;
        address oracle;
        uint32 twapDuration;
    }

    mapping(address => PendleConfig) public configOf;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ─── Admin ─────────────────────────────────────────────────────────────────

    function setConfig(address token, PendleConfig calldata config) external onlyOwner {
        _setConfig(token, config);
    }

    function setConfigBatch(address[] calldata tokens, PendleConfig[] calldata configs) external onlyOwner {
        if (tokens.length != configs.length) revert LengthMismatch();
        for (uint256 i = 0; i < tokens.length; i++) {
            _setConfig(tokens[i], configs[i]);
        }
    }

    function removeConfig(address token) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        delete configOf[token];
        emit ConfigRemoved(token);
    }

    // ─── Queries ───────────────────────────────────────────────────────────────

    function getExchangeRate(address lsdTokenAddress) external view returns (ExchangeRateInfo memory info) {
        return _getRate(lsdTokenAddress);
    }

    function convertToUnderlying(address lsdTokenAddress, uint256 lsdAmount)
        external
        view
        returns (uint256 underlyingAmount, ExchangeRateInfo memory info)
    {
        info = _getRate(lsdTokenAddress);
        underlyingAmount = (lsdAmount * info.rate) / (10 ** uint256(info.lsdDecimals));
    }

    // ─── Storage gap ────────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Internal ───────────────────────────────────────────────────────────────

    function _setConfig(address token, PendleConfig calldata config) internal {
        if (token == address(0)) revert InvalidAddress();
        if (config.market == address(0)) revert InvalidConfig("Invalid market");
        if (config.oracle == address(0)) revert InvalidConfig("Invalid oracle");
        if (config.twapDuration < MIN_TWAP_DURATION) revert InvalidConfig("TWAP duration too short");
        configOf[token] = config;
        emit ConfigSet(token, config.market, config.oracle, config.twapDuration);
    }

    function _getRate(address lsdTokenAddress) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdTokenAddress);
        PendleConfig memory cfg = configOf[lsdTokenAddress];
        if (cfg.market == address(0)) revert NotConfigured();

        if (cfg.mode == Mode.PT) {
            info = _getPTRate(lsdTokenAddress, cfg);
        } else {
            info = _getYTRate(lsdTokenAddress, cfg);
        }
    }

    function _getPTRate(address lsdTokenAddress, PendleConfig memory cfg)
        internal
        view
        returns (ExchangeRateInfo memory info)
    {
        address sy = IPendlePT(lsdTokenAddress).SY();
        (, address assetAddress, uint8 assetDecimals) = IPendleSY(sy).assetInfo();

        uint256 rawRate;

        if (IPendlePT(lsdTokenAddress).isExpired()) {
            rawRate = IPendleSY(sy).exchangeRate();
        } else {
            rawRate = IPendlePtOracle(cfg.oracle).getPtToAssetRate(cfg.market, cfg.twapDuration);
        }

        uint256 rate = _scaleToUnderlying(rawRate, assetAddress, assetDecimals);

        if (assetAddress == address(0)) {
            info = _buildInfoNative(lsdTokenAddress, rate, _getNativeSymbol());
        } else {
            info = _buildInfoWithUnderlyingToken(lsdTokenAddress, assetAddress, rate);
        }
    }

    function _getYTRate(address lsdTokenAddress, PendleConfig memory cfg)
        internal
        view
        returns (ExchangeRateInfo memory info)
    {
        address sy = IPendleYT(lsdTokenAddress).SY();
        (, address assetAddress, uint8 assetDecimals) = IPendleSY(sy).assetInfo();

        uint256 rawRate = IPendlePtOracle(cfg.oracle).getYtToAssetRate(cfg.market, cfg.twapDuration);
        uint256 rate = _scaleToUnderlying(rawRate, assetAddress, assetDecimals);

        if (assetAddress == address(0)) {
            info = _buildInfoNative(lsdTokenAddress, rate, _getNativeSymbol());
        } else {
            info = _buildInfoWithUnderlyingToken(lsdTokenAddress, assetAddress, rate);
        }
    }

    function _scaleToUnderlying(uint256 rawRate, address assetAddress, uint8 assetDecimals)
        internal
        pure
        returns (uint256)
    {
        uint8 dec;
        if (assetAddress == address(0)) {
            dec = 18;
        } else {
            dec = assetDecimals == 0 ? 18 : assetDecimals;
        }
        if (dec == 18) return rawRate;
        return (rawRate * (10 ** uint256(dec))) / 1e18;
    }
}
