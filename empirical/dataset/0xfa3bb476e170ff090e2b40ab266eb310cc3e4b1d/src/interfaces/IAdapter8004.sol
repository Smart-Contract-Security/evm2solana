// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

enum TokenStandard {
    ERC721,
    ERC1155,
    ERC6909
}

interface IAdapter8004 {
    struct Binding {
        TokenStandard standard;
        address tokenContract;
        uint256 tokenId;
    }

    function bindingOf(uint256 agentId) external view returns (Binding memory);
}
