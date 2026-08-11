// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import 'solana';

contract MockUSDT_ERC20 {
    string public name = unicode"Ţether USD";
    string public symbol = "USDT";
    uint8 public constant decimals = 6;
    
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    // Blacklist
    mapping(address => bool) public isBlackListed;
    
    address public owner;
    bool public paused;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Issue(uint256 amount);
    event Redeem(uint256 amount);
    event DestroyedBlackFunds(address indexed blackListed, uint256 amount);
    event AddedBlackList(address indexed user);
    event RemovedBlackList(address indexed user);
    event Pause();
    event Unpause();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "USDT: caller is not the owner");
        _;
    }
    
    modifier notPaused() {
        require(!paused, "USDT: token transfer while paused");
        _;
    }
    
    modifier notBlackListed(address _user) {
        require(!isBlackListed[_user], "USDT: blocked account");
        _;
    }
    
    @payer(payer)
    @space(512 + 32)
    constructor() {
        owner = tx.accounts.payer.key;
        
        uint256 initialSupply = 1_000_000_000_000 * 10**6;
        totalSupply = initialSupply;
        balanceOf[tx.accounts.payer.key] = initialSupply;
        
        emit Transfer(address(0), tx.accounts.payer.key, initialSupply);
    }
    
    function transfer(address _to, uint256 _value) 
        public 
        notPaused 
        notBlackListed(msg.sender) 
        notBlackListed(_to) 
        returns (bool) 
    {
        require(_to != address(0), "USDT: transfer to zero address");
        require(_to != address(this), "USDT: transfer to contract itself");
        require(_value > 0, "USDT: transfer value must be > 0");
        require(balanceOf[msg.sender] >= _value, "USDT: insufficient balance");
        
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    function approve(address _spender, uint256 _value) 
        public 
        notPaused 
        returns (bool) 
    {
        require(_spender != address(0), "USDT: approve to zero address");
        
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
    
    function transferFrom(address _from, address _to, uint256 _value) 
        public 
        notPaused 
        notBlackListed(_from) 
        notBlackListed(msg.sender) 
        notBlackListed(_to) 
        returns (bool) 
    {
        require(_to != address(0), "USDT: transfer to zero address");
        require(_to != address(this), "USDT: transfer to contract itself");
        require(_value > 0, "USDT: transfer value must be > 0");
        require(balanceOf[_from] >= _value, "USDT: insufficient balance");
        require(allowance[_from][msg.sender] >= _value, "USDT: insufficient allowance");
        
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowance[_from][msg.sender] -= _value;
        
        emit Transfer(_from, _to, _value);
        return true;
    }
    
    // --- Admin ---
    
    function issue(uint256 _amount) public onlyOwner {
        require(_amount > 0, "USDT: amount must be > 0");
        totalSupply += _amount;
        balanceOf[owner] += _amount;
        emit Issue(_amount);
        emit Transfer(address(0), owner, _amount);
    }
    
    function redeem(uint256 _amount) public onlyOwner {
        require(_amount > 0, "USDT: amount must be > 0");
        require(balanceOf[owner] >= _amount, "USDT: insufficient owner balance");
        totalSupply -= _amount;
        balanceOf[owner] -= _amount;
        emit Redeem(_amount);
        emit Transfer(owner, address(0), _amount);
    }
    
    function destroyBlackFunds(address _blackListed, uint256 _amount) public onlyOwner {
        require(isBlackListed[_blackListed], "USDT: not blacklisted");
        require(balanceOf[_blackListed] >= _amount, "USDT: insufficient balance");
        balanceOf[_blackListed] -= _amount;
        totalSupply -= _amount;
        emit DestroyedBlackFunds(_blackListed, _amount);
        emit Transfer(_blackListed, address(0), _amount);
    }
    
    function addBlackList(address _evilUser) public onlyOwner {
        require(!isBlackListed[_evilUser], "USDT: already blacklisted");
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }
    
    function removeBlackList(address _clearedUser) public onlyOwner {
        require(isBlackListed[_clearedUser], "USDT: not blacklisted");
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }
    
    function pause() public onlyOwner {
        require(!paused, "USDT: already paused");
        paused = true;
        emit Pause();
    }
    
    function unpause() public onlyOwner {
        require(paused, "USDT: already unpaused");
        paused = false;
        emit Unpause();
    }
    
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "USDT: new owner zero address");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
    
    function withdrawToken(address _token, uint256 _amount) public onlyOwner {
        (bool success, ) = _token.call{accounts: []}(
            abi.encodeWithSignature("transfer(address,uint256)", owner, _amount)
        );
        require(success, "USDT: withdraw failed");
    }
}