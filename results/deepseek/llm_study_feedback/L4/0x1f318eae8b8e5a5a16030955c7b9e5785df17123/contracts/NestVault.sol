// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract NestVault is ERC4626Upgradeable {
    address private _permit2;
    address private _accountant;
    address private _owner;
    uint256 private _minRate;
    address private _operatorRegistry;
    string private _version;

    constructor(address payable _share, address _permit2Addr) {
        _permit2 = _permit2Addr;
        _disableInitializers();
    }

    function initialize(
        address _accountantAddr,
        address _asset,
        address _ownerAddr,
        uint256 _minRateVal,
        address _operatorRegistryAddr
    ) external virtual initializer {
        __NestVaultCore_init(_accountantAddr, _asset, _ownerAddr, _minRateVal, _operatorRegistryAddr, version());
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    function deposit(uint256 _assets, address _receiver) public virtual override returns (uint256) {
        return super.deposit(_assets, _receiver);
    }

    function mint(uint256 _shares, address _receiver) public virtual override returns (uint256) {
        return super.mint(_shares, _receiver);
    }

    function __NestVaultCore_init(
        address _accountantAddr,
        address _asset,
        address _ownerAddr,
        uint256 _minRateVal,
        address _operatorRegistryAddr,
        string memory _ver
    ) internal {
        __ERC4626_init(IERC20Upgradeable(_asset));
        _accountant = _accountantAddr;
        _owner = _ownerAddr;
        _minRate = _minRateVal;
        _operatorRegistry = _operatorRegistryAddr;
        _version = _ver;
    }

    function _disableInitializers() internal {
        // Placeholder for initializer disabling logic
    }
}