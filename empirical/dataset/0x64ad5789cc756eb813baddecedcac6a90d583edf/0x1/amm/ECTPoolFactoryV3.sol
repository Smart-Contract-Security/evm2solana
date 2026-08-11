// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ECTPoolV3} from "./ECTPoolV3.sol";

contract ECTPoolFactoryV3 is Ownable2Step {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error IdenticalTokens();
    error PoolExists();
    error InvalidTickSpacing();

    uint256 public constant PAIR_CREATION_FEE = 100 * 1e18;

    IERC20 public immutable ect;
    address public treasury;

    mapping(int24 => bool) public allowedTickSpacing;

    /// @dev pool[tokenA][tokenB][tickSpacing] = poolAddress; lookup is symmetric.
    mapping(address => mapping(address => mapping(int24 => address))) internal _getPoolPair;
    /// @dev Single-token lookup for ECT-paired pools: pool[token][tickSpacing].
    mapping(address => mapping(int24 => address)) public getPool;
    address[] public allPools;

    mapping(address => address) public tokenCreator;

    event PoolCreated(address indexed tokenA, address indexed tokenB, int24 tickSpacing, address pool, int24 startTick);
    event TickSpacingAllowed(int24 tickSpacing, bool allowed);

    constructor(address initialOwner, address _ect, address _treasury) Ownable(initialOwner) {
        if (_ect == address(0) || _treasury == address(0)) revert ZeroAddress();
        ect = IERC20(_ect);
        treasury = _treasury;
        allowedTickSpacing[1] = true;
        allowedTickSpacing[10] = true;
        allowedTickSpacing[60] = true;
        allowedTickSpacing[200] = true;
        emit TickSpacingAllowed(1, true);
        emit TickSpacingAllowed(10, true);
        emit TickSpacingAllowed(60, true);
        emit TickSpacingAllowed(200, true);
    }

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function setTickSpacing(int24 spacing, bool allowed) external onlyOwner {
        if (spacing <= 0) revert InvalidTickSpacing();
        allowedTickSpacing[spacing] = allowed;
        emit TickSpacingAllowed(spacing, allowed);
    }

    /// @notice Register a token's creator for routing the creator fee.
    function registerTokenCreator(address token, address creator) external onlyOwner {
        tokenCreator[token] = creator;
    }

    /// @notice Create an ECT / token pool.
    function createPool(address token, int24 tickSpacing, int24 startTick) external returns (address pool) {
        return _createPoolInternal(address(ect), token, tickSpacing, startTick);
    }

    /// @notice Create a pool between any two tokens.
    function createPoolPair(address tokenA, address tokenB, int24 tickSpacing, int24 startTick) external returns (address pool) {
        return _createPoolInternal(tokenA, tokenB, tickSpacing, startTick);
    }

    function _createPoolInternal(address tokenA, address tokenB, int24 tickSpacing, int24 startTick) internal returns (address pool) {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        if (tokenA == tokenB) revert IdenticalTokens();
        if (!allowedTickSpacing[tickSpacing]) revert InvalidTickSpacing();
        if (startTick % tickSpacing != 0) revert InvalidTickSpacing();
        if (_getPoolPair[tokenA][tokenB][tickSpacing] != address(0)) revert PoolExists();

        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        ect.safeTransferFrom(msg.sender, treasury, PAIR_CREATION_FEE);

        ECTPoolV3 newPool = new ECTPoolV3();
        newPool.initialize(t0, t1, treasury, tickSpacing, startTick);
        address nonEct = tokenA == address(ect) ? tokenB : tokenA;
        address creator = tokenCreator[nonEct];
        if (creator != address(0)) newPool.setCreatorRecipient(creator);

        pool = address(newPool);
        _getPoolPair[tokenA][tokenB][tickSpacing] = pool;
        _getPoolPair[tokenB][tokenA][tickSpacing] = pool;
        if (tokenA == address(ect)) getPool[tokenB][tickSpacing] = pool;
        else if (tokenB == address(ect)) getPool[tokenA][tickSpacing] = pool;
        allPools.push(pool);
        emit PoolCreated(tokenA, tokenB, tickSpacing, pool, startTick);
    }

    /// @notice Symmetric lookup for any-to-any pools.
    function getPoolPair(address tokenA, address tokenB, int24 tickSpacing) external view returns (address) {
        return _getPoolPair[tokenA][tokenB][tickSpacing];
    }
}
