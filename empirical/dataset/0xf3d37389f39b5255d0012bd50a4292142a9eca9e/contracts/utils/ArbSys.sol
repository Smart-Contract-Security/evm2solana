// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ArbSys {
    function arbBlockNumber() external view returns (uint256);
}

library ChainBlockNumber {
    // Arbitrum precompile address
    address constant ARBSYS_ADDR = address(0x0000000000000000000000000000000000000064);

    function canonicalBlockNumber() internal view returns (uint256) {
        uint256 cid = block.chainid;

        // Arbitrum One (42161) or Arbitrum Sepolia (421614), etc
        if (cid == 42161 || cid == 421614) {
            // L2 block number on Arbitrum
            return ArbSys(ARBSYS_ADDR).arbBlockNumber();
        }

        // Normal behavior on Polygon, Ethereum, etc
        return block.number;
    }
}
