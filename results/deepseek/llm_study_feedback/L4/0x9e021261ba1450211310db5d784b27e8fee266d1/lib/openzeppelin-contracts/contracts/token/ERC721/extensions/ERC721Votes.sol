// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "../ERC721.sol";
import {Votes} from "../../../governance/utils/Votes.sol";

abstract contract ERC721Votes is ERC721, Votes {
    function _update(address to, uint256 tokenId, address auth) internal virtual override(ERC721, Votes) returns (address) {
        address previousOwner = ERC721._update(to, tokenId, auth);

        _transferVotingUnits(previousOwner, to, 1);

        return previousOwner;
    }

    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return ERC721.balanceOf(account);
    }

    function _increaseBalance(address account, uint128 amount) internal virtual override {
        Votes._increaseBalance(account, amount);
        _transferVotingUnits(address(0), account, amount);
    }
}