// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "../IERC721Receiver.sol";
import {IERC721Errors} from "../../../interfaces/draft-IERC6093.sol";

library ERC721Utils {
    function checkOnERC721Received(
        address operator,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external {
        // On Solana, we cannot check `to.code.length`. Instead, we always attempt the call.
        // If `to` is not a contract, the call will fail and we revert with ERC721InvalidReceiver.
        (bool success, bytes memory returndata) = to.call{accounts: [to]}(
            abi.encodeWithSelector(IERC721Receiver.onERC721Received.selector, operator, from, tokenId, data)
        );

        if (success) {
            bytes4 retval = abi.decode(returndata, (bytes4));
            if (retval != IERC721Receiver.onERC721Received.selector) {
                revert IERC721Errors.ERC721InvalidReceiver(to);
            }
        } else {
            if (returndata.length == 0) {
                revert IERC721Errors.ERC721InvalidReceiver(to);
            } else {
                assembly {
                    revert(add(returndata, 0x20), mload(returndata))
                }
            }
        }
    }
}