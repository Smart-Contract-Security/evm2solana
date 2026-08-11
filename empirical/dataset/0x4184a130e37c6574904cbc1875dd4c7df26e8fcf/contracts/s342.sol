// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract S342 is ERC20, Ownable, ERC20Burnable {
    
    constructor() 
        ERC20("S342", "S342") 
        Ownable(msg.sender) 
    {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }
    
    function renounceOwnershipPermanently() public onlyOwner {
        renounceOwnership();
    }
    
    bool private _paused;
    
    event Paused(address account);
    event Unpaused(address account);
    
    modifier whenNotPaused() {
        require(!_paused, "S342: Paused");
        _;
    }
    
    function pause() public onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    function unpause() public onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    function transfer(address to, uint256 amount) 
        public 
        virtual 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) 
        public 
        virtual 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transferFrom(from, to, amount);
    }
}