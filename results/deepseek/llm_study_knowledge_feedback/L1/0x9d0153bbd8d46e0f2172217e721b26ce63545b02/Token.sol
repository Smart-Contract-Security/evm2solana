import 'solana';

contract Token {
    mapping(address => uint64) public balances;
    mapping(address => mapping(address => uint64)) public allowance;
    uint64 public totalSupply = 1500000000000 * 10 ** 18;
    string public name = "Bondex";
    string public symbol = "BDXN";
    uint8 public decimals = 18;
    
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    
    @payer(payer)
    @space(512 + 512)
    constructor(address payer) {
        address dataAccount = tx.accounts.dataAccount.key;
        balances[dataAccount] = totalSupply;
    }
    
    function balanceOf(address owner) public view returns(uint64) {
        return balances[owner];
    }
    
    function transfer(address to, uint64 value) public returns(bool) {
        address dataAccount = tx.accounts.dataAccount.key;
        require(balanceOf(dataAccount) >= value, 'balance too low');
        balances[to] += value;
        balances[dataAccount] -= value;
        emit Transfer(dataAccount, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint64 value) public returns(bool) {
        address dataAccount = tx.accounts.dataAccount.key;
        require(balanceOf(from) >= value, 'balance too low');
        require(allowance[from][dataAccount] >= value, 'allowance too low');
        balances[to] += value;
        balances[from] -= value;
        emit Transfer(from, to, value);
        return true;   
    }
    
    function approve(address spender, uint64 value) public returns (bool) {
        address dataAccount = tx.accounts.dataAccount.key;
        allowance[dataAccount][spender] = value;
        emit Approval(dataAccount, spender, value);
        return true;   
    }
}