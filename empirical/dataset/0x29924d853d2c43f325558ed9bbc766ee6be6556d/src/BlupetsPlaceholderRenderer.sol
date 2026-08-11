// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IBlupetsRenderer} from "./IBlupetsRenderer.sol";

contract BlupetsPlaceholderRenderer is IBlupetsRenderer {
    using Strings for uint256;

    function tokenURI(uint256 tokenId) external pure returns (string memory) {
        return string.concat(
            'data:application/json,{"name":"Blupet #',
            tokenId.toString(),
            '","description":"Blupets metadata is being configured."}'
        );
    }
}
