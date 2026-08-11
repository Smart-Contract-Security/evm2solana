// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (token/ERC721/utils/ERC721Utils.sol)

import {IERC721Receiver} from "../IERC721Receiver.sol";
import {IERC721Errors} from "../../../interfaces/draft-IERC6093.sol";

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
        // On Solana, try-catch is not supported.
        // We perform the external call and check the return data manually.
        (bool success, bytes memory returndata) = address(to).call{accounts: []}(
            abi.encodeWithSelector(IERC721Receiver.onERC721Received.selector, operator, from, tokenId, data)
        );

        if (success && returndata.length >= 4) {
            bytes4 retval = abi.decode(returndata, (bytes4));
            if (retval != IERC721Receiver.onERC721Received.selector) {
                // Token rejected
                revert IERC721Errors.ERC721InvalidReceiver(to);
            }
        } else {
            // Call failed or returned no data
            revert IERC721Errors.ERC721InvalidReceiver(to);
        }
    }
}