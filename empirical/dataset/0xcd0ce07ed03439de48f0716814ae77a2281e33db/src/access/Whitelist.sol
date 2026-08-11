// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CoreAccess } from "../base/CoreAccess.sol";
import { IWhitelist } from "../interfaces/IWhitelist.sol";

/// @title Whitelist
contract Whitelist is CoreAccess, IWhitelist {
    mapping(address => bool) private _users;
    mapping(address => bool) private _assets;
    mapping(address => uint8) private _assetDecimals;

    event UserWhitelistSet(address indexed account, bool allowed);
    event AssetWhitelistSet(address indexed asset, bool allowed);
    event AssetDecimalsSet(address indexed asset, uint8 decimals);

    constructor(address admin) CoreAccess(admin) { }

    function initialize(address admin) external {
        _initializeCoreAccess(admin);
    }

    function setUser(address account, bool allowed) external onlyAdmin {
        _users[account] = allowed;
        emit UserWhitelistSet(account, allowed);
    }

    function setUsers(address[] calldata accounts, bool[] calldata allowed)
        external
        onlyAdmin
    {
        require(accounts.length == allowed.length, "Whitelist: length mismatch");
        for (uint256 i; i < accounts.length; ++i) {
            _users[accounts[i]] = allowed[i];
            emit UserWhitelistSet(accounts[i], allowed[i]);
        }
    }

    function setAsset(address asset, bool allowed) external onlyAdmin {
        _assets[asset] = allowed;
        emit AssetWhitelistSet(asset, allowed);
    }

    function setAssetWithMetadata(address asset, bool allowed, uint8 decimals)
        external
        onlyAdmin
    {
        _assets[asset] = allowed;
        _assetDecimals[asset] = decimals;
        emit AssetWhitelistSet(asset, allowed);
        emit AssetDecimalsSet(asset, decimals);
    }

    function setAssets(address[] calldata assets, bool[] calldata allowed) external onlyAdmin {
        require(assets.length == allowed.length, "Whitelist: length mismatch");
        for (uint256 i; i < assets.length; ++i) {
            _assets[assets[i]] = allowed[i];
            emit AssetWhitelistSet(assets[i], allowed[i]);
        }
    }

    function isWhitelisted(address account) external view returns (bool) {
        return _users[account];
    }

    function isAssetAllowed(address asset) external view returns (bool) {
        return _assets[asset];
    }

    function assetDecimals(address asset) external view returns (uint8) {
        return _assetDecimals[asset];
    }
}
