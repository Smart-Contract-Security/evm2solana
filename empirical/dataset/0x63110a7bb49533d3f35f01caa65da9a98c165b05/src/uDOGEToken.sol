// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title uDOGEToken
 */
contract uDOGEToken is ERC20, ERC20Burnable, Ownable {
    

    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10**18;
    

    address public hookContract;

    event HookContractUpdated(address indexed newHook);

    modifier onlyHook() {
        require(msg.sender == hookContract, "uDOGEToken: Only Hook can call");
        _;
    }

    constructor(address _initialOwner) ERC20("uDOGE Token", "uDOGE") Ownable(_initialOwner) {}

    
    function setHookContract(address _hookContract) external onlyOwner {
        require(hookContract == address(0), "uDOGEToken: Hook contract already set");
        require(_hookContract != address(0), "uDOGEToken: Invalid address");
        
        hookContract = _hookContract;
        emit HookContractUpdated(_hookContract);


        _mint(_hookContract, 1_000_000_000 * 10**18);
    }

    
    function mint(address to, uint256 amount) external onlyHook {
        require(totalSupply() + amount <= MAX_SUPPLY, "uDOGEToken: Exceeds absolute max supply");
        _mint(to, amount);
    }
}
