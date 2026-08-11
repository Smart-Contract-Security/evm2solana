// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20MetadataMintable is IERC20Metadata {
    function mintFromFactory(address to, uint256 amount) external;
}
