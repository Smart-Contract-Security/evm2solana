// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title Rescuable
/// @notice Owner-gated recovery of assets accidentally sent to a contract (ETH,
///         ERC-20, ERC-721, ERC-1155). The inheriting contract supplies the
///         authorization in `_authorizeRescue` — typically `_checkOwner()`.
///
///         WARNING: do NOT mix this into a contract that legitimately escrows
///         the asset type being rescued — a blanket rescue is then a withdrawal
///         backdoor. (E.g. SeasonSloplingsState custodies the vault NFTs, so it
///         is deliberately NOT Rescuable; its controlled, pause-gated
///         `withdrawNFTs` is the only way those leave.)
abstract contract Rescuable {
    using SafeTransferLib for address;

    /// @dev Reverts if the caller may not rescue. Supplied by the inheritor
    ///      (typically `_checkOwner()`).
    function _authorizeRescue() internal view virtual;

    modifier onlyRescuer() {
        _authorizeRescue();
        _;
    }

    function rescueETH(address to, uint256 amount) external onlyRescuer {
        to.safeTransferETH(amount);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyRescuer {
        token.safeTransfer(to, amount);
    }

    function rescueERC721(address token, address to, uint256 tokenId) external onlyRescuer {
        IERC721(token).transferFrom(address(this), to, tokenId);
    }

    function rescueERC1155(address token, address to, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyRescuer
    {
        IERC1155(token).safeTransferFrom(address(this), to, id, amount, data);
    }
}
