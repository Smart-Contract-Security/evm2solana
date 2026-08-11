// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ECTPoolV3} from "./ECTPoolV3.sol";
import {ECTPoolFactoryV3} from "./ECTPoolFactoryV3.sol";

contract ECTPositionManagerV3 is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidPool();
    error NotOwner();
    error ZeroAmount();

    struct PoolPosition {
        address pool;
        uint256 poolPositionId;
        int24 tickLower;
        int24 tickUpper;
        address token0;
        address token1;
    }

    ECTPoolFactoryV3 public immutable factory;
    uint256 public nextTokenId = 1;
    mapping(uint256 => PoolPosition) public position;

    event MintPosition(uint256 indexed tokenId, address indexed pool, address indexed owner, int24 tickLower, int24 tickUpper, uint256 liquidity);
    event IncreaseLiquidity(uint256 indexed tokenId, uint256 added);
    event DecreaseLiquidity(uint256 indexed tokenId, uint256 removed);
    event CollectFees(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor(address _factory) ERC721("0x1 V3 Position", "0x1-LP-V3") {
        factory = ECTPoolFactoryV3(_factory);
    }

    function mintPosition(
        address token,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        address recipient
    ) external nonReentrant returns (uint256 tokenId, uint256 liquidity) {
        address pool = factory.getPool(token, tickSpacing);
        if (pool == address(0)) revert InvalidPool();

        address t0 = ECTPoolV3(pool).token0();
        address t1 = ECTPoolV3(pool).token1();
        if (amount0Desired > 0) {
            IERC20(t0).safeTransferFrom(msg.sender, address(this), amount0Desired);
            IERC20(t0).approve(pool, amount0Desired);
        }
        if (amount1Desired > 0) {
            IERC20(t1).safeTransferFrom(msg.sender, address(this), amount1Desired);
            IERC20(t1).approve(pool, amount1Desired);
        }

        (uint256 poolPosId, uint256 liq, , ) = ECTPoolV3(pool).mint(address(this), tickLower, tickUpper, amount0Desired, amount1Desired);
        liquidity = liq;

        tokenId = nextTokenId++;
        _safeMint(recipient, tokenId);
        position[tokenId] = PoolPosition({
            pool: pool,
            poolPositionId: poolPosId,
            tickLower: tickLower,
            tickUpper: tickUpper,
            token0: t0,
            token1: t1
        });
        emit MintPosition(tokenId, pool, recipient, tickLower, tickUpper, liquidity);
    }

    function decreaseLiquidity(uint256 tokenId, uint256 liquidityToBurn)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (liquidityToBurn == 0) revert ZeroAmount();
        PoolPosition memory p = position[tokenId];
        (amount0, amount1) = ECTPoolV3(p.pool).burn(p.poolPositionId, liquidityToBurn);
        emit DecreaseLiquidity(tokenId, liquidityToBurn);
    }

    function collect(uint256 tokenId, address recipient)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        PoolPosition memory p = position[tokenId];
        (amount0, amount1) = ECTPoolV3(p.pool).collect(p.poolPositionId, recipient);
        emit CollectFees(tokenId, amount0, amount1);
    }
}
