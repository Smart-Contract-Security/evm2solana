// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @title TransferValidation
 * @author Limit Break, Inc.
 * @notice A mix-in that can be combined with ERC-721 contracts to provide more granular hooks.
 * Openzeppelin's ERC721 contract only provides hooks for before and after transfer.  This allows
 * developers to validate or customize transfers within the context of a mint, a burn, or a transfer.
 */
abstract contract TransferValidation is Context {
    
    error ShouldNotMintToBurnAddress();

    /// @dev Inheriting contracts should call this function in the _beforeTokenTransfer function to get more granular hooks.
    function _validateBeforeTransfer(address from, address to, uint256 tokenId) internal virtual {
        bool fromZeroAddress = from == address(0);
        bool toZeroAddress = to == address(0);

        if(fromZeroAddress && toZeroAddress) {
            revert ShouldNotMintToBurnAddress();
        } else if(fromZeroAddress) {
            _preValidateMint(_msgSender(), to, tokenId, msg.value);
        } else if(toZeroAddress) {
            _preValidateBurn(_msgSender(), from, tokenId, msg.value);
        } else {
            _preValidateTransfer(_msgSender(), from, to, tokenId, msg.value);
        }
    }

    /// @dev Inheriting contracts should call this function in the _afterTokenTransfer function to get more granular hooks.
    function _validateAfterTransfer(address from, address to, uint256 tokenId) internal virtual {
        bool fromZeroAddress = from == address(0);
        bool toZeroAddress = to == address(0);

        if(fromZeroAddress && toZeroAddress) {
            revert ShouldNotMintToBurnAddress();
        } else if(fromZeroAddress) {
            _postValidateMint(_msgSender(), to, tokenId, msg.value);
        } else if(toZeroAddress) {
            _postValidateBurn(_msgSender(), from, tokenId, msg.value);
        } else {
            _postValidateTransfer(_msgSender(), from, to, tokenId, msg.value);
        }
    }

    /// @dev Optional validation hook that fires before a mint
    function _preValidateMint(address caller, address to, uint256 tokenId, uint256 value) internal virtual {}

    /// @dev Optional validation hook that fires after a mint
    function _postValidateMint(address caller, address to, uint256 tokenId, uint256 value) internal virtual {}

    /// @dev Optional validation hook that fires before a burn
    function _preValidateBurn(address caller, address from, uint256 tokenId, uint256 value) internal virtual {}

    /// @dev Optional validation hook that fires after a burn
    function _postValidateBurn(address caller, address from, uint256 tokenId, uint256 value) internal virtual {}

    /// @dev Optional validation hook that fires before a transfer
    function _preValidateTransfer(address caller, address from, address to, uint256 tokenId, uint256 value) internal virtual {}

    /// @dev Optional validation hook that fires after a transfer
    function _postValidateTransfer(address caller, address from, address to, uint256 tokenId, uint256 value) internal virtual {}
}