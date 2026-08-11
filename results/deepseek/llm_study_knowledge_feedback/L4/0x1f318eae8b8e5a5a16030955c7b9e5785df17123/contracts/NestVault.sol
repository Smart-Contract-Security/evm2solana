// SPDX-License-Identifier: AGPL-3.0-only

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract NestVault is ERC4626Upgradeable {
    address private _permit2;

    constructor(address _share, address _permit2Addr) {
        _permit2 = _permit2Addr;
    }

    function initialize(
        address _accountant,
        address _asset,
        address _owner,
        uint64 _minRate,
        address _operatorRegistry
    ) external {
        __NestVaultCore_init(_accountant, _asset, _owner, _minRate, _operatorRegistry, version());
    }

    function __NestVaultCore_init(
        address _accountant,
        address _asset,
        address _owner,
        uint64 _minRate,
        address _operatorRegistry,
        string memory _version
    ) internal {
        // Initialization logic would go here
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    function deposit(uint64 _assets, address _receiver) public virtual returns (uint64) {
        return _assets;
    }

    function mint(uint64 _shares, address _receiver) public virtual returns (uint64) {
        return _shares;
    }
}