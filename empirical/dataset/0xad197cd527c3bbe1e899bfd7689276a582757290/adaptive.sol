// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title AdaptiveToken
 * @dev This ERC20 token experiment allows for anyone to change the token's name and symbol.
 * This contract explores the concept of dynamic and adaptive token metadata, opening new avenues 
 * for token identity management in the decentralized world.
 *
 * The AdaptiveToken demonstrates how an ERC20 token's metadata can be made flexible, 
 * enabling changes through smart contract functions that can be further extended 
 * to include various governance models and external data integrations.
 *
 * Key Features and Potential Extensions:
 * 1. Dynamic Metadata Tokens
 * 2. Governance Models (DAO, reputation-based, etc.)
 * 3. Integration with External Data Oracles
 * 4. Social Media-driven Metadata Changes
 * 5. Time-based or Event-driven Metadata Adjustments
 *
 * These features aim to push the boundaries of what is possible with ERC20 tokens, 
 * making them more interactive, community-driven, and responsive to external inputs.
 */

contract AdaptiveToken is ERC20 {
    // Private variables to store the dynamic name and symbol
    string private _name;
    string private _symbol;
    uint256 private constant _initialSupply = 1_000_000 * 10 ** 18; // 1,000,000 tokens with 18 decimals

    /**
     * @dev Constructor that sets the initial name and symbol of the token, and mints the max supply to the deployer.
     * @param name_ Initial name of the token.
     * @param symbol_ Initial symbol of the token.
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _name = name_;
        _symbol = symbol_;
        _mint(msg.sender, _initialSupply); // Mint the max supply to the deployer
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Allows anyone to change the name of the token.
     * @param newName The new name of the token.
     */
    function changeName(string memory newName) public {
        _name = newName;
    }

    /**
     * @dev Allows anyone to change the symbol of the token.
     * @param newSymbol The new symbol of the token.
     */
    function changeSymbol(string memory newSymbol) public {
        _symbol = newSymbol;
    }
}
