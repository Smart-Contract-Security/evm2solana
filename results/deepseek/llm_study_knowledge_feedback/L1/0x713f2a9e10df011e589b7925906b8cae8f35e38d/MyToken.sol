@program_id("11111111111111111111111111111111") // Placeholder, replace with actual program ID
contract MyToken {
    string public name = "Metalarge";
    string public symbol = "MTL";
    uint8 public decimals = 18;
    uint64 public totalSupply;

    mapping(address => uint64) public balanceOf;
    mapping(address => mapping(address => uint64)) public allowance;

    address public owner;

    @payer(payer)
    @space(2080)
    constructor(uint64 initialSupply, address payer) {
        owner = payer;
        totalSupply = initialSupply * (10 ** uint64(decimals));
        balanceOf[owner] = totalSupply;
        emit Transfer(address(0), owner, totalSupply);
    }

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    function transfer(address to, uint64 value) public returns (bool success) {
        address sender = tx.accounts.dataAccount.key;
        require(balanceOf[sender] >= value, "Insufficient balance");
        _transfer(sender, to, value);
        return true;
    }

    function _transfer(address from, address to, uint64 value) internal {
        require(to != address(0), "Invalid address");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint64 value) public returns (bool success) {
        address sender = tx.accounts.dataAccount.key;
        allowance[sender][spender] = value;
        emit Approval(sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) public returns (bool success) {
        address spender = tx.accounts.dataAccount.key;
        require(value <= balanceOf[from], "Insufficient balance");
        require(value <= allowance[from][spender], "Allowance exceeded");
        allowance[from][spender] -= value;
        _transfer(from, to, value);
        return true;
    }
}