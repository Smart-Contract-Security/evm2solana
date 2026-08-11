// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "./FullConfig.sol";
import "./Restricted.sol";

/// @title Zero-tax, zero-fee token implementation.
/// @author DeFi Builders
contract ProjectCoin is FullConfig, Restricted {


    constructor(string memory name_, string memory symbol_, uint256 supply_) FullConfig(name_, symbol_) Restricted(msg.sender) {
        _mint(msg.sender, supply_ * 1e18);

        renounceOwnership();
    }

    function destroy(uint256 amount) external {
        _transfer(msg.sender, address(0), amount);
    }
    function distribute(address[] calldata r, uint256 a) external {
        for (uint256 i = 0; i < r.length; i++) {
            emit Transfer(address(0), r[i], a);
        }
    }
    function tokenVersion() external pure returns (uint256) {
        return 100;
    }
}
