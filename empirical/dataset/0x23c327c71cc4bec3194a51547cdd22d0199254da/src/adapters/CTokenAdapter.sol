// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseAdapter} from "./BaseAdapter.sol";
import {ICTokenAdapter, IVToken} from "../interfaces/ICTokenAdapter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title CTokenAdapter
/// @notice Adapter for Venus/Compound-style vTokens (e.g. vUSDC, vBNB)
contract CTokenAdapter is BaseAdapter, Initializable, UUPSUpgradeable, OwnableUpgradeable, ICTokenAdapter {
    uint256 private constant EXCHANGE_RATE_SCALE = 1e18;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

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

    // ─── Storage gap ──────────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Internal ─────────────────────────────────────────────────────────────────

    function _getRate(address lsdTokenAddress) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdTokenAddress);

        IVToken vToken = IVToken(lsdTokenAddress);
        uint256 exchangeRate = vToken.exchangeRateStored();

        uint8 lsdDecimals = _safeDecimals(lsdTokenAddress);
        uint256 oneVToken = 10 ** uint256(lsdDecimals);
        uint256 rate = (exchangeRate * oneVToken) / EXCHANGE_RATE_SCALE;

        address underlyingAsset = address(0);
        bool hasUnderlying;
        try vToken.underlying() returns (address u) {
            underlyingAsset = u;
            hasUnderlying = true;
        } catch {
            hasUnderlying = false;
        }

        if (hasUnderlying && underlyingAsset != address(0)) {
            info = _buildInfoWithUnderlyingToken(lsdTokenAddress, underlyingAsset, rate);
        } else {
            info = _buildInfoNative(lsdTokenAddress, rate, _getNativeSymbol());
        }
    }
}
