// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
MemePerp
meme coins backed by live perp vaults
whitepaper v0.1 — May 2026

MemePerp is an Ethereum-native meme launch system where every coin can be paired with a live perpetual strategy. Each token launches as a fixed-supply ERC-20, trades through an on-chain liquidity pool, and can route a share of trading fees into a dedicated vault. That vault is used for perp collateral, buybacks, burns, and public strategy accounting.

The goal is simple: turn meme coin trading activity into an on-chain flywheel where fees can feed a live perp position, buybacks can reduce supply, and every major vault action can be verified.

1. Token

Each MemePerp launch creates a standard ERC-20 token on EVM.

Supply is fixed at creation. There is no mint function after deployment, no freeze function, no blacklist, no clawback, and no upgradeable proxy for the token contract.

The intended default supply is:

1,000,000,000 tokens

The token is designed to be simple, verifiable, and compatible with Ethereum wallets, DEX routers, explorers, and portfolio tools.

2. Launch pool

Trading begins through an Ethereum-native liquidity pool.

The preferred launch setup is a Uniswap v3 or Uniswap v4-style concentrated liquidity pool. Concentrated liquidity allows small initial liquidity to be placed around the active trading range instead of being spread across all possible prices.

For early launches, MemePerp can use a simple ERC-20 plus concentrated liquidity model. More advanced hook-based routing, dynamic fee capture, or automated treasury routing can be added later as production infrastructure matures.

3. Token vaults

Every launched token can receive its own vault.

The vault is the token’s on-chain treasury module. It can receive ETH or other supported assets, track fee reserves, fund buybacks, post perp collateral, and record strategy activity.

Funds from one token vault are not mixed with another token vault.

Each token’s public data can include:

token contract
liquidity pool
vault address
fee history
buyback history
burn history
perp strategy status

4. Market universe

At launch, the creator can select a market, side, and leverage tier.

Supported markets may include crypto majors, L1s, DeFi tokens, memecoins, indices, commodities, and FX-style synthetic markets, depending on available perp venue support.

Example markets:

BTC, ETH, SOL, BNB, XRP, DOGE, AVAX, LINK, AAVE, UNI, ARB, GMX, PEPE, SHIB, WIF, TSLA, NVDA, AAPL, SPY, XAU, WTI, EUR, GBP, and other supported markets.

Leverage tiers are split into:

Base: 2x, 3x, 5x
Degen: 10x, 25x, 50x, 100x where supported

A creator cannot select leverage that the execution venue rejects.

5. Perp routing

The keeper routes perpetual actions through supported EVM-compatible venues or off-chain execution systems.

The first implementation can target venues such as GMX-style perpetual markets or other EVM-accessible perp systems. The keeper compares venue support, collateral requirements, execution cost, available liquidity, and position safety before opening or topping up a position.

Each action can be recorded per token:

venue used
collateral deposited
market selected
side selected
leverage selected
position size
realized PnL
buyback amount
burn amount

If a venue, RPC, or API is unavailable, the keeper pauses new perp actions and continues recording pending balances.

6. Fee split

Every fee cycle can be split into three parts:

50% to perp collateral
Used to open or top up the token’s live perp position.

25% to buyback and burn
Accumulates in the vault. Once the reserve crosses the minimum execution threshold, the keeper swaps into the token and burns it on-chain.

25% to treasury reserve
Stays in the token vault for gas, execution runway, safety buffers, and future top-ups.

7. Keeper loop

The keeper processes each active token.

On every cycle, it can:

read pool activity
account for fees
update the token vault balance
apply the 50 / 25 / 25 split
check whether buyback reserve is above threshold
execute buyback and burn when viable
check perp position status
open, top up, or partially close the position
publish the latest token state

The keeper does not custody user wallets. Users trade normally through wallets and DEX interfaces.

8. Position lifecycle

Open
Once the token vault reaches the opening threshold, the keeper can open the selected perp position using the creator’s chosen market, side, and leverage.

Top up
Additional fee cycles can add collateral to the same strategy, subject to safety checks.

Take profit
When realized profit reaches the active profit-slice threshold, the keeper can close enough size to lock in that slice. Released funds can be swapped into the token and burned.

Losses
If the position moves against the token, the keeper does not burn from negative PnL. The fee-funded buyback stream can continue independently.

Liquidation safety
Before each top-up, the keeper checks effective leverage, collateral buffer, venue risk limits, and liquidation distance. If the top-up would increase risk too much, funds remain queued.

Permanence
The token’s perp strategy is intended to remain active for the life of the token, as long as supported venues and keeper infrastructure remain operational.

9. External tokens

MemePerp can also support tokens launched elsewhere.

A creator can connect an existing ERC-20, assign a vault, choose a market, side, and leverage, and route eligible fees or treasury deposits into the same keeper system.

External tokens should only appear as active once their vault has received real funds or produced a verifiable on-chain action.

10. Burn flywheel

Burns come from two independent paths:

Fee burns
Trading activity creates fees. A portion of those fees buys back the token and burns it.

Perp-profit burns
The vault’s perp strategy realizes profit. A slice of the profit buys back the token and burns it.

The first path can operate regardless of perp PnL. The second path adds upside when the selected perp strategy performs well.

11. What users can verify

Users can verify:

ERC-20 deployment
pool creation
vault address
fee inflows
buyback swaps
burn transactions
keeper actions
perp venue state where available
treasury balances
pending reserves

The system is designed so that token, pool, vault, and burn activity can be checked directly on-chain.

12. Current rollout status

MemePerp is being adapted for Ethereum/EVM.

Some contract addresses, keeper integrations, and venue routes may be marked as pending, staged, or prototype until they are fully deployed, verified, and connected to production keeper infrastructure.

No inactive contract address should be presented as a live production route. Production status is only assigned once the token, vault, pool, keeper, and venue integration are all verifiably active.

13. Risks

Leverage cuts both ways. A high-leverage strategy can be liquidated. Perp venues, RPC providers, DEX pools, keepers, bridges, and oracle systems are live dependencies. Outages or failed executions can pause claims, burns, top-ups, or position updates.

MemePerp does not remove market risk. It turns token activity into a transparent strategy loop: fees fund collateral, collateral powers a perp, profits can burn supply, and losses remain visible.
*/

contract MemePerpToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public immutable totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply_,
        address recipient_
    ) {
        if (recipient_ == address(0)) revert ZeroAddress();

        name = name_;
        symbol = symbol_;
        totalSupply = supply_;

        balanceOf[recipient_] = supply_;
        emit Transfer(address(0), recipient_, supply_);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
        }

        _transfer(from, to, amount);
        return true;
    }

    function burn(uint256 amount) external returns (bool) {
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[msg.sender] = bal - amount;
        }

        emit Transfer(msg.sender, address(0), amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }
}

contract MemePerpVault {
    address public immutable token;
    address public immutable creator;
    address public keeper;

    bytes32 public immutable marketId;
    int8 public immutable side; // 1 = long, -1 = short
    uint16 public immutable leverageBps; // 500 = 5x, 2500 = 25x, 10000 = 100x

    uint128 public perpReserve;
    uint128 public buybackReserve;
    uint128 public treasuryReserve;
    uint128 public totalFeesAccounted;

    uint128 public totalPerpSpent;
    uint128 public totalBuybackSpent;
    uint128 public totalTreasuryWithdrawn;
    uint128 public totalBurned;

    event FeesAccounted(uint256 amount, uint256 perpPart, uint256 buybackPart, uint256 treasuryPart);
    event BuybackReserveSpent(address indexed to, uint256 amount);
    event PerpReserveSpent(address indexed to, uint256 amount, bytes32 indexed actionId);
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event TokensBurned(uint256 amount);
    event PerpActionReported(bytes32 indexed actionId, int256 pnl, uint256 positionSize, string venue);
    event KeeperChanged(address indexed newKeeper);

    error ZeroAddress();
    error NotKeeper();
    error NotCreator();
    error BadSide();
    error AmountTooLarge();
    error InsufficientReserve();
    error EthTransferFailed();

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper();
        _;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    constructor(
        address token_,
        address creator_,
        address keeper_,
        bytes32 marketId_,
        int8 side_,
        uint16 leverageBps_
    ) {
        if (token_ == address(0) || creator_ == address(0) || keeper_ == address(0)) revert ZeroAddress();
        if (side_ != 1 && side_ != -1) revert BadSide();

        token = token_;
        creator = creator_;
        keeper = keeper_;
        marketId = marketId_;
        side = side_;
        leverageBps = leverageBps_;
    }

    receive() external payable {}

    function receiveFees() external payable {
        _split(msg.value);
    }

    function accountUnaccountedFees() external {
        uint256 amount = address(this).balance - accountedBalance();
        _split(amount);
    }

    function spendBuybackReserve(address payable to, uint128 amount) external onlyKeeper {
        if (to == address(0)) revert ZeroAddress();
        if (buybackReserve < amount) revert InsufficientReserve();

        unchecked {
            buybackReserve -= amount;
            totalBuybackSpent += amount;
        }

        _sendETH(to, amount);
        emit BuybackReserveSpent(to, amount);
    }

    function spendPerpReserve(address payable to, uint128 amount, bytes32 actionId) external onlyKeeper {
        if (to == address(0)) revert ZeroAddress();
        if (perpReserve < amount) revert InsufficientReserve();

        unchecked {
            perpReserve -= amount;
            totalPerpSpent += amount;
        }

        _sendETH(to, amount);
        emit PerpReserveSpent(to, amount, actionId);
    }

    function withdrawTreasury(address payable to, uint128 amount) external onlyCreator {
        if (to == address(0)) revert ZeroAddress();
        if (treasuryReserve < amount) revert InsufficientReserve();

        unchecked {
            treasuryReserve -= amount;
            totalTreasuryWithdrawn += amount;
        }

        _sendETH(to, amount);
        emit TreasuryWithdrawn(to, amount);
    }

    function burnHeld(uint128 amount) external onlyKeeper {
        MemePerpToken(token).burn(amount);

        unchecked {
            totalBurned += amount;
        }

        emit TokensBurned(amount);
    }

    function reportPerpAction(
        bytes32 actionId,
        int256 pnl,
        uint256 positionSize,
        string calldata venue
    ) external onlyKeeper {
        emit PerpActionReported(actionId, pnl, positionSize, venue);
    }

    function setKeeper(address newKeeper) external onlyCreator {
        if (newKeeper == address(0)) revert ZeroAddress();
        keeper = newKeeper;
        emit KeeperChanged(newKeeper);
    }

    function reserves() external view returns (uint128 perp, uint128 buyback, uint128 treasury) {
        return (perpReserve, buybackReserve, treasuryReserve);
    }

    function accountedBalance() public view returns (uint256) {
        return uint256(perpReserve) + uint256(buybackReserve) + uint256(treasuryReserve);
    }

    function _split(uint256 amount) internal {
        if (amount == 0) return;
        if (amount > type(uint128).max) revert AmountTooLarge();

        uint256 perpPart = amount / 2;
        uint256 buybackPart = amount / 4;
        uint256 treasuryPart = amount - perpPart - buybackPart;

        unchecked {
            perpReserve += uint128(perpPart);
            buybackReserve += uint128(buybackPart);
            treasuryReserve += uint128(treasuryPart);
            totalFeesAccounted += uint128(amount);
        }

        emit FeesAccounted(amount, perpPart, buybackPart, treasuryPart);
    }

    function _sendETH(address payable to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
    }
}

contract MemePerpFactory {
    address public owner;
    address public keeper;
    uint256 public launchCount;

    struct Launch {
        address token;
        address vault;
        address creator;
    }

    mapping(uint256 => Launch) public launches;

    event Launched(
        uint256 indexed launchId,
        address indexed creator,
        address token,
        address vault,
        bytes32 indexed marketId,
        int8 side,
        uint16 leverageBps
    );

    event OwnerChanged(address indexed newOwner);
    event KeeperChanged(address indexed newKeeper);

    error ZeroAddress();
    error NotOwner();
    error BadSupply();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address keeper_) {
        if (keeper_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        keeper = keeper_;
    }

    function launchToken(
        string calldata name_,
        string calldata symbol_,
        uint256 supply_,
        bytes32 marketId_,
        int8 side_,
        uint16 leverageBps_
    ) external returns (address token, address vault) {
        if (supply_ == 0) revert BadSupply();

        MemePerpToken t = new MemePerpToken(name_, symbol_, supply_, msg.sender);
        MemePerpVault v = new MemePerpVault(
            address(t),
            msg.sender,
            keeper,
            marketId_,
            side_,
            leverageBps_
        );

        token = address(t);
        vault = address(v);

        unchecked {
            launchCount++;
        }

        launches[launchCount] = Launch({token: token, vault: vault, creator: msg.sender});

        emit Launched(launchCount, msg.sender, token, vault, marketId_, side_, leverageBps_);
    }

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert ZeroAddress();
        keeper = newKeeper;
        emit KeeperChanged(newKeeper);
    }
}
