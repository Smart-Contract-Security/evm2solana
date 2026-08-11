// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title WrappedStellarPT
 * @notice ERC20 representation of a Stellar-native Principal Token on EVM
 * @dev Deployed by PTBridge via BeaconProxy + CREATE2 when a native Stellar PT is first bridged.
 *      Only the bridge can mint (on lock) and burn (on unlock).
 *      Uses Beacon Proxy pattern: all instances share one implementation, upgradeable in one tx.
 */
contract WrappedStellarPT is ERC20 {
    uint8 private _decimals;
    uint256 public maturity;
    string public stellarPtAddress;
    address public bridge;

    bool private _initialized;

    error OnlyBridge();

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    constructor() ERC20("", "") {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maturity_,
        string memory stellarPtAddress_,
        address bridge_
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        maturity = maturity_;
        stellarPtAddress = stellarPtAddress_;
        bridge = bridge_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyBridge {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyBridge {
        _burn(from, amount);
    }

    function _disableInitializers() internal {
        _initialized = true;
    }
}