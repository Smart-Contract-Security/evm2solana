// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseAdapter} from "./BaseAdapter.sol";
import {IERC4626Adapter} from "../interfaces/IERC4626Adapter.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title ERC4626Adapter
/// @notice Generic LSD adapter for ERC-4626 vault tokens
contract ERC4626Adapter is BaseAdapter, Initializable, UUPSUpgradeable, OwnableUpgradeable, IERC4626Adapter {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getExchangeRate(address lsdTokenAddress) external view returns (ExchangeRateInfo memory info) {
        info = _buildInfo4626(lsdTokenAddress);
    }

    function convertToUnderlying(address lsdTokenAddress, uint256 lsdAmount)
        external
        view
        returns (uint256 underlyingAmount, ExchangeRateInfo memory info)
    {
        info = _buildInfo4626(lsdTokenAddress);
        IERC4626 vault = IERC4626(lsdTokenAddress);
        underlyingAmount = vault.convertToAssets(lsdAmount);
    }

    // ─── Storage gap ──────────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Internal ─────────────────────────────────────────────────────────────────

    function _buildInfo4626(address lsdTokenAddress) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdTokenAddress);

        IERC4626 vault = IERC4626(lsdTokenAddress);
        address asset = vault.asset();
        if (asset == address(0)) revert InvalidConfig("ERC4626: zero asset");

        uint8 lsdDecimals = _safeDecimals(lsdTokenAddress);
        uint256 oneShare = 10 ** uint256(lsdDecimals);
        uint256 assetsPerShare = vault.convertToAssets(oneShare);

        info = _buildInfoWithUnderlyingToken(lsdTokenAddress, asset, assetsPerShare);
    }
}
