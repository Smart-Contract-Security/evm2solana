import 'solana';

contract UnisToken {
    string public constant name     = "UNIS";
    string public constant symbol   = "UNIS";
    uint8  public constant decimals = 18;

    uint64 public constant SUPPLY = 100000000000000000000000000;
    uint64 public totalSupply = SUPPLY;

    mapping(address => uint64) public balanceOf;
    mapping(address => mapping(address => uint64)) public allowance;

    address public admin;
    address public treasury;
    bool    public live;

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed holder, address indexed spender, uint64 value);
    event Incinerated(address indexed from, uint64 amount);
    event Ignited(uint64 atTimestamp);
    event TreasurySet(address indexed prev, address indexed next);
    event AdminPassed(address indexed prev, address indexed next);
    event EthSwept(address indexed to, uint64 amount);

    modifier onlyAdmin() { 
        if (tx.accounts.dataAccount.key != admin) {
            revert("NotAdmin");
        }
        _; 
    }

    @payer(payer)
    @space(512 + 32)
    @seed("unis_token")
    constructor(address payer) {
        admin = tx.accounts.dataAccount.key;
        balanceOf[tx.accounts.dataAccount.key] = SUPPLY;
        emit Transfer(address(0), tx.accounts.dataAccount.key, SUPPLY);
    }

    function approve(address spender, uint64 value) external returns (bool) {
        allowance[tx.accounts.dataAccount.key][spender] = value;
        emit Approval(tx.accounts.dataAccount.key, spender, value);
        return true;
    }

    function transfer(address to, uint64 value) external returns (bool) {
        _move(tx.accounts.dataAccount.key, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) external returns (bool) {
        uint64 a = allowance[from][tx.accounts.dataAccount.key];
        if (a != type(uint64).max) {
            if (a < value) {
                revert("InsufficientAllowance");
            }
            unchecked { allowance[from][tx.accounts.dataAccount.key] = a - value; }
        }
        _move(from, to, value);
        return true;
    }

    function _move(address from, address to, uint64 value) internal {
        if (to == address(0)) {
            revert("ZeroAddress");
        }
        if (balanceOf[from] < value) {
            revert("InsufficientBalance");
        }
        if (!live && from != admin && to != admin) {
            revert("NotLive");
        }
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to]   += value;
        }
        emit Transfer(from, to, value);
    }

    function incinerate(uint64 value) external {
        if (balanceOf[tx.accounts.dataAccount.key] < value) {
            revert("InsufficientBalance");
        }
        unchecked {
            balanceOf[tx.accounts.dataAccount.key] -= value;
            totalSupply -= value;
        }
        emit Transfer(tx.accounts.dataAccount.key, address(0), value);
        emit Incinerated(tx.accounts.dataAccount.key, value);
    }

    function setTreasury(address t) external onlyAdmin {
        if (t == address(0)) {
            revert("ZeroAddress");
        }
        emit TreasurySet(treasury, t);
        treasury = t;
    }

    @account(clockAccount)
    function ignite() external onlyAdmin {
        if (live) {
            revert("AlreadyLive");
        }
        live = true;
        emit Ignited(uint64(block.timestamp));
    }

    function sweepEth(address to, uint64 amount) external onlyAdmin {
        if (to == address(0)) {
            revert("ZeroAddress");
        }
        AccountInfo account = tx.accounts.dataAccount;
        uint64 balance = account.lamports;
        if (balance < amount) {
            revert("InsufficientBalance");
        }
        account.lamports -= amount;
        AccountInfo toAccount = getAccountInfo(to);
        toAccount.lamports += amount;
        emit EthSwept(to, amount);
    }

    function passAdmin(address next) external onlyAdmin {
        if (next == address(0)) {
            revert("ZeroAddress");
        }
        emit AdminPassed(admin, next);
        admin = next;
    }

    function cedeAdmin() external onlyAdmin {
        emit AdminPassed(admin, address(0));
        admin = address(0);
    }

    function getAccountInfo(address addr) private view returns (AccountInfo) {
        AccountInfo info = tx.accounts.dataAccount;
        return info;
    }
}