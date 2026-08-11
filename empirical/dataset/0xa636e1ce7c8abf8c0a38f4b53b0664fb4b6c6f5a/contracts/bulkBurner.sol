// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721Burnable {
    function burn(uint256 tokenId) external;
}

contract bulkBurner {
    IERC721Burnable public nftContract;

    constructor() {
        nftContract = IERC721Burnable(0xD4307E0acD12CF46fD6cf93BC264f5D5D1598792);
    }

    function bulkBurn(uint256[] calldata tokenIds) external {
        require(tokenIds.length <= 30, "Cannot burn more than 30 tokens at a time");

        for (uint i = 0; i < tokenIds.length; i++) {
            // The caller of this function must be authorized to burn tokens
            nftContract.burn(tokenIds[i]);
        }
    }
}
