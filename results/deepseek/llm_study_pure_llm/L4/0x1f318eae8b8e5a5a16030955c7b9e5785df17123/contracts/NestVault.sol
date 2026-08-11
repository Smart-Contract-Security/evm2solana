// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {NestVaultPermit2} from "contracts/NestVaultPermit2.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract NestVault is NestVaultPermit2 {
    constructor(address payable _share, address _permit2) NestVaultPermit2(_share, _permit2) {
        _disableInitializers();
    }

    function initialize(
        address _accountant,
        address _asset,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry
    ) external virtual initializer {
        __NestVaultCore_init(_accountant, _asset, _owner, _minRate, _operatorRegistry, version());
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
}