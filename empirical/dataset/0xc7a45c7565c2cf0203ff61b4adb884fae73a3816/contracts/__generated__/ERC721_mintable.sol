// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../templates/ERC721/ERC721Base.sol";
import "../templates/ERC721/ERC721Mintable.sol";

contract ERC721_mintable is
  ERC721Base,
  ERC721MintableFeature
{
  constructor(string memory name_, string memory symbol_, string memory baseURI_, string memory uriSuffix_, address royaltyReceiver_, uint96 royaltyFeeNumerator_)
    ERC721Base(name_, symbol_, baseURI_, uriSuffix_, royaltyReceiver_, royaltyFeeNumerator_)
  {
    _grantRole(MINTER_ROLE, msg.sender);
  }

}
