// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IPunksMarket {
    function buyPunk(uint16 punkId, uint96 expectedListingWei, address recipient) external payable;
}

interface ICryptoPunksV1 {
    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external;
}

interface IPunksV1Wrapper {
    function wrap(uint256 punkId) external payable;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}
