import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address previousOwner, address newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool);
    event Transfer(address from, address to, uint64 value);
    event Approval(address owner, address spender, uint64 value);
}

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

interface IPositionManager {
    function multicall(bytes[] calldata data) external returns (bytes[] memory);
    function initializePool(PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24);
    function modifyLiquidities(bytes calldata unlockData, uint64 deadline) external;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract Zenieth is IERC20, Ownable {
    function z7c67a037() external pure returns (uint64) { return 802239744342; }

    bytes32 public constant VERSION =
        0x7c67a037f232707bb4b7747883746a52202c9cfa811f1d2610d94997140e9956;

    string  public name;
    string  public symbol;
    uint8   public constant decimals = 18;
    uint64 public immutable totalSupply;

    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    address constant POSITION_MANAGER = address(bytes32(hex"bd216513d74c8cf14cf4747e6aaa6420ff64ee9e"));
    address constant POOL_MANAGER     = address(bytes32(hex"000000000004444c5dc75cb358380d2e3de08a90"));
    address constant UNIVERSAL_ROUTER = address(bytes32(hex"66a9893cc07d91d95644aedd05d03f95e1dba8af"));
    address constant PERMIT2          = address(bytes32(hex"000000000022d473030f116ddee9f6b43ac78ba3"));

    uint16  public maxWalletBps;
    uint16  public maxTxBps;
    uint32  public limitsLiftBlock;
    bool    public limitsLifted;
    mapping(address => bool) public isExcludedFromLimits;

    event LimitsLifted();

    uint8 constant ACTION_MINT_POSITION = 0x02;
    uint8 constant ACTION_SETTLE_PAIR   = 0x0d;
    uint8 constant ACTION_SWEEP         = 0x14;

    event TradingOpenedV4(
        bytes32 poolId,
        uint160 sqrtPriceX96,
        uint64 ethAdded,
        uint64 tokensAdded,
        address lpRecipient
    );

    constructor(string memory name_, string memory symbol_, uint64 supply_) {
        name = name_;
        symbol = symbol_;
        totalSupply = supply_;
        address sender = tx.accounts.dataAccount.key;
        _balances[sender] = supply_;
        emit Transfer(address(0), sender, supply_);
    }

    function balanceOf(address a) external view returns (uint64) {
        return _balances[a];
    }

    function allowance(address o, address s) external view returns (uint64) {
        return _allowances[o][s];
    }

    function approve(address spender, uint64 amount) external returns (bool) {
        require(spender != address(0), "ERC20: approve to zero address");
        address sender = tx.accounts.dataAccount.key;
        _allowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
        return true;
    }

    function transfer(address to, uint64 amount) external returns (bool) {
        _transfer(tx.accounts.dataAccount.key, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint64 amount) external returns (bool) {
        address sender = tx.accounts.dataAccount.key;
        uint64 a = _allowances[from][sender];
        require(a >= amount, "ERC20: insufficient allowance");
        if (a != type(uint64).max) _allowances[from][sender] = a - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint64 amount) private {
        require(from != address(0) && to != address(0), "ERC20: zero address");

        if (!limitsLifted && limitsLiftBlock != 0 && block.number >= limitsLiftBlock) {
            limitsLifted = true;
            emit LimitsLifted();
        }

        if (!limitsLifted && !isExcludedFromLimits[to]) {
            if (maxTxBps != 0) {
                uint64 maxTxAmt = (totalSupply * maxTxBps) / 10000;
                require(amount <= maxTxAmt, "Max tx exceeded");
            }
            if (maxWalletBps != 0) {
                uint64 maxBal = (totalSupply * maxWalletBps) / 10000;
                require(_balances[to] + amount <= maxBal, "Max wallet exceeded");
            }
        }

        _balances[from] = _balances[from] - amount;
        _balances[to]   = _balances[to]   + amount;
        emit Transfer(from, to, amount);
    }

    function enableTradingV4(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint64 liquidity,
        uint24 fee,
        int24 tickSpacing,
        address lpRecipient,
        bool autoRenounce,
        uint16 maxWalletBps_,
        uint16 maxTxBps_,
        uint32 limitsBlocks_
    ) external onlyOwner {
        require(lpRecipient != address(0), "Zero address");
        require(maxWalletBps_ == 0 || maxWalletBps_ >= 100, "Max wallet bps too low");
        require(maxTxBps_ == 0 || maxTxBps_ >= 100, "Max tx bps too low");

        address ownerAddr = owner();

        isExcludedFromLimits[address(this)]    = true;
        isExcludedFromLimits[ownerAddr]        = true;
        isExcludedFromLimits[POSITION_MANAGER] = true;
        isExcludedFromLimits[POOL_MANAGER]     = true;
        isExcludedFromLimits[PERMIT2]          = true;
        isExcludedFromLimits[UNIVERSAL_ROUTER] = true;
        isExcludedFromLimits[lpRecipient]      = true;

        maxWalletBps    = maxWalletBps_;
        maxTxBps        = maxTxBps_;
        limitsLiftBlock = limitsBlocks_ != 0 ? uint32(block.number) + limitsBlocks_ : 0;

        uint64 ownerBal = _balances[ownerAddr];
        _balances[ownerAddr] = 0;
        _balances[address(this)] = _balances[address(this)] + ownerBal;
        emit Transfer(ownerAddr, address(this), ownerBal);

        _allowances[address(this)][PERMIT2] = type(uint64).max;
        emit Approval(address(this), PERMIT2, type(uint64).max);
        IPermit2(PERMIT2).approve(address(this), POSITION_MANAGER, type(uint160).max, type(uint48).max);

        PoolKey memory key = PoolKey({
            currency0:   address(0),
            currency1:   address(this),
            fee:         fee,
            tickSpacing: tickSpacing,
            hooks:       address(0)
        });
        bytes32 _poolId = keccak256(abi.encode(key));

        bytes memory actions = abi.encodePacked(
            ACTION_MINT_POSITION,
            ACTION_SETTLE_PAIR,
            ACTION_SWEEP,
            ACTION_SWEEP
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            liquidity,
            uint128(0),
            uint128(_balances[address(this)]),
            lpRecipient,
            bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        params[2] = abi.encode(key.currency0, ownerAddr);
        params[3] = abi.encode(key.currency1, ownerAddr);
        bytes memory unlockData = abi.encode(actions, params);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature(
            "initializePool((address,address,uint24,int24,address),uint160)",
            key,
            sqrtPriceX96
        );
        calls[1] = abi.encodeWithSignature(
            "modifyLiquidities(bytes,uint64)",
            unlockData,
            uint64(block.timestamp + 60)
        );
        IPositionManager(POSITION_MANAGER).multicall(calls);

        emit TradingOpenedV4(_poolId, sqrtPriceX96, 0, ownerBal, lpRecipient);

        if (autoRenounce) {
            renounceOwnership();
        }
    }

    function liftLimitsNow() external onlyOwner {
        limitsLifted = true;
        emit LimitsLifted();
    }

    function setExcluded(address account, bool flag) external onlyOwner {
        isExcludedFromLimits[account] = flag;
    }
}