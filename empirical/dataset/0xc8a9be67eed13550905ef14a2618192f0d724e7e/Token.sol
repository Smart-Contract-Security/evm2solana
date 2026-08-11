// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/**

https://arcshieldprotocol.com/
https://x.com/arc_shield

 */
contract Token {

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // Dynamic Max Wallet
    uint256 public initialMaxWalletBps;
    uint256 public growthBpsPerSecond;
    uint256 public deploymentTime;

    mapping(address => bool) public isExcludedFromMaxWallet;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialMaxWalletBps,
        uint256 _growthBpsPerSecond
    ) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
        deploymentTime = block.timestamp;

        initialMaxWalletBps = _initialMaxWalletBps;
        growthBpsPerSecond = _growthBpsPerSecond;

        uint256 supply = _totalSupply * (10 ** decimals);
        totalSupply = supply;
        balanceOf[msg.sender] = supply;   // ← All tokens minted to deployer

        // Exclude important addresses
        isExcludedFromMaxWallet[msg.sender] = true;
        isExcludedFromMaxWallet[address(this)] = true;
        isExcludedFromMaxWallet[0x000000000004444c5dc75cB358380D2e3dE08A90] = true; // V4 PoolManager
        isExcludedFromMaxWallet[0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e] = true; // Position Manager

        emit Transfer(address(0), msg.sender, supply);
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function currentMaxWalletBps() public view returns (uint256) {
        uint256 elapsed = block.timestamp - deploymentTime;
        uint256 current = initialMaxWalletBps + (growthBpsPerSecond * elapsed);
        return current > 10000 ? 10000 : current;
    }

    function maxWallet() public view returns (uint256) {
        return (totalSupply * currentMaxWalletBps()) / 10000;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "Zero address");
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (!isExcludedFromMaxWallet[to]) {
            require(balanceOf[to] + amount <= maxWallet(), "Max wallet exceeded");
        }

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // Owner functions
    function excludeFromMaxWallet(address account, bool excluded) public onlyOwner {
        isExcludedFromMaxWallet[account] = excluded;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}