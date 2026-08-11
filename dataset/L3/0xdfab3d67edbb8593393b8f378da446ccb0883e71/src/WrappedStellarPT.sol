// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title WrappedStellarPT
 * @notice ERC20 representation of a Stellar-native Principal Token on EVM
 * @dev Deployed by PTBridge via BeaconProxy + CREATE2 when a native Stellar PT is first bridged.
 *      Only the bridge can mint (on lock) and burn (on unlock).
 *      Uses Beacon Proxy pattern: all instances share one implementation, upgradeable in one tx.
 */
contract WrappedStellarPT is Initializable, ERC20Upgradeable {
    uint8 private _decimals;
    uint256 public maturity;
    string public stellarPtAddress;
    address public bridge;

    error OnlyBridge();

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maturity_,
        string memory stellarPtAddress_,
        address bridge_
    ) external initializer {
        __ERC20_init(name_, symbol_);
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
}
