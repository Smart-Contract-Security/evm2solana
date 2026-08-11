// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface MirrorFactory {
    function getPair(address a, address b) external view returns (address);
}

interface MirrorTreasuryLike {
    function bind(address owner, address token, address vault) external;
    function note(uint256 amount) external;
}

interface MirrorVaultLike { function bind(address token, address treasury) external; }
interface MirrorLedgerLike { function bind(address token) external; function reflect(uint256 amount, uint256 supply) external; function claim(address who, uint256 bal) external returns (uint256); }
interface MirrorClaimLike { function bind(address token) external; function mark(address who, uint256 amount) external; }
interface MirrorControllerLike { function bind(address token) external; function opened(address pair) external; }
interface MirrorGaugeLike { function bind(address token) external; function mark(uint256 amount) external; }

contract MirrorDividend {
    string public constant name = "Mirror Dividend";
    string public constant symbol = "MIRR";
    uint8 public constant decimals = 9;
    uint256 public totalSupply = 1_111_000_000 * 1e9;

    address public owner;
    address public factory;
    address public weth;
    address public pair;
    address public treasury;
    address public vault;
    address public ledger;
    address public claimBook;
    address public controller;
    address public gauge;
    bool public tradingOpen;
    uint256 public buyTax = 6;
    uint256 public sellTax = 8;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public noTax;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed holder, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    constructor(
        address factory_,
        address weth_,
        address owner_,
        address treasury_,
        address vault_,
        address ledger_,
        address claim_,
        address controller_,
        address gauge_
    ) {
        factory = factory_;
        weth = weth_;
        owner = owner_;
        treasury = treasury_;
        vault = vault_;
        ledger = ledger_;
        claimBook = claim_;
        controller = controller_;
        gauge = gauge_;
        noTax[owner_] = true;
        noTax[address(this)] = true;
        MirrorTreasuryLike(treasury_).bind(owner_, address(this), vault_);
        MirrorVaultLike(vault_).bind(address(this), treasury_);
        MirrorLedgerLike(ledger_).bind(address(this));
        MirrorClaimLike(claim_).bind(address(this));
        MirrorControllerLike(controller_).bind(address(this));
        MirrorGaugeLike(gauge_).bind(address(this));
        balanceOf[owner_] = totalSupply;
        emit OwnershipTransferred(address(0), owner_);
        emit Transfer(address(0), owner_, totalSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) {
            require(a >= amount, "allow");
            allowance[from][msg.sender] = a - amount;
        }
        _move(from, to, amount);
        return true;
    }

    function enableTrading() external onlyOwner {
        require(!tradingOpen, "live");
        pair = MirrorFactory(factory).getPair(address(this), weth);
        require(pair != address(0), "pair");
        tradingOpen = true;
        MirrorControllerLike(controller).opened(pair);
    }

    function setMirrorTax(uint256 buy, uint256 sell) external onlyOwner {
        require(buy <= 38 && sell <= 38, "cap");
        buyTax = buy;
        sellTax = sell;
    }

    function claimReflection() external {
        uint256 due = MirrorLedgerLike(ledger).claim(msg.sender, balanceOf[msg.sender]);
        uint256 pot = balanceOf[address(this)];
        if (due > pot) due = pot;
        if (due != 0) {
            _raw(address(this), msg.sender, due);
            MirrorClaimLike(claimBook).mark(msg.sender, due);
        }
    }

    function routeReflection(uint256 amount) external onlyOwner {
        uint256 use = amount == 0 ? balanceOf[address(this)] / 2 : amount;
        require(use <= balanceOf[address(this)], "bal");
        _raw(address(this), treasury, use);
        MirrorTreasuryLike(treasury).note(use);
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function _move(address from, address to, uint256 amount) private {
        require(to != address(0), "zero");
        if (!tradingOpen) require(from == owner || from == address(this), "closed");
        uint256 pct;
        if (tradingOpen && !noTax[from] && !noTax[to]) {
            if (from == pair) pct = buyTax;
            else if (to == pair) pct = sellTax;
        }
        uint256 fee = amount * pct / 100;
        uint256 net = amount - fee;
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += net;
            if (fee != 0) balanceOf[address(this)] += fee;
        }
        emit Transfer(from, to, net);
        if (fee != 0) {
            emit Transfer(from, address(this), fee);
            MirrorLedgerLike(ledger).reflect(fee, totalSupply);
            MirrorGaugeLike(gauge).mark(fee);
        }
    }

    function _raw(address from, address to, uint256 amount) private {
        balanceOf[from] -= amount;
        unchecked { balanceOf[to] += amount; }
        emit Transfer(from, to, amount);
    }
}
