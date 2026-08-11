// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


contract SafexProTokenERC20 {
    string public name = "SafexPro";
    string public symbol = "USDS";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    address public owner;

    uint64 public constant EXPIRY_PERIOD = 90 days;
    uint64 internal constant NEVER = type(uint64).max;

    struct Lot {
        uint256 amount; // kolicina u ovom lotu
        uint64 expiry; // unix vreme kada lot istice (NEVER = nikad)
    }

    mapping(address => Lot[]) private _lots; // FIFO lotovi po adresi
    mapping(address => uint256) private _head; // indeks prvog nepotrosenog lota
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public isExempt; // adrese izuzete od isteka

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Expired(address indexed account, uint256 amount);
    event ExemptionSet(address indexed account, bool exempt);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Nije vlasnik");
        _;
    }

    constructor() {
        owner = msg.sender;
        isExempt[msg.sender] = true; // treasury vlasnika se ne gubi
        uint256 initialSupply = 1_200_000_000 * (10 ** uint256(decimals));
        totalSupply = initialSupply;
        _lots[msg.sender].push(Lot({amount: initialSupply, expiry: NEVER}));
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    // ----------------------------- VIEW -------------------------------------

    /// @notice Vraca SAMO neistekle tokene na adresi.
    function balanceOf(address account) public view returns (uint256 sum) {
        Lot[] storage lots = _lots[account];
        uint256 len = lots.length;
        for (uint256 i = _head[account]; i < len; i++) {
            if (lots[i].expiry > block.timestamp) {
                sum += lots[i].amount;
            }
        }
    }

    function allowance(address holder, address spender) external view returns (uint256) {
        return _allowances[holder][spender];
    }

    // --------------------------- MUTACIJE -----------------------------------

    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= value, "Nedovoljan allowance");
        if (allowed != type(uint256).max) {
            _allowances[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "Slanje na nulti naslov");
        _pruneExpired(from); // prvo pocisti istekle tokene posiljaoca
        require(_availableBalance(from) >= value, "Nedovoljno (ili istekli) tokeni");
        _consume(from, value); // potrosi FIFO
        _addLot(to, value); // primaocu se pravi novi lot sa rokom 90 dana
        emit Transfer(from, to, value);
    }

    function _availableBalance(address a) internal view returns (uint256 sum) {
        Lot[] storage lots = _lots[a];
        uint256 len = lots.length;
        for (uint256 i = _head[a]; i < len; i++) {
            if (lots[i].expiry > block.timestamp) {
                sum += lots[i].amount;
            }
        }
    }

    function _consume(address from, uint256 value) internal {
        Lot[] storage lots = _lots[from];
        uint256 i = _head[from];
        uint256 len = lots.length;
        uint256 remaining = value;
        while (remaining > 0 && i < len) {
            Lot storage lot = lots[i];
            if (lot.expiry <= block.timestamp) {
                i++;
                continue;
            }
            if (lot.amount <= remaining) {
                remaining -= lot.amount;
                lot.amount = 0;
                i++;
            } else {
                lot.amount -= remaining;
                remaining = 0;
            }
        }
        _head[from] = i;
        require(remaining == 0, "Greska u potrosnji lotova");
    }

    function _addLot(address to, uint256 value) internal {
        uint64 exp = isExempt[to] ? NEVER : uint64(block.timestamp) + EXPIRY_PERIOD;
        _lots[to].push(Lot({amount: value, expiry: exp}));
    }

    /// @dev Spaljuje istekle (prefiks) lotove i umanjuje totalSupply.
    function _pruneExpired(address a) internal {
        Lot[] storage lots = _lots[a];
        uint256 i = _head[a];
        uint256 len = lots.length;
        uint256 burned = 0;
        while (i < len && lots[i].expiry <= block.timestamp) {
            burned += lots[i].amount;
            lots[i].amount = 0;
            i++;
        }
        if (i != _head[a]) {
            _head[a] = i;
        }
        if (burned > 0) {
            totalSupply -= burned;
            emit Expired(a, burned);
            emit Transfer(a, address(0), burned); // izgleda kao burn u eksplorerima
        }
    }

    /// @notice Bilo ko moze da pokrene ciscenje isteklih tokena za adresu.
    function expire(address account) external {
        _pruneExpired(account);
    }

    // ----------------------------- ADMIN ------------------------------------

    function setExempt(address account, bool exempt) external onlyOwner {
        isExempt[account] = exempt;
        emit ExemptionSet(account, exempt);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Nulti vlasnik");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}