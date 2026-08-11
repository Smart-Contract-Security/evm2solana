// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AirdropperV2 {
    function airdropTokens(
        IERC20 token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        uint256 length = recipients.length;
        IERC20 tokenContract = token;
        unchecked {
            for (uint256 i = 0; i < length; i++) {
                tokenContract.transferFrom(
                    msg.sender,
                    recipients[i],
                    amounts[i]
                );
            }
        }
    }
}
