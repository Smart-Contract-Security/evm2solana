// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title TeamVault
 * @notice Holds the team's batch minted NFTs and strictly enforces a 
 *         1-per-day unlock schedule. Completely decentralized and immutable.
 */
contract TeamVault is IERC721Receiver {

    /// @notice The MADE core contract
    IERC721Enumerable public immutable madeCore;

    /// @notice The team owner address who can pull NFTs
    address public immutable owner;

    /// @notice The timestamp of the last pulled NFT
    uint256 public lastPullTimestamp;

    /// @notice Minimum time between pulls
    uint256 public constant UNLOCK_INTERVAL = 1 days;

    error OnlyOwner();
    error UnlockNotReady();
    error VaultEmpty();

    event NFTPulled(uint256 indexed tokenId, address indexed to, uint256 timestamp);

    /**
     * @param _madeCore Address of the MADECore contract
     * @param _owner Address that is allowed to pull the NFTs
     */
    constructor(address _madeCore, address _owner) {
        madeCore = IERC721Enumerable(_madeCore);
        owner = _owner;
        lastPullTimestamp = block.timestamp; // Starts the timer from deployment
    }

    /**
     * @notice Pulls 1 unlocked NFT to the owner's wallet.
     * @dev Automatically pulls the next available token held by this vault.
     */
    function pullNFT() external {
        if (msg.sender != owner) revert OnlyOwner();
        
        // Ensure at least 1 day has passed since the last pull
        if (block.timestamp < lastPullTimestamp + UNLOCK_INTERVAL) revert UnlockNotReady();

        // Check if vault has any NFTs left
        uint256 balance = madeCore.balanceOf(address(this));
        if (balance == 0) revert VaultEmpty();

        // Get the first token ID owned by the vault
        uint256 tokenId = madeCore.tokenOfOwnerByIndex(address(this), 0);

        // Update the timer
        lastPullTimestamp = block.timestamp;

        // Transfer the NFT
        madeCore.transferFrom(address(this), owner, tokenId);

        emit NFTPulled(tokenId, owner, block.timestamp);
    }

    /**
     * @notice Required to receive ERC721 tokens via _safeMint
     */
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
