// SPDX-License-Identifier: MIT
/*
AURORA PROTOCOL
The Luminescent Liquidity Protocol.
Hold longer during active markets. Earn more.
*/
pragma solidity ^0.8.24;

contract AuroraToken {

    string  public constant name     = "Aurora";
    string  public constant symbol   = "AURORA";
    uint8   public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 100_000_000e18;
    uint256 public totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    address public owner;
    bool    public tradingEnabled;

    mapping(address => bool) public isLimitless;
    mapping(address => bool) public isPair;

    uint256 public maxBuy    = (TOTAL_SUPPLY * 1) / 100;
    uint256 public maxWallet = (TOTAL_SUPPLY * 2) / 100;
    bool    public limitsActive = true;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed prev, address indexed next);
    event TradingEnabled();
    event PairSet(address indexed pair, bool status);
    event LimitlessSet(address indexed account, bool status);
    event LimitsLifted();

    error NotOwner();
    error AlreadyEnabled();
    error TradingNotEnabled();
    error MaxBuyExceeded();
    error MaxWalletExceeded();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error PermitExpired();
    error InvalidSignature();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256("1"),
            block.chainid,
            address(this)
        ));
        totalSupply           = TOTAL_SUPPLY;
        balanceOf[msg.sender] = TOTAL_SUPPLY;
        isLimitless[msg.sender]    = true;
        isLimitless[address(this)] = true;
        isLimitless[address(0)]    = true;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance();
            unchecked { allowance[from][msg.sender] = allowed - value; }
        }
        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function permit(
        address holder, address spender, uint256 value,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external {
        if (block.timestamp > deadline) revert PermitExpired();
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01", DOMAIN_SEPARATOR,
            keccak256(abi.encode(PERMIT_TYPEHASH, holder, spender, value, nonces[holder]++, deadline))
        ));
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0) || signer != holder) revert InvalidSignature();
        allowance[holder][spender] = value;
        emit Approval(holder, spender, value);
    }

    function burn(uint256 amount) external {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        unchecked { balanceOf[msg.sender] -= amount; totalSupply -= amount; }
        emit Transfer(msg.sender, address(0), amount);
    }

    function enableTrading() external onlyOwner {
        if (tradingEnabled) revert AlreadyEnabled();
        tradingEnabled = true;
        emit TradingEnabled();
    }

    function setPair(address pair, bool status) external onlyOwner {
        isPair[pair]      = status;
        isLimitless[pair] = status;
        emit PairSet(pair, status);
    }

    function setLimitless(address account, bool status) external onlyOwner {
        isLimitless[account] = status;
        emit LimitlessSet(account, status);
    }

    function liftLimits() external onlyOwner {
        limitsActive = false;
        maxBuy    = type(uint256).max;
        maxWallet = type(uint256).max;
        emit LimitsLifted();
    }

    function transferOwnership(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, next);
        owner = next;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (balanceOf[from] < value) revert InsufficientBalance();
        if (!tradingEnabled && !isLimitless[from] && !isLimitless[to]) revert TradingNotEnabled();
        if (limitsActive && tradingEnabled) {
            if (isPair[from] && !isLimitless[to]) {
                if (value > maxBuy) revert MaxBuyExceeded();
            }
            if (!isLimitless[to] && !isPair[to]) {
                if (balanceOf[to] + value > maxWallet) revert MaxWalletExceeded();
            }
        }
        unchecked { balanceOf[from] -= value; balanceOf[to] += value; }
        emit Transfer(from, to, value);
    }
}
