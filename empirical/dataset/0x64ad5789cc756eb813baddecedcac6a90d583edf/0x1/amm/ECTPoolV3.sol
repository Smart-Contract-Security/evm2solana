// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ECTPoolV3 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidTickRange();
    error InvalidTickSpacing();
    error InsufficientLiquidity();
    error InsufficientInput();
    error InsufficientOutput();
    error NotPositionOwner();
    error ZeroAmount();
    error K();

    uint256 public constant PROTOCOL_FEE_BPS = 150;            // 1.50%
    uint256 public constant PROTOCOL_FEE_TREASURY_BPS = 100;   // 1.00%
    uint256 public constant PROTOCOL_FEE_CREATOR_BPS  = 50;    // 0.50%
    uint256 public constant LP_FEE_BPS = 30;                   // 0.30%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable factory;
    address public token0;
    address public token1;
    address public treasury;
    address public creatorRecipient;
    int24 public tickSpacing;

    int24 public currentTick;
    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public feeGrowthGlobal0;
    uint256 public feeGrowthGlobal1;

    struct Position {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidity;
        uint256 feeGrowthInside0Last;
        uint256 feeGrowthInside1Last;
        uint256 tokensOwed0;
        uint256 tokensOwed1;
    }
    mapping(uint256 => Position) public positions;
    uint256 public nextPositionId = 1;

    mapping(int24 => uint256) public tickLiquidity;

    event Initialized(address token0, address token1, int24 tickSpacing, int24 startTick);
    event Mint(uint256 indexed positionId, address indexed owner, int24 tickLower, int24 tickUpper, uint256 liquidity, uint256 amount0, uint256 amount1);
    event Burn(uint256 indexed positionId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event Collect(uint256 indexed positionId, address recipient, uint256 amount0, uint256 amount1);
    event Swap(address indexed sender, address indexed recipient, bool zeroForOne, uint256 amountIn, uint256 amountOut, int24 newTick);
    event ProtocolFeePaid(address token, uint256 treasuryFee, uint256 creatorFee);

    constructor() {
        factory = msg.sender;
    }

    /// @notice One-shot init called by the factory.
    function initialize(
        address _token0,
        address _token1,
        address _treasury,
        int24 _tickSpacing,
        int24 _startTick
    ) external {
        if (msg.sender != factory) revert NotInitialized();
        if (token0 != address(0)) revert AlreadyInitialized();
        if (_tickSpacing <= 0) revert InvalidTickSpacing();
        token0 = _token0;
        token1 = _token1;
        treasury = _treasury;
        creatorRecipient = _treasury;
        tickSpacing = _tickSpacing;
        currentTick = _startTick;
        emit Initialized(_token0, _token1, _tickSpacing, _startTick);
    }

    function setCreatorRecipient(address newRecipient) external {
        require(msg.sender == factory, "ECTPoolV3: not factory");
        creatorRecipient = newRecipient == address(0) ? treasury : newRecipient;
    }

    /// @notice Mint a new concentrated-liquidity position.
    /// @param tickLower Lower bound of the position's price range (must be multiple of tickSpacing).
    /// @param tickUpper Upper bound (exclusive, must be > tickLower).
    /// @param amount0Desired Maximum token0 the caller will deposit.
    /// @param amount1Desired Maximum token1 the caller will deposit.
    /// @return positionId The new position's id.
    /// @return liquidity Liquidity units credited to the position.
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external nonReentrant returns (uint256 positionId, uint256 liquidity, uint256 amount0Used, uint256 amount1Used) {
        if (tickLower >= tickUpper) revert InvalidTickRange();
        if (tickLower % tickSpacing != 0 || tickUpper % tickSpacing != 0) revert InvalidTickRange();

        // Linear liquidity sum (no sqrt-price math).
        liquidity = amount0Desired + amount1Desired;
        if (liquidity == 0) revert ZeroAmount();
        amount0Used = amount0Desired;
        amount1Used = amount1Desired;

        if (amount0Used > 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0Used);
        if (amount1Used > 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1Used);
        reserve0 += amount0Used;
        reserve1 += amount1Used;

        positionId = nextPositionId++;
        positions[positionId] = Position({
            owner: recipient,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0Last: feeGrowthGlobal0,
            feeGrowthInside1Last: feeGrowthGlobal1,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        if (currentTick >= tickLower && currentTick < tickUpper) {
            tickLiquidity[tickLower] += liquidity;
        }

        emit Mint(positionId, recipient, tickLower, tickUpper, liquidity, amount0Used, amount1Used);
    }

    function burn(uint256 positionId, uint256 liquidityToBurn)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage pos = positions[positionId];
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (liquidityToBurn == 0 || liquidityToBurn > pos.liquidity) revert InsufficientLiquidity();

        // Pro-rata return from pool reserves.
        amount0 = (reserve0 * liquidityToBurn) / (reserve0 + reserve1 + 1);
        amount1 = (reserve1 * liquidityToBurn) / (reserve0 + reserve1 + 1);

        pos.liquidity -= liquidityToBurn;
        if (currentTick >= pos.tickLower && currentTick < pos.tickUpper) {
            tickLiquidity[pos.tickLower] -= liquidityToBurn;
        }

        _settleFees(pos);

        pos.tokensOwed0 += amount0;
        pos.tokensOwed1 += amount1;
        reserve0 -= amount0;
        reserve1 -= amount1;

        emit Burn(positionId, liquidityToBurn, amount0, amount1);
    }

    function collect(uint256 positionId, address recipient)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage pos = positions[positionId];
        if (pos.owner != msg.sender) revert NotPositionOwner();
        _settleFees(pos);
        amount0 = pos.tokensOwed0;
        amount1 = pos.tokensOwed1;
        pos.tokensOwed0 = 0;
        pos.tokensOwed1 = 0;
        if (amount0 > 0) IERC20(token0).safeTransfer(recipient, amount0);
        if (amount1 > 0) IERC20(token1).safeTransfer(recipient, amount1);
        emit Collect(positionId, recipient, amount0, amount1);
    }

    function _settleFees(Position storage pos) private {
        if (pos.liquidity == 0) return;
        uint256 delta0 = feeGrowthGlobal0 - pos.feeGrowthInside0Last;
        uint256 delta1 = feeGrowthGlobal1 - pos.feeGrowthInside1Last;
        pos.tokensOwed0 += (delta0 * pos.liquidity) / 1e18;
        pos.tokensOwed1 += (delta1 * pos.liquidity) / 1e18;
        pos.feeGrowthInside0Last = feeGrowthGlobal0;
        pos.feeGrowthInside1Last = feeGrowthGlobal1;
    }

    /// @notice Swap `amountIn` of one side for the other.
    /// @param  zeroForOne True if swapping token0 -> token1.
    /// @param  amountIn   Gross input amount (protocol fee deducted from this).
    /// @param  minAmountOut Reverts if the realized output is below this.
    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInput();
        address tokenIn = zeroForOne ? token0 : token1;
        address tokenOut = zeroForOne ? token1 : token0;

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 protocolTreasury = (amountIn * PROTOCOL_FEE_TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 protocolCreator = (amountIn * PROTOCOL_FEE_CREATOR_BPS) / BPS_DENOMINATOR;
        if (protocolTreasury > 0) IERC20(tokenIn).safeTransfer(treasury, protocolTreasury);
        if (protocolCreator > 0) IERC20(tokenIn).safeTransfer(creatorRecipient, protocolCreator);
        emit ProtocolFeePaid(tokenIn, protocolTreasury, protocolCreator);
        uint256 amountInPostProtocol = amountIn - protocolTreasury - protocolCreator;

        // LP fee accumulates into feeGrowthGlobal.
        uint256 lpFee = (amountInPostProtocol * LP_FEE_BPS) / BPS_DENOMINATOR;
        uint256 amountInForSwap = amountInPostProtocol - lpFee;

        uint256 rIn = zeroForOne ? reserve0 : reserve1;
        uint256 rOut = zeroForOne ? reserve1 : reserve0;
        if (rIn == 0 || rOut == 0) revert InsufficientLiquidity();
        amountOut = (amountInForSwap * rOut) / (rIn + amountInForSwap);
        if (amountOut < minAmountOut) revert InsufficientOutput();
        if (amountOut >= rOut) revert InsufficientLiquidity();

        if (zeroForOne) {
            reserve0 = rIn + amountInPostProtocol; // lpFee stays in reserves
            reserve1 = rOut - amountOut;
            currentTick = currentTick - tickSpacing;
            uint256 activeLiq = _activeLiquidityHere();
            if (activeLiq > 0) feeGrowthGlobal0 += (lpFee * 1e18) / activeLiq;
        } else {
            reserve1 = rIn + amountInPostProtocol;
            reserve0 = rOut - amountOut;
            currentTick = currentTick + tickSpacing;
            uint256 activeLiq = _activeLiquidityHere();
            if (activeLiq > 0) feeGrowthGlobal1 += (lpFee * 1e18) / activeLiq;
        }

        IERC20(tokenOut).safeTransfer(recipient, amountOut);
        emit Swap(msg.sender, recipient, zeroForOne, amountIn, amountOut, currentTick);
    }

    function _activeLiquidityHere() private view returns (uint256 total) {
        total = tickLiquidity[currentTick];
        if (total == 0) {
            int24 t = currentTick - tickSpacing;
            total = tickLiquidity[t];
        }
    }

    function getReserves() external view returns (uint256, uint256, int24) {
        return (reserve0, reserve1, currentTick);
    }

    function positionOf(uint256 id) external view returns (
        address owner, int24 tickLower, int24 tickUpper, uint256 liquidity,
        uint256 tokensOwed0, uint256 tokensOwed1
    ) {
        Position storage p = positions[id];
        return (p.owner, p.tickLower, p.tickUpper, p.liquidity, p.tokensOwed0, p.tokensOwed1);
    }
}
