// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../libs/P2PLibrary.sol";

interface IFactory {
    function getTokenInfo(
        address tokenAddress
    ) external view returns (P2PLibrary.TokenInfo memory);
}
