// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

interface IBronNft {
    event BaseURIUpdated(string newBaseURI);
    event ContractURIUpdated(string newContractURI);
    function mint(address to, uint256 tokenId) external;
    function mintBatch(address to, uint256[] calldata tokenIds) external;
    function burn(uint256 tokenId) external;
    function setBaseURI(string memory baseURI) external;
    function setContractURI(string memory uri) external;
    function contractURI() external view returns (string memory);
    function pause() external;
    function unpause() external;
}
