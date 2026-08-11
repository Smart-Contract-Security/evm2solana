// SPDX-License-Identifier: MIT

// https://x.com/ProofMarkets     
// https://www.proof.trade/



pragma solidity ^0.8.21;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

contract Proof is IERC20 {
    string public constant name = "PROOF";
    string public constant symbol = "PROOF";
    uint8 public constant decimals = 18;

    uint256 public constant SUPPLY = 100_000_000;
    uint256 public constant totalSupply = SUPPLY * 1e18;

    // 0.15% of supply = 15 bps. Max transaction at launch.
    uint256 public constant DEFAULT_BPS = 15;
    uint256 public constant MIN_LIMIT_TOKENS = 100;

    // Starting market capitalisation target at the moment of creation (USD).
    uint256 public constant STARTING_MCAP_USD = 10_000;

    uint24 public constant POOL_FEE = 10000;
    int24 public constant TICK_SPACING = 200;
    int24 public constant MAX_USABLE_TICK = 887200;
    uint160 private constant MIN_SQRT_PLUS_ONE = 4295128740;
    uint160 private constant MAX_SQRT_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public creator;

    uint256 public maxTxn;
    bool public guarded = true;
    bool public proven;

    uint256 public proofId;
    address public pool;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    INonfungiblePositionManager public constant POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint256 private _lock = 1;

    event Proven(address indexed pool, uint256 tokenId, int24 tickLower, int24 tickUpper);
    event Attested(address indexed to, uint256 ethSpent, uint256 tokensReceived);
    event Finalized();
    event Calibrated(uint256 newMaxTxn);
    event Reclaimed(address indexed to, uint256 tokenId);
    event Harvested(address indexed to, uint256 amount0, uint256 amount1);
    event Succeeded(address indexed previousCreator, address indexed newCreator);

    error NotCreator();
    error AlreadyProven();
    error NotProvenYet();
    error SupplyTampered();
    error BadTick();
    error PriceMismatch();
    error LimitTooSmall();
    error LimitTooLarge();
    error AlreadyFinalized();
    error ZeroAddress();
    error Reentry();
    error Slippage();
    error RefundFailed();
    error BadCallback();
    error OnlyWETH();
    error EthTooLarge();

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    modifier instant() {
        if (_lock != 1) revert Reentry();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor() {
        creator = msg.sender;
        maxTxn = (totalSupply * DEFAULT_BPS) / 10_000;

        balanceOf[address(this)] = totalSupply;
        emit Transfer(address(0), address(this), totalSupply);
        emit Succeeded(address(0), msg.sender);
    }

    function limit() external view returns (uint256) {
        return maxTxn / 1e18;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _move(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "Insufficient allowance");
            unchecked { allowance[from][msg.sender] = allowed - amount; }
        }
        return _move(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal returns (bool) {
        require(to != address(0), "Zero to");
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (
            guarded &&
            from != creator &&
            to != creator &&
            from != address(this) &&
            to != address(this)
        ) {
            require(amount <= maxTxn, "Exceeds max txn");
        }

        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function prove(int24 startTick, uint160 sqrtPriceX96, uint256 minTokensOut)
        external
        payable
        onlyCreator
        instant
    {
        if (proven) revert AlreadyProven();
        if (balanceOf[address(this)] != totalSupply) revert SupplyTampered();
        if (startTick % TICK_SPACING != 0) revert BadTick();
        if (startTick <= -MAX_USABLE_TICK || startTick >= MAX_USABLE_TICK) revert BadTick();
        proven = true;

        bool isT0 = address(this) < WETH;
        int24 tickLower = isT0 ? startTick : -MAX_USABLE_TICK;
        int24 tickUpper = isT0 ? MAX_USABLE_TICK : startTick;

        address poolAddr = POSITION_MANAGER.createAndInitializePoolIfNecessary(
            isT0 ? address(this) : WETH,
            isT0 ? WETH : address(this),
            POOL_FEE,
            sqrtPriceX96
        );

        (uint160 livePrice, , , , , , ) = IUniswapV3Pool(poolAddr).slot0();
        if (livePrice != sqrtPriceX96) revert PriceMismatch();

        pool = poolAddr;

        allowance[address(this)][address(POSITION_MANAGER)] = totalSupply;
        emit Approval(address(this), address(POSITION_MANAGER), totalSupply);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: isT0 ? address(this) : WETH,
            token1: isT0 ? WETH : address(this),
            fee: POOL_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: isT0 ? totalSupply : 0,
            amount1Desired: isT0 ? 0 : totalSupply,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 600
        });

        (uint256 tokenId, , , ) = POSITION_MANAGER.mint(params);
        proofId = tokenId;

        allowance[address(this)][address(POSITION_MANAGER)] = 0;
        emit Approval(address(this), address(POSITION_MANAGER), 0);

        emit Proven(poolAddr, tokenId, tickLower, tickUpper);

        if (msg.value > 0) {
            _attest(isT0, minTokensOut);
        }
    }

    function _attest(bool isT0, uint256 minOut) internal {
        uint256 ethIn = msg.value;
        if (ethIn > uint256(type(int256).max)) revert EthTooLarge();

        IWETH9(WETH).deposit{value: ethIn}();

        bool zeroForOne = !isT0;
        uint160 priceLimit = zeroForOne ? MIN_SQRT_PLUS_ONE : MAX_SQRT_MINUS_ONE;

        address to = msg.sender;

        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            to,
            zeroForOne,
            int256(ethIn),
            priceLimit,
            ""
        );

        uint256 received = isT0 ? uint256(-amount0) : uint256(-amount1);
        if (received < minOut) revert Slippage();

        uint256 leftover = IERC20(WETH).balanceOf(address(this));
        uint256 spent = ethIn - leftover;
        if (leftover > 0) {
            IWETH9(WETH).withdraw(leftover);
            (bool ok, ) = to.call{value: leftover}("");
            if (!ok) revert RefundFailed();
        }

        emit Attested(to, spent, received);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        if (msg.sender != pool) revert BadCallback();
        uint256 owed = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        IERC20(WETH).transfer(msg.sender, owed);
    }

    receive() external payable {
        if (msg.sender != WETH) revert OnlyWETH();
    }

    function calibrate(uint256 newLimitInTokens) external onlyCreator {
        if (!guarded) revert AlreadyFinalized();
        if (newLimitInTokens < MIN_LIMIT_TOKENS) revert LimitTooSmall();
        if (newLimitInTokens > SUPPLY) revert LimitTooLarge();
        uint256 newLimitWei = newLimitInTokens * 1e18;
        maxTxn = newLimitWei;
        emit Calibrated(newLimitWei);
    }

    function finalize() external onlyCreator {
        if (!guarded) revert AlreadyFinalized();
        guarded = false;
        maxTxn = totalSupply;
        emit Finalized();
    }

    function reclaim(address to) external onlyCreator instant {
        if (proofId == 0) revert NotProvenYet();
        if (to == address(0)) revert ZeroAddress();

        uint256 id = proofId;
        proofId = 0;

        POSITION_MANAGER.safeTransferFrom(address(this), to, id);
        emit Reclaimed(to, id);
    }

    function harvest(address to)
        external
        onlyCreator
        instant
        returns (uint256 amount0, uint256 amount1)
    {
        if (proofId == 0) revert NotProvenYet();
        if (to == address(0)) revert ZeroAddress();

        (amount0, amount1) = POSITION_MANAGER.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: proofId,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit Harvested(to, amount0, amount1);
    }

    function succeed(address newCreator) external onlyCreator {
        if (newCreator == address(0)) revert ZeroAddress();
        address previous = creator;
        creator = newCreator;
        emit Succeeded(previous, newCreator);
    }

    function seal() external onlyCreator {
        if (!proven) revert NotProvenYet();
        address previous = creator;
        creator = address(0);
        emit Succeeded(previous, address(0));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }
}
