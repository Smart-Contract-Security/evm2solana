// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**

 
https://x.com/i/status/2060706832461484035






 */
contract Token {

    // ─── Uniswap V4 — Ethereum Mainnet ────────────────────────────────────────
    // docs.uniswap.org/contracts/v4/deployments

    address private constant V4_POOL_MANAGER     = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant V4_UNIVERSAL_ROUTER  = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address private constant PERMIT2             = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ─── ERC-20 state ─────────────────────────────────────────────────────────

    string  public name;
    string  public symbol;
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256)                     private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ─── Ownership ────────────────────────────────────────────────────────────

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ─── Max wallet ───────────────────────────────────────────────────────────

    uint256 public startingMaxWalletBps;
    uint256 public growthBpsPerSecond;
    uint256 public deployedAt;

    mapping(address => bool) public isExempt;

    // ─── Events ───────────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ExemptUpdated(address indexed account, bool exempt);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _name                 Token name
     * @param _symbol               Token symbol
     * @param _totalSupply          Total supply in whole tokens (e.g. 1_000_000)
     * @param _startingMaxWalletBps Starting max wallet in bps  (e.g. 100 = 1%)
     * @param _growthBpsPerSecond   Bps growth per second       (e.g. 1 = 0.01%/s)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256       _totalSupply,
        uint256       _startingMaxWalletBps,
        uint256       _growthBpsPerSecond
    ) {
        require(_startingMaxWalletBps > 0 && _startingMaxWalletBps <= 10_000, "Invalid bps");

        name   = _name;
        symbol = _symbol;
        owner  = msg.sender;

        startingMaxWalletBps = _startingMaxWalletBps;
        growthBpsPerSecond   = _growthBpsPerSecond;
        deployedAt           = block.timestamp;

        uint256 supply        = _totalSupply * (10 ** decimals);
        totalSupply           = supply;
        _balances[msg.sender] = supply;

        // ── Baked-in exemptions ──────────────────────────────────────────────
        // Uniswap V4: PoolManager is the singleton vault — must be exempt.
        // PositionManager + Universal Router may transiently receive tokens.
        // Permit2 handles allowance routing.
        isExempt[V4_POOL_MANAGER]     = true;
        isExempt[V4_POSITION_MANAGER] = true;
        isExempt[V4_UNIVERSAL_ROUTER]  = true;
        isExempt[PERMIT2]             = true;

        // Deployer and this contract are also exempt
        isExempt[msg.sender]    = true;
        isExempt[address(this)] = true;

        emit Transfer(address(0), msg.sender, supply);
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Max wallet views ─────────────────────────────────────────────────────

    /// @notice Current max wallet in bps (capped at 10 000 = 100%).
    function currentMaxWalletBps() public view returns (uint256) {
        uint256 elapsed = block.timestamp - deployedAt;
        uint256 grown   = startingMaxWalletBps + (growthBpsPerSecond * elapsed);
        return grown > 10_000 ? 10_000 : grown;
    }

    /// @notice Current max wallet in raw token units (18 decimals).
    function currentMaxWallet() public view returns (uint256) {
        return (totalSupply * currentMaxWalletBps()) / 10_000;
    }

    // ─── Owner functions ─────────────────────────────────────────────────────
    // These all become permanently uncallable after renounceOwnership().

    /// @notice Exempt (or un-exempt) any address from the max wallet check.
    ///         Useful for adding aggregators or vesting contracts pre-renounce.
    function setExempt(address account, bool exempt) external onlyOwner {
        isExempt[account] = exempt;
        emit ExemptUpdated(account, exempt);
    }

    /// @notice Permanently renounce ownership. Cannot be undone.
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /// @notice Hand ownership to a new address.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        isExempt[newOwner] = true;
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ─── ERC-20 ───────────────────────────────────────────────────────────────

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address _owner, address spender) external view returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= amount, "Allowance exceeded");
        unchecked { _allowances[from][msg.sender] = allowed - amount; }
        _transfer(from, to, amount);
        return true;
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "Zero address");
        require(_balances[from] >= amount, "Insufficient balance");

        if (!isExempt[to]) {
            require(
                _balances[to] + amount <= currentMaxWallet(),
                "Exceeds max wallet"
            );
        }

        unchecked {
            _balances[from] -= amount;
            _balances[to]   += amount;
        }

        emit Transfer(from, to, amount);
    }
}
