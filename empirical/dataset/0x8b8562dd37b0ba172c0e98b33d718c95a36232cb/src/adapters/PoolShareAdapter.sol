// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseAdapter} from "./BaseAdapter.sol";
import {IPoolShareAdapter} from "../interfaces/IPoolShareAdapter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title PoolShareAdapter
/// @notice Adapter for tokens where rate = call_A / call_B (e.g., totalPooledBNB / totalSupply)
contract PoolShareAdapter is BaseAdapter, Initializable, UUPSUpgradeable, OwnableUpgradeable, IPoolShareAdapter {
    struct RatioConfig {
        address numeratorTarget;
        bytes numeratorCallData;
        address denominatorTarget;
        bytes denominatorCallData;
        uint256 outputScale;
        address underlying;
        bool isNative;
    }

    mapping(address => RatioConfig) public configOf;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setConfig(address token, RatioConfig calldata config) external onlyOwner {
        _setConfig(token, config);
    }

    function setConfigBatch(address[] calldata tokens, RatioConfig[] calldata configs) external onlyOwner {
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

    function getExchangeRate(address lsdToken) external view returns (ExchangeRateInfo memory info) {
        return _getRate(lsdToken);
    }

    function convertToUnderlying(address lsdToken, uint256 lsdAmount)
        external
        view
        returns (uint256 underlyingAmount, ExchangeRateInfo memory info)
    {
        info = _getRate(lsdToken);
        underlyingAmount = (lsdAmount * info.rate) / (10 ** uint256(info.lsdDecimals));
    }

    // ─── Storage gap ────────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Internal ───────────────────────────────────────────────────────────────

    function _setConfig(address token, RatioConfig calldata config) internal {
        if (token == address(0)) revert InvalidAddress();
        if (config.numeratorTarget == address(0)) revert InvalidConfig("Invalid numerator target");
        if (config.denominatorTarget == address(0)) revert InvalidConfig("Invalid denominator target");
        if (config.numeratorCallData.length < 4) revert InvalidConfig("Numerator calldata too short");
        if (config.denominatorCallData.length < 4) revert InvalidConfig("Denominator calldata too short");
        if (config.outputScale == 0) revert InvalidConfig("Output scale cannot be zero");
        if (config.isNative) {
            if (config.underlying != address(0)) revert InvalidConfig("Native must have zero underlying");
        } else {
            if (config.underlying == address(0)) revert InvalidConfig("Invalid underlying");
        }
        configOf[token] = config;
        emit ConfigSet(token, config.numeratorTarget, config.denominatorTarget);
    }

    function _getRate(address lsdToken) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdToken);
        RatioConfig memory cfg = configOf[lsdToken];
        if (cfg.numeratorTarget == address(0)) revert NotConfigured();

        uint256 num = _staticCallUint256(cfg.numeratorTarget, cfg.numeratorCallData);
        uint256 den = _staticCallUint256(cfg.denominatorTarget, cfg.denominatorCallData);
        if (den == 0) revert CallFailed();

        uint256 rate = (num * cfg.outputScale) / den;

        if (cfg.isNative) {
            return _buildInfoNative(lsdToken, rate, _getNativeSymbol());
        } else {
            return _buildInfoWithUnderlyingToken(lsdToken, cfg.underlying, rate);
        }
    }
}
