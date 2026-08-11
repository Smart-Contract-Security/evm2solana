// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { CoreAccess } from "../base/CoreAccess.sol";
import { IBlocklist } from "../interfaces/IBlocklist.sol";
import { IShareToken } from "../interfaces/IShareToken.sol";
import { Roles } from "../libraries/Roles.sol";

/// @title ShareToken
contract ShareToken is ERC20, CoreAccess, IShareToken {
    IBlocklist public blocklist;
    string private _shareName;
    string private _shareSymbol;
    mapping(address => address) private _vaultByAsset;
    mapping(address => address) private _assetByVault;
    bool private _shareTokenInitialized;

    constructor(string memory name_, string memory symbol_, address admin, address blocklist_)
        ERC20(name_, symbol_)
        CoreAccess(admin)
    {
        if (admin != address(0)) _initializeShareToken(name_, symbol_, blocklist_);
    }

    function initialize(string memory name_, string memory symbol_, address admin, address blocklist_) external {
        _initializeCoreAccess(admin);
        _initializeShareToken(name_, symbol_, blocklist_);
    }

    function _initializeShareToken(string memory name_, string memory symbol_, address blocklist_) internal {
        require(!_shareTokenInitialized, "ShareToken: initialized");
        require(blocklist_ != address(0), "ShareToken: zero blocklist");
        _shareTokenInitialized = true;
        _shareName = name_;
        _shareSymbol = symbol_;
        blocklist = IBlocklist(blocklist_);
    }

    function name() public view override returns (string memory) {
        return _shareName;
    }

    function symbol() public view override returns (string memory) {
        return _shareSymbol;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IShareToken).interfaceId;
    }

    function mint(address to, uint256 amount) external {
        require(isVault(msg.sender) || hasRole(Roles.TOKEN_MINTER, msg.sender), "ShareToken: not minter");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(isVault(msg.sender) || hasRole(Roles.TOKEN_MINTER, msg.sender), "ShareToken: not burner");
        _burn(from, amount);
    }

    function addVault(address asset_, address vault_) external onlyAdmin {
        require(asset_ != address(0) && vault_ != address(0), "ShareToken: zero address");
        address oldVault = _vaultByAsset[asset_];
        if (oldVault != address(0)) {
            delete _assetByVault[oldVault];
        }
        _vaultByAsset[asset_] = vault_;
        _assetByVault[vault_] = asset_;
        emit VaultAdded(asset_, vault_);
    }

    function removeVault(address asset_) external onlyAdmin {
        address oldVault = _vaultByAsset[asset_];
        require(oldVault != address(0), "ShareToken: missing vault");
        delete _vaultByAsset[asset_];
        delete _assetByVault[oldVault];
        emit VaultRemoved(asset_, oldVault);
    }

    function vault(address asset_) external view returns (address) {
        return _vaultByAsset[asset_];
    }

    function asset(address vault_) external view returns (address) {
        return _assetByVault[vault_];
    }

    function isVault(address vault_) public view returns (bool) {
        return _assetByVault[vault_] != address(0);
    }

    function _transfer(address from, address to, uint256 value) internal override {
        require(!blocklist.isBlocked(from) && !blocklist.isBlocked(to), "ShareToken: blocked");
        super._transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal override {
        require(!blocklist.isBlocked(to), "ShareToken: blocked");
        super._mint(to, value);
    }
}
