// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../base/BronNft.sol";

contract YxyzNft is BronNft {
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        string memory _contractURI,
        address _owner
    ) public initializer {
        __BronNft_init(_name, _symbol, _baseURI, _contractURI, _owner);
    }
}
