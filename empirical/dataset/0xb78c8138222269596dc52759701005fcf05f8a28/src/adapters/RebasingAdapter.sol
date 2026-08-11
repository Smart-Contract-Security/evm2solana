// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseAdapter} from "./BaseAdapter.sol";
import {IRebasingAdapter} from "../interfaces/IRebasingAdapter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title RebasingAdapter
/// @notice Adapter for 1:1 rebasing tokens (stETH, eETH, OETH, aTokens, stFLIP, lsDAI, etc.)
contract RebasingAdapter is BaseAdapter, Initializable, UUPSUpgradeable, OwnableUpgradeable, IRebasingAdapter {
    struct RebasingConfig {
        address underlying; // address(0) = native
        bool isNative;
    }

    mapping(address => RebasingConfig) public configOf;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setConfig(address token, address underlying, bool isNative) external onlyOwner {
        _setConfig(token, underlying, isNative);
    }

    function setConfigBatch(
        address[] calldata tokens,
        address[] calldata underlyings,
        bool[] calldata isNatives
    ) external onlyOwner {
        if (tokens.length != underlyings.length || tokens.length != isNatives.length) revert LengthMismatch();
        for (uint256 i = 0; i < tokens.length; i++) {
            _setConfig(tokens[i], underlyings[i], isNatives[i]);
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
        underlyingAmount = lsdAmount;
    }

    // ─── Storage gap ────────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Internal ───────────────────────────────────────────────────────────────

    function _setConfig(address token, address underlying, bool isNative) internal {
        if (token == address(0)) revert InvalidAddress();
        if (isNative) {
            if (underlying != address(0)) revert InvalidConfig("Native must have zero underlying");
            if (_safeDecimals(token) != 18) revert InvalidConfig("Native rebasing must be 18 dec");
        } else {
            if (underlying == address(0)) revert InvalidConfig("Invalid underlying");
            if (_safeDecimals(token) != _safeDecimals(underlying)) revert InvalidConfig("Decimals mismatch");
        }
        configOf[token] = RebasingConfig({underlying: underlying, isNative: isNative});
        emit ConfigSet(token, underlying, isNative);
    }

    function _getRate(address lsdToken) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdToken);
        RebasingConfig memory cfg = configOf[lsdToken];
        if (cfg.underlying == address(0) && !cfg.isNative) revert NotConfigured();

        uint256 rate = 10 ** uint256(_safeDecimals(lsdToken));
        if (cfg.isNative) {
            return _buildInfoNative(lsdToken, rate, _getNativeSymbol());
        } else {
            return _buildInfoWithUnderlyingToken(lsdToken, cfg.underlying, rate);
        }
    }
}
