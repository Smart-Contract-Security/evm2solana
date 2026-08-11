// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {StablecoinBase} from "./StablecoinBase.sol";

/// @title PLNY
/// @notice PLNY - PLN-pegged stablecoin (1 PLNY = 1 PLN).
/// @dev Inherits all functionality from StablecoinBase. This contract only sets the token name and symbol.
contract PLNY is StablecoinBase {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the PLNY token with the AccessManager authority.
    /// @param initialAuthority The address of the AccessManager contract that will govern this token.
    function initialize(address initialAuthority) external initializer {
        __ERC20_init("PLNY", "PLNY");
        __ERC20Permit_init("PLNY");
        __Pausable_init();
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();
    }
}
