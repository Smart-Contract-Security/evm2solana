// SPDX-License-Identifier: MIT

import 'solana';

/**
 * @title MockUSDT_ERC20
 * @notice Token ERC20 identique à USDT (Ţether USD) pour audit
 * @dev 100 milliards de supply, decimals = 6, blacklist, pause, mint/burn
 */
contract MockUSDT_ERC20 {
    string public name = unicode"Ţether USD";
    string public symbol = "USDT";
    uint8 public constant decimals = 6;
    
    uint64 public totalSupply;
    
    mapping(address => uint64) public balanceOf;
    mapping(address => mapping(address => uint64)) public allowance;
    
    // Blacklist
    mapping(address => bool) public isBlackListed;
    
    address public owner;
    bool public paused;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event Issue(uint64 amount);
    event Redeem(uint64 amount);
    event DestroyedBlackFunds(address indexed blackListed, uint64 amount);
    event AddedBlackList(address indexed user);
    event RemovedBlackList(address indexed user);
    event Pause();
    event Unpause();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "USDT: caller is not the owner");
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
    
    /**
     * @dev 100 milliards USDT mintés au déployeur
     */
    @payer(payer)
    @space(512 + 1024)
    constructor(address payer) {
        owner = tx.accounts.dataAccount.key;
        
        uint64 initialSupply = 1000000000000000; // 1_000_000_000_000 * 10**6
        totalSupply = initialSupply;
        balanceOf[tx.accounts.dataAccount.key] = initialSupply;
        
        emit Transfer(address(0), tx.accounts.dataAccount.key, initialSupply);
    }
    
    function transfer(address _to, uint64 _value) 
        public 
        notPaused 
        notBlackListed(tx.accounts.dataAccount.key) 
        notBlackListed(_to) 
        returns (bool) 
    {
        require(_to != address(0), "USDT: transfer to zero address");
        require(_to != address(this), "USDT: transfer to contract itself");
        require(_value > 0, "USDT: transfer value must be > 0");
        require(balanceOf[tx.accounts.dataAccount.key] >= _value, "USDT: insufficient balance");
        
        balanceOf[tx.accounts.dataAccount.key] -= _value;
        balanceOf[_to] += _value;
        
        emit Transfer(tx.accounts.dataAccount.key, _to, _value);
        return true;
    }
    
    function approve(address _spender, uint64 _value) 
        public 
        notPaused 
        returns (bool) 
    {
        require(_spender != address(0), "USDT: approve to zero address");
        
        allowance[tx.accounts.dataAccount.key][_spender] = _value;
        emit Approval(tx.accounts.dataAccount.key, _spender, _value);
        return true;
    }
    
    function transferFrom(address _from, address _to, uint64 _value) 
        public 
        notPaused 
        notBlackListed(_from) 
        notBlackListed(tx.accounts.dataAccount.key) 
        notBlackListed(_to) 
        returns (bool) 
    {
        require(_to != address(0), "USDT: transfer to zero address");
        require(_to != address(this), "USDT: transfer to contract itself");
        require(_value > 0, "USDT: transfer value must be > 0");
        require(balanceOf[_from] >= _value, "USDT: insufficient balance");
        require(allowance[_from][tx.accounts.dataAccount.key] >= _value, "USDT: insufficient allowance");
        
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowance[_from][tx.accounts.dataAccount.key] -= _value;
        
        emit Transfer(_from, _to, _value);
        return true;
    }
    
    // --- Admin ---
    
    function issue(uint64 _amount) public onlyOwner {
        require(_amount > 0, "USDT: amount must be > 0");
        totalSupply += _amount;
        balanceOf[owner] += _amount;
        emit Issue(_amount);
        emit Transfer(address(0), owner, _amount);
    }
    
    function redeem(uint64 _amount) public onlyOwner {
        require(_amount > 0, "USDT: amount must be > 0");
        require(balanceOf[owner] >= _amount, "USDT: insufficient owner balance");
        totalSupply -= _amount;
        balanceOf[owner] -= _amount;
        emit Redeem(_amount);
        emit Transfer(owner, address(0), _amount);
    }
    
    function destroyBlackFunds(address _blackListed, uint64 _amount) public onlyOwner {
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
    
    function withdrawToken(address _token, uint64 _amount) public onlyOwner {
        AccountMeta[2] metas = [
            AccountMeta({pubkey: _token, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: owner, is_signer: false, is_writable: true})
        ];
        bytes data = abi.encodeWithSelector(0xa9059cbb, owner, _amount);
        _token.call{accounts: metas}(data);
    }
}