// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (token/ERC721/utils/ERC721Utils.sol)

import {IERC721Errors} from "../../../interfaces/draft-IERC6093.sol";

/**
 * @dev Library that provides common ERC-721 utility functions.
 *
 * See https://eips.ethereum.org/EIPS/eip-721[ERC-721].
 *
 * _Available since v5.1._
 */
library ERC721Utils {
    bytes4 constant ERC721_RECEIVED = bytes4(keccak256("onERC721Received(address,address,uint64,bytes)"));

    /**
     * @dev Performs an acceptance check for the provided `operator` by calling {IERC721Receiver-onERC721Received}
     * on the `to` address. The `operator` is generally the address that initiated the token transfer (i.e. `msg.sender`).
     *
     * The acceptance call is not executed and treated as a no-op if the target address doesn't contain code (i.e. an EOA).
     * Otherwise, the recipient must implement {IERC721Receiver-onERC721Received} and return the acceptance magic value to accept
     * the transfer.
     */
    function checkOnERC721Received(
        address operator,
        address from,
        address to,
        uint64 tokenId,
        bytes memory data
    ) internal {
        // On Solana, we cannot check code length of an address.
        // We attempt the external call and handle failure via try-catch.
        // Note: try-catch is not supported on Solana, so we use a different approach.
        // We call the receiver and check the return value directly.
        // If the call fails, it will revert automatically.
        (bool success, bytes memory returnData) = to.call{value: 0}(
            abi.encodeWithSignature("onERC721Received(address,address,uint64,bytes)", operator, from, tokenId, data)
        );
        if (!success) {
            revert IERC721Errors.ERC721InvalidReceiver(to);
        }
        bytes4 retval = abi.decode(returnData, (bytes4));
        if (retval != ERC721_RECEIVED) {
            // Token rejected
            revert IERC721Errors.ERC721InvalidReceiver(to);
        }
    }
}