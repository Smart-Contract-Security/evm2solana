// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (token/ERC721/utils/ERC721Utils.sol)

import {IERC721Errors} from "../../../interfaces/draft-IERC6093.sol";

/**
 * @dev Interface of the ERC721Receiver standard, as defined in the EIP.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be
     * reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint64 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/**
 * @dev Library that provides common ERC-721 utility functions.
 *
 * See https://eips.ethereum.org/EIPS/eip-721[ERC-721].
 *
 * _Available since v5.1._
 */
library ERC721Utils {
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
        // We attempt the call and handle failure via try-catch.
        // Note: try-catch is not supported on Solana, so we use a different approach.
        // We call the receiver and check the return value directly.
        // If the call fails, it will revert automatically.
        bytes4 retval = IERC721Receiver(to).onERC721Received(operator, from, tokenId, data);
        if (retval != IERC721Receiver.onERC721Received.selector) {
            revert IERC721Errors.ERC721InvalidReceiver(to);
        }
    }
}