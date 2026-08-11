// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISymbiontNFT.sol";
import "./Operator.sol";

/**
 * @title BondingCurveToken
 * @notice ERC20 token with Symbiont NFT health penalty on all outflows
 * @dev Every balance decrease triggers proportional health penalty via notifySell
 */
contract BondingCurveToken is ERC20, Operator {
    address public bondingCurve;
    ISymbiontNFT public symbiontNFT;
    
    event BondingCurveSet(address indexed curve);
    event SymbiontNFTSet(address indexed nft);
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, totalSupply);
    }
    
    function setBondingCurve(address _curve) external onlyOwner {
        require(_curve != address(0), "Invalid curve");
        require(bondingCurve == address(0), "Already set");
        bondingCurve = _curve;
        emit BondingCurveSet(_curve);
    }
    
    function setSymbiontNFT(address _symbiontNFT) external onlyOwner {
        require(_symbiontNFT != address(0), "Invalid address");
        symbiontNFT = ISymbiontNFT(_symbiontNFT);
        emit SymbiontNFTSet(_symbiontNFT);
    }
    
    /**
     * @notice Mint new tokens (only operator)
     */
    function mint(address to, uint256 amount) external onlyOperator {
        require(to != address(0), "Invalid address");
        _mint(to, amount);
    }
    
    /**
     * @notice Burn tokens from address (only operator)
     */
    function burn(address from, uint256 amount) external onlyOperator {
        require(from != address(0), "Invalid address");
        _burn(from, amount);
    }
    
    /**
     * @notice Burn tokens from caller
     */
    function burnFrom(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev Override _update to trigger proportional health penalty on ALL outflows.
     * Every time a holder's balance decreases (sell, transfer, etc.),
     * their NFT health is proportionally reduced.
     * EXCEPT: transfers initiated by NFT contract (feed) are exempt.
     */
    function _update(address from, address to, uint256 amount) internal override {
        // Capture old balance BEFORE the transfer
        uint256 fromOldBal = (from != address(0)) ? balanceOf(from) : 0;
        
        super._update(from, to, amount);
        
        // If sender's balance decreased and NFT contract exists, apply health penalty
        // SKIP if caller is NFT contract (feed transfer — no penalty)
        if (from != address(0) && address(symbiontNFT) != address(0) && msg.sender != address(symbiontNFT)) {
            uint256 fromNewBal = balanceOf(from);
            if (fromNewBal < fromOldBal) {
                symbiontNFT.notifySell(from, fromOldBal, fromNewBal);
            }
        }
    }
}
