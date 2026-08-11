// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title JustMarried.sol
 * @notice Wishing you both a lifetime of happiness.
 */
contract JustMarried {
    using SafeERC20 for IERC20;

    /**
     * @dev Ensure callers made a loving commitment to one-another.
     */
    modifier onlyAryaAndSuly() {
        require(msg.sender == 0x3341DD81D325F231aa744efD603B8255D8cc3515);
        _;
    }

    /**
     * @notice Suly - I've always known that Arya possessed a profound
     *         eye for the goodness in people, and he wants to spend
     *         the rest of his life looking at you.
     * @param gift Token to withdraw.
     */
    function loveAndHappiness_ILyuzm7jE(IERC20 gift) external onlyAryaAndSuly {
        gift.safeTransfer(msg.sender, gift.balanceOf(address(this)));
    }
}
