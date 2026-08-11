// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGateRouter {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[] calldata,address,uint256) external;
}

interface IGateV2Factory {
    function getPair(address, address) external view returns (address);
}

contract GateLedger {
    string public constant name = "Gate Ledger";
    string public constant symbol = "GLED";
    uint8 public constant decimals = 9;
    uint256 public totalSupply = 930_000_000 * 10 ** 9;

    mapping(address => uint256) private lot;
    mapping(address => mapping(address => uint256)) private book;
    mapping(address => bool) public untaxed;
    mapping(address => bool) public isBot;
    mapping(address => uint256) public firstBlock;

    address public owner;
    address public router;
    address public factoryTrail;
    address public pair;
    bool public live;
    bool private seedDone;
    uint256 public buyFee = 16;
    uint256 public sellFee = 19;
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event TradingEnabled(address indexed pair);
    event BotMarked(address indexed who, bool yes);

    constructor(address router_, address owner_, address factoryTrail_) {
        owner = owner_;
        router = router_;
        factoryTrail = factoryTrail_;
        maxTxAmount = totalSupply * 18 / 1000;
        maxWalletAmount = totalSupply * 34 / 1000;
        untaxed[owner_] = true;
        untaxed[address(this)] = true;
        untaxed[router_] = true;
        untaxed[factoryTrail_] = true;
        lot[owner_] = totalSupply;
        emit OwnershipTransferred(address(0), owner_);
        emit Transfer(address(0), owner_, totalSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    function balanceOf(address who) external view returns (uint256) { return lot[who]; }
    function allowance(address from, address spender) external view returns (uint256) { return book[from][spender]; }

    function approve(address spender, uint256 amount) external returns (bool) {
        book[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _record(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = book[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            unchecked { book[from][msg.sender] = allowed - amount; }
        }
        _record(from, to, amount);
        return true;
    }

    function _record(address from, address to, uint256 amount) private {
        require(from != address(0) && to != address(0), "zero");
        require(!isBot[from] && !isBot[to], "bot");
        uint256 moved = amount;

        if (!live) {
            IGateRouter r = IGateRouter(router);
            address maybePair = IGateV2Factory(r.factory()).getPair(address(this), r.WETH());
            if (!seedDone && from == owner && to == maybePair && maybePair != address(0)) {
                pair = maybePair;
                moved = amount * 30 / 100;
                seedDone = true;
            } else if (from != owner && from != address(this)) {
                revert("closed");
            }
        }

        uint256 fee;
        if (live && pair != address(0) && !untaxed[from] && !untaxed[to]) {
            if (from == pair) {
                require(moved <= maxTxAmount, "max");
                fee = moved * buyFee / 100;
                uint256 got = moved - fee;
                require(lot[to] + got <= maxWalletAmount, "wallet");
                firstBlock[to] = block.number;
            } else if (to == pair) {
                require(moved <= maxTxAmount, "max");
                fee = moved * sellFee / 100;
            }
        }

        lot[from] -= moved;
        uint256 net = moved - fee;
        lot[to] += net;
        emit Transfer(from, to, net);
        if (fee != 0) {
            lot[address(this)] += fee;
            emit Transfer(from, address(this), fee);
        }
    }

    function enableTrading() external onlyOwner {
        require(!live, "live");
        IGateRouter r = IGateRouter(router);
        pair = IGateV2Factory(r.factory()).getPair(address(this), r.WETH());
        require(pair != address(0), "pair");
        live = true;
        emit TradingEnabled(pair);
    }

    function setGateTax(uint256 buy, uint256 sell) external onlyOwner {
        require(buy <= 38 && sell <= 38, "tax");
        buyFee = buy;
        sellFee = sell;
    }

    function setGateLimits(uint256 maxTxRaw, uint256 maxWalletRaw) external onlyOwner {
        require(maxTxRaw >= totalSupply / 200 && maxWalletRaw >= totalSupply / 200, "floor");
        maxTxAmount = maxTxRaw;
        maxWalletAmount = maxWalletRaw;
    }

    function markBot(address who, bool yes) external onlyOwner {
        require(!live, "live");
        isBot[who] = yes;
        emit BotMarked(who, yes);
    }

    function flushGate(uint256 amount, uint256 minOut) external onlyOwner {
        uint256 use = amount == 0 ? lot[address(this)] : amount;
        require(use > 0 && use <= lot[address(this)], "empty");
        book[address(this)][router] = use;
        emit Approval(address(this), router, use);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IGateRouter(router).WETH();
        IGateRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(use, minOut, path, owner, block.timestamp);
    }

    function transferOwnership(address next) external onlyOwner {
        require(next != address(0), "zero");
        emit OwnershipTransferred(owner, next);
        owner = next;
        untaxed[next] = true;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    receive() external payable {}
}
