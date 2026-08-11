// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ILSDAdapter} from "./interfaces/ILSDAdapter.sol";
import {ILSDExchangeRateRouter} from "./interfaces/ILSDExchangeRateRouter.sol";
import {ERC4626Adapter} from "./adapters/ERC4626Adapter.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @title LSDExchangeRateRouter
/// @notice Registry + unified view router for LSD adapters (UUPS upgradeable).
///         Supports two pause levels:
///           - Global pause (`pause()` / `unpause()`): blocks ALL rate queries.
///           - Per-adapter pause (`pauseAdapter()` / `unpauseAdapter()`): blocks
///             rate queries that route through one specific adapter address,
///             leaving other adapters operational.
contract LSDExchangeRateRouter is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ILSDExchangeRateRouter
{
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private registeredLSDs;
    mapping(address => address) public lsdToAdapter;
    EnumerableSet.AddressSet private registeredAdapters;

    ERC4626Adapter public erc4626Adapter;

    /// @notice Per-adapter pause flags. Owner-only.
    mapping(address => bool) private _adapterPaused;

    /// @notice Reference count: how many LSD tokens point to each adapter.
    mapping(address => uint256) private _adapterRefCount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address erc4626Adapter_) public initializer {
        require(owner_ != address(0), ErrorsLib.INVALID_ADDRESS);
        require(erc4626Adapter_ != address(0), ErrorsLib.INVALID_ADDRESS);
        __Ownable_init(owner_);
        __Pausable_init();
        erc4626Adapter = ERC4626Adapter(erc4626Adapter_);
    }

    // -------- Admin --------

    function registerAdapter(address lsdToken, address adapter) external onlyOwner {
        require(lsdToken != address(0) && adapter != address(0), ErrorsLib.INVALID_ADDRESS);
        if (registeredLSDs.contains(lsdToken)) {
            address old = lsdToAdapter[lsdToken];
            lsdToAdapter[lsdToken] = adapter;
            if (old != adapter) {
                if (--_adapterRefCount[old] == 0) registeredAdapters.remove(old);
                registeredAdapters.add(adapter);
                _adapterRefCount[adapter]++;
            }
        } else {
            registeredLSDs.add(lsdToken);
            lsdToAdapter[lsdToken] = adapter;
            registeredAdapters.add(adapter);
            _adapterRefCount[adapter]++;
        }
        emit EventsLib.AdapterRegistered(lsdToken, adapter);
    }

    function registerAdapterBatch(address[] calldata lsdTokens, address adapter) external onlyOwner {
        require(adapter != address(0), ErrorsLib.INVALID_ADDRESS);
        for (uint256 i = 0; i < lsdTokens.length; i++) {
            address t = lsdTokens[i];
            require(t != address(0), ErrorsLib.INVALID_ADDRESS);
            if (registeredLSDs.contains(t)) {
                address old = lsdToAdapter[t];
                lsdToAdapter[t] = adapter;
                if (old != adapter) {
                    if (--_adapterRefCount[old] == 0) registeredAdapters.remove(old);
                    registeredAdapters.add(adapter);
                    _adapterRefCount[adapter]++;
                }
            } else {
                registeredLSDs.add(t);
                lsdToAdapter[t] = adapter;
                registeredAdapters.add(adapter);
                _adapterRefCount[adapter]++;
            }
            emit EventsLib.AdapterRegistered(t, adapter);
        }
    }

    function updateAdapter(address lsdToken, address newAdapter) external onlyOwner {
        require(registeredLSDs.contains(lsdToken), ErrorsLib.LSD_NOT_REGISTERED);
        require(newAdapter != address(0), ErrorsLib.INVALID_ADDRESS);
        address oldAdapter = lsdToAdapter[lsdToken];
        lsdToAdapter[lsdToken] = newAdapter;
        registeredAdapters.add(newAdapter);
        _adapterRefCount[newAdapter]++;

        if (--_adapterRefCount[oldAdapter] == 0) {
            registeredAdapters.remove(oldAdapter);
        }

        emit EventsLib.AdapterRegistered(lsdToken, newAdapter);
    }

    /// @notice Migrate many tokens to the same new adapter in one transaction.
    function updateAdapterBatch(address[] calldata lsdTokens, address newAdapter) external onlyOwner {
        require(newAdapter != address(0), ErrorsLib.INVALID_ADDRESS);
        require(lsdTokens.length > 0, ErrorsLib.LENGTH_MISMATCH);

        for (uint256 i = 0; i < lsdTokens.length; i++) {
            address t = lsdTokens[i];
            require(registeredLSDs.contains(t), ErrorsLib.LSD_NOT_REGISTERED);
            address old = lsdToAdapter[t];
            lsdToAdapter[t] = newAdapter;

            _adapterRefCount[old]--;
            if (_adapterRefCount[old] == 0) {
                registeredAdapters.remove(old);
            }

            emit EventsLib.AdapterRegistered(t, newAdapter);
        }
        registeredAdapters.add(newAdapter);
        _adapterRefCount[newAdapter] += lsdTokens.length;
    }

    function removeAdapter(address lsdToken) external onlyOwner {
        require(registeredLSDs.contains(lsdToken), ErrorsLib.LSD_NOT_REGISTERED);
        address adapter = lsdToAdapter[lsdToken];

        registeredLSDs.remove(lsdToken);
        delete lsdToAdapter[lsdToken];

        if (--_adapterRefCount[adapter] == 0) {
            registeredAdapters.remove(adapter);
        }

        emit EventsLib.AdapterRemoved(lsdToken, adapter);
    }

    // -------- Pause control --------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Pause queries that route through this specific adapter address.
    ///         Other adapters keep working. Useful when one adapter category has
    ///         a known issue but the rest of the registry is healthy.
    function pauseAdapter(address adapter) external onlyOwner {
        require(adapter != address(0), ErrorsLib.INVALID_ADDRESS);
        require(!_adapterPaused[adapter], ErrorsLib.ALREADY_SET);
        _adapterPaused[adapter] = true;
        emit EventsLib.AdapterPaused(adapter);
    }

    function unpauseAdapter(address adapter) external onlyOwner {
        require(_adapterPaused[adapter], ErrorsLib.ALREADY_SET);
        _adapterPaused[adapter] = false;
        emit EventsLib.AdapterUnpaused(adapter);
    }

    function isAdapterPaused(address adapter) external view returns (bool) {
        return _adapterPaused[adapter];
    }

    // -------- View: registry --------

    function getAdapter(address lsdToken) external view returns (address) {
        address adapter = lsdToAdapter[lsdToken];
        require(adapter != address(0), ErrorsLib.LSD_NOT_REGISTERED);
        return adapter;
    }

    function isLSDRegistered(address lsdToken) external view returns (bool) {
        return registeredLSDs.contains(lsdToken);
    }

    function getAdapterCount() external view returns (uint256) {
        return registeredLSDs.length();
    }

    function getUniqueAdapterCount() external view returns (uint256) {
        return registeredAdapters.length();
    }

    function getAllRegisteredLSDs() external view returns (address[] memory) {
        return registeredLSDs.values();
    }

    function getAllAdapters() external view returns (address[] memory) {
        return registeredAdapters.values();
    }

    function getRegisteredLSDsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory lsdTokens, uint256 total)
    {
        total = registeredLSDs.length();
        if (offset >= total) return (new address[](0), total);
        uint256 end = (limit == 0 || offset + limit > total) ? total : offset + limit;
        uint256 count = end - offset;
        lsdTokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            lsdTokens[i] = registeredLSDs.at(offset + i);
        }
    }

    // -------- View: single hop --------

    function getExchangeRate(address lsdToken)
        external
        view
        whenNotPaused
        returns (ILSDAdapter.ExchangeRateInfo memory)
    {
        return _getRate(lsdToken);
    }

    function convertToUnderlying(address lsdToken, uint256 lsdAmount)
        external
        view
        whenNotPaused
        returns (uint256 underlyingAmount, ILSDAdapter.ExchangeRateInfo memory info)
    {
        return _convert(lsdToken, lsdAmount);
    }

    // -------- View: recursive --------

    function getExchangeRateRecursive(address lsdToken)
        external
        view
        whenNotPaused
        returns (ILSDAdapter.ExchangeRateInfo memory)
    {
        return _getRateRecursive(lsdToken, new address[](0));
    }

    function convertToUnderlyingRecursive(address lsdToken, uint256 lsdAmount)
        external
        view
        whenNotPaused
        returns (uint256 underlyingAmount, ILSDAdapter.ExchangeRateInfo memory info)
    {
        return _convertRecursive(lsdToken, lsdAmount, new address[](0));
    }

    // -------- View: batch --------

    function batchGetExchangeRates(address[] calldata lsdTokens)
        external
        view
        whenNotPaused
        returns (BatchResult[] memory results)
    {
        results = new BatchResult[](lsdTokens.length);
        for (uint256 i = 0; i < lsdTokens.length; i++) {
            results[i].lsdToken = lsdTokens[i];
            try this.getExchangeRate(lsdTokens[i]) returns (ILSDAdapter.ExchangeRateInfo memory info) {
                results[i].success = true;
                results[i].info = info;
            } catch Error(string memory reason) {
                results[i].errorMessage = reason;
            } catch {
                results[i].errorMessage = "Unknown error";
            }
        }
    }

    function batchConvertToUnderlying(address[] calldata lsdTokens, uint256[] calldata amounts)
        external
        view
        whenNotPaused
        returns (uint256[] memory underlyingAmounts, BatchResult[] memory results)
    {
        require(lsdTokens.length == amounts.length, ErrorsLib.LENGTH_MISMATCH);
        underlyingAmounts = new uint256[](lsdTokens.length);
        results = new BatchResult[](lsdTokens.length);
        for (uint256 i = 0; i < lsdTokens.length; i++) {
            results[i].lsdToken = lsdTokens[i];
            try this.convertToUnderlying(lsdTokens[i], amounts[i]) returns (
                uint256 amountOut, ILSDAdapter.ExchangeRateInfo memory info
            ) {
                results[i].success = true;
                results[i].info = info;
                underlyingAmounts[i] = amountOut;
            } catch Error(string memory reason) {
                results[i].errorMessage = reason;
            } catch {
                results[i].errorMessage = "Unknown error";
            }
        }
    }

    // -------- Internal --------

    function _getRate(address lsdToken) internal view returns (ILSDAdapter.ExchangeRateInfo memory) {
        address adapter = lsdToAdapter[lsdToken];
        if (adapter != address(0)) {
            require(!_adapterPaused[adapter], ErrorsLib.ADAPTER_DISABLED);
            return ILSDAdapter(adapter).getExchangeRate(lsdToken);
        }
        require(!_adapterPaused[address(erc4626Adapter)], ErrorsLib.ADAPTER_DISABLED);
        return erc4626Adapter.getExchangeRate(lsdToken);
    }

    function _convert(address lsdToken, uint256 amount)
        internal
        view
        returns (uint256, ILSDAdapter.ExchangeRateInfo memory)
    {
        address adapter = lsdToAdapter[lsdToken];
        if (adapter != address(0)) {
            require(!_adapterPaused[adapter], ErrorsLib.ADAPTER_DISABLED);
            return ILSDAdapter(adapter).convertToUnderlying(lsdToken, amount);
        }
        require(!_adapterPaused[address(erc4626Adapter)], ErrorsLib.ADAPTER_DISABLED);
        return erc4626Adapter.convertToUnderlying(lsdToken, amount);
    }

    function _getRateRecursive(address lsdToken, address[] memory path)
        internal
        view
        returns (ILSDAdapter.ExchangeRateInfo memory info)
    {
        _assertNoCycle(lsdToken, path);
        info = _getRate(lsdToken);

        if (info.isNative || lsdToAdapter[info.underlyingAsset] == address(0)) {
            return info;
        }

        ILSDAdapter.ExchangeRateInfo memory deeper = _getRateRecursive(info.underlyingAsset, _append(path, lsdToken));
        info.rate = (info.rate * deeper.rate) / (10 ** uint256(deeper.lsdDecimals));
        info.underlyingAsset = deeper.underlyingAsset;
        info.underlyingSymbol = deeper.underlyingSymbol;
        info.underlyingDecimals = deeper.underlyingDecimals;
        info.isNative = deeper.isNative;
        info.timestamp = deeper.timestamp < info.timestamp ? deeper.timestamp : info.timestamp;
    }

    function _convertRecursive(address lsdToken, uint256 amount, address[] memory path)
        internal
        view
        returns (uint256 underlyingAmount, ILSDAdapter.ExchangeRateInfo memory info)
    {
        _assertNoCycle(lsdToken, path);
        (underlyingAmount, info) = _convert(lsdToken, amount);

        if (info.isNative || lsdToAdapter[info.underlyingAsset] == address(0)) {
            return (underlyingAmount, info);
        }

        (uint256 deeperAmount, ILSDAdapter.ExchangeRateInfo memory deeper) =
            _convertRecursive(info.underlyingAsset, underlyingAmount, _append(path, lsdToken));

        info.rate = (info.rate * deeper.rate) / (10 ** uint256(deeper.lsdDecimals));
        info.underlyingAsset = deeper.underlyingAsset;
        info.underlyingSymbol = deeper.underlyingSymbol;
        info.underlyingDecimals = deeper.underlyingDecimals;
        info.isNative = deeper.isNative;
        info.timestamp = deeper.timestamp < info.timestamp ? deeper.timestamp : info.timestamp;
        return (deeperAmount, info);
    }

    function _assertNoCycle(address lsdToken, address[] memory path) internal pure {
        for (uint256 i = 0; i < path.length; i++) {
            require(path[i] != lsdToken, ErrorsLib.RECURSION_LOOP);
        }
    }

    function _append(address[] memory path, address item) internal pure returns (address[] memory) {
        address[] memory next = new address[](path.length + 1);
        for (uint256 i = 0; i < path.length; i++) {
            next[i] = path[i];
        }
        next[path.length] = item;
        return next;
    }


    function _authorizeUpgrade(address) internal override onlyOwner {}

    // -------- Storage gap --------
    // Reserve 50 slots for future fields. Append new fields above this gap and
    // shrink the gap by the same count to preserve layout on upgrades.

    uint256[50] private __gap;
}
