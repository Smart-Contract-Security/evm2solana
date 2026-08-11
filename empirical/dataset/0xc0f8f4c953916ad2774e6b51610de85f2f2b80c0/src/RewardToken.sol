// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

/**
 * @title RewardToken (REWARD)
 * @notice The farm's reward token. Supply starts at ZERO and is minted on-demand by the
 *         FarmHook only:
 *           - the one-time genesis seed (paired with the deployer's ETH), and
 *           - emissions, minted when farmers `claim()`.
 *
 * @dev The hook is the SOLE minter, set immutably at construction. Because the hook address
 *      is known ahead of time (it is CREATE2-mined for its permission flags), we can pass it
 *      straight into the constructor — so there is never a window where the deployer can mint.
 *      No premine, no owner mint, no cap change. The entire inflation schedule lives in the hook.
 */
contract RewardToken is ERC20 {
    /// @notice The only address allowed to mint — the FarmHook.
    address public immutable minter;

    error OnlyMinter();

    constructor(string memory name_, string memory symbol_, address minter_) ERC20(name_, symbol_, 18) {
        minter = minter_;
    }

    /// @notice Mint `amount` to `to`. Callable only by the hook.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }
}
