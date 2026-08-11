// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WorldCupRewardToken
 * @dev Utility ERC-20 reward token for WorldCupBall NFT holders.
 * Max supply is capped at 100,000,000. 
 * During deployment, 2% is sent to the deployer, and 98% is held in the NFT contract for daily rewards and deployer vesting claims.
 * Standard transfers carry a 1% tax sent to the deployer (owner).
 */
contract WorldCupRewardToken is ERC20, Ownable {
    address public immutable nftContract;
    address public taxRecipient;

    constructor(address deployer, address _nftContract) ERC20("WorldCupBall", "WCB") Ownable(deployer) {
        nftContract = _nftContract;
        taxRecipient = deployer;

        uint256 maxSupply = 1_000_000_000 * 10**18; // 1 Billion tokens
        uint256 deployerShare = (maxSupply * 2) / 100; // 2% of total supply
        uint256 nftShare = maxSupply - deployerShare;  // 98% of total supply

        _mint(deployer, deployerShare);
        _mint(_nftContract, nftShare);
    }

    /**
     * @notice Allows the owner to update the tax recipient address.
     */
    function setTaxRecipient(address _taxRecipient) external onlyOwner {
        require(_taxRecipient != address(0), "Invalid address");
        taxRecipient = _taxRecipient;
    }

    /**
     * @dev Overrides ERC-20 update hook to implement a 1% transfer tax on standard transfers.
     * Mints, burns, and transfers involving the NFT contract (rewards distributions) or the deployer are tax-free.
     */
    function _update(address from, address to, uint256 value) internal override {
        // Exclude mints, burns, and transfers involving the NFT contract or owner from tax
        if (from == address(0) || to == address(0) || from == nftContract || to == nftContract || from == owner() || to == owner()) {
            super._update(from, to, value);
        } else {
            uint256 taxAmount = (value * 1) / 100; // 1% tax
            uint256 sendAmount = value - taxAmount;

            super._update(from, taxRecipient, taxAmount);
            super._update(from, to, sendAmount);
        }
    }
}
