// SPDX-License-Identifier: MIT

/*

    ASTRAFORGE NOMADS
    https://astraforgenomads.xyz
    https://x.com/astraforgeerc

*/

pragma solidity ^0.8.24;

import {DN404} from "./DN404.sol";

abstract contract DN404Pooled is DN404 {
    error PoolInitializationFailed();

    function _initializeDN404Pooled(
        uint256 erc20Supply,
        uint256 nftSupply,
        address initialMintTo,
        address mirror
    ) internal {
        if (erc20Supply != nftSupply * 1e18) revert PoolInitializationFailed();
        _initializeDN404(erc20Supply, nftSupply, initialMintTo, mirror);
    }
}
