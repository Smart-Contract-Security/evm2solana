// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../templates/ERC721/ERC721Base.sol";
import "../templates/ERC721/ERC721Pausable.sol";

contract ERC721_pausable is
  ERC721Base,
  ERC721PausableFeature
{
  constructor(string memory name_, string memory symbol_, string memory baseURI_, string memory uriSuffix_, address royaltyReceiver_, uint96 royaltyFeeNumerator_)
    ERC721Base(name_, symbol_, baseURI_, uriSuffix_, royaltyReceiver_, royaltyFeeNumerator_)
  {
    _grantRole(PAUSER_ROLE, msg.sender);
  }

  function _update(address to, uint256 tokenId, address auth)
    internal
    override(ERC721)
    returns (address)
  {
    require(!paused(), "Pausable: paused");
    return super._update(to, tokenId, auth);
  }
}
