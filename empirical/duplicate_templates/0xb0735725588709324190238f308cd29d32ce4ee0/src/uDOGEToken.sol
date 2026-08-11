// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title uDOGEToken
 * @dev uDOGE 代币合约。严格硬顶 1,000 亿枚。
 * 部署时直接向 Hook 合约铸造 10 亿枚作为流动性储备，其余 990 亿枚只能由 Hook 合约在 Mint 期间铸造。
 */
contract uDOGEToken is ERC20, ERC20Burnable, Ownable {
    
    // 绝对硬顶：1,000 亿枚
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10**18;
    
    // Hook 合约地址，唯一拥有 minter 权限
    address public hookContract;

    event HookContractUpdated(address indexed newHook);

    modifier onlyHook() {
        require(msg.sender == hookContract, "uDOGEToken: Only Hook can call");
        _;
    }

    constructor(address _initialOwner) ERC20("uDOGE Token", "uDOGE") Ownable(_initialOwner) {}

    /**
     * @dev 设置并锁定唯一 Hook 合约地址，同时铸造 10 亿预留代币给 Hook。
     * @param _hookContract Hook 主合约地址
     */
    function setHookContract(address _hookContract) external onlyOwner {
        require(hookContract == address(0), "uDOGEToken: Hook contract already set");
        require(_hookContract != address(0), "uDOGEToken: Invalid address");
        
        hookContract = _hookContract;
        emit HookContractUpdated(_hookContract);

        // 部署时预留 1% (10 亿枚) 铸造给 Hook 作为 V3 流动性储备，绝对零增发
        _mint(_hookContract, 1_000_000_000 * 10**18);
    }

    /**
     * @dev 唯一允许 Hook 合约在 Mint 阶段为用户铸造代币（上限为扣除储备后的 990 亿枚）
     */
    function mint(address to, uint256 amount) external onlyHook {
        require(totalSupply() + amount <= MAX_SUPPLY, "uDOGEToken: Exceeds absolute max supply");
        _mint(to, amount);
    }
}
