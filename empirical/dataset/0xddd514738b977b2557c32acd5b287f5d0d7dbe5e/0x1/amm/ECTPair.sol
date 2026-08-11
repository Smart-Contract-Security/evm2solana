// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IECTPair} from "../interfaces/IECTPair.sol";

contract ECTPair is ERC20, IECTPair {
    using SafeERC20 for IERC20;

    /// @notice Minimum liquidity locked at first mint.
    uint256 public constant override MINIMUM_LIQUIDITY = 1000;

    uint256 public constant PROTOCOL_FEE_TREASURY_BPS = 100; // 1.00%
    uint256 public constant PROTOCOL_FEE_CREATOR_BPS  = 50;  // 0.50%
    uint256 public constant PROTOCOL_FEE_TOTAL_BPS    = 150; // 1.50%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable override factory;
    address public override token0;
    address public override token1;
    address public override treasury;
    address public override creatorRecipient;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;

    bool private _unlocked = true;

    error Locked();
    error Forbidden();
    error AlreadyInitialized();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();
    error InvalidTo();
    error InsufficientInputAmount();
    error K();
    error Overflow();

    modifier lock() {
        if (!_unlocked) revert Locked();
        _unlocked = false;
        _;
        _unlocked = true;
    }

    constructor() ERC20("0x1 LP", "0x1-LP") {
        factory = msg.sender;
    }

    /// @inheritdoc IECTPair
    function initialize(address _token0, address _token1, address _treasury) external override {
        if (msg.sender != factory) revert Forbidden();
        if (token0 != address(0)) revert AlreadyInitialized();
        token0 = _token0;
        token1 = _token1;
        treasury = _treasury;
        creatorRecipient = _treasury;
    }

    /// @inheritdoc IECTPair
    function setCreatorRecipient(address newRecipient) external override {
        if (msg.sender != factory) revert Forbidden();
        require(newRecipient != address(0), "ECTPair: zero recipient");
        creatorRecipient = newRecipient;
        emit CreatorRecipientUpdated(newRecipient);
    }

    /// @inheritdoc IECTPair
    function getReserves()
        public
        view
        override
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = _blockTimestampLast;
    }

    function _update(uint256 balance0, uint256 balance1, uint112 reserve0, uint112 reserve1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - _blockTimestampLast; // wraps OK
            if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
                // price0 = reserve1 * 2^112 / reserve0 (UQ112x112)
                price0CumulativeLast += (uint256(reserve1) << 112) / reserve0 * timeElapsed;
                price1CumulativeLast += (uint256(reserve0) << 112) / reserve1 * timeElapsed;
            }
        }
        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = blockTimestamp;
        emit Sync(_reserve0, _reserve1);
    }

    /// @inheritdoc IECTPair
    /// @notice Adds liquidity. Caller must pre-fund the pair with both tokens.
    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        uint256 supply = totalSupply();
        if (supply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // permanent burn
        } else {
            liquidity = Math.min((amount0 * supply) / reserve0, (amount1 * supply) / reserve1);
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1, reserve0, reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @inheritdoc IECTPair
    /// @notice Removes liquidity. Caller must have transferred LP tokens to this pair.
    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 supply = totalSupply();
        amount0 = (liquidity * balance0) / supply;
        amount1 = (liquidity * balance1) / supply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, reserve0, reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @inheritdoc IECTPair
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        override
        lock
    {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        if (amount0Out >= reserve0 || amount1Out >= reserve1) revert InsufficientLiquidity();

        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            if (to == _token0 || to == _token1) revert InvalidTo();
            if (amount0Out > 0) IERC20(_token0).safeTransfer(to, amount0Out);
            if (amount1Out > 0) IERC20(_token1).safeTransfer(to, amount1Out);
            if (data.length > 0) {
                // Flash-swap callback signature (callers must implement on `to`).
                (bool ok,) = to.call(
                    abi.encodeWithSignature(
                        "uniswapV2Call(address,uint256,uint256,bytes)",
                        msg.sender,
                        amount0Out,
                        amount1Out,
                        data
                    )
                );
                require(ok, "ECTPair: flash callback failed");
            }
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // Pull protocol fee from each input side that was credited.
        if (amount0In > 0) {
            (uint256 treasuryFee, uint256 creatorFee) = _payProtocolFee(token0, amount0In);
            unchecked {
                amount0In -= (treasuryFee + creatorFee);
                balance0 -= (treasuryFee + creatorFee);
            }
        }
        if (amount1In > 0) {
            (uint256 treasuryFee, uint256 creatorFee) = _payProtocolFee(token1, amount1In);
            unchecked {
                amount1In -= (treasuryFee + creatorFee);
                balance1 -= (treasuryFee + creatorFee);
            }
        }

        // K invariant (post-protocol-fee, 0.3% LP fee applied via *3):
        //   balanceAdjusted = balance * 1000 - amountIn * 3
        // ensures balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1_000_000.
        {
            uint256 balance0Adj = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adj = balance1 * 1000 - amount1In * 3;
            if (balance0Adj * balance1Adj < uint256(reserve0) * uint256(reserve1) * 1_000_000) {
                revert K();
            }
        }

        _update(balance0, balance1, reserve0, reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _payProtocolFee(address token, uint256 grossIn)
        private
        returns (uint256 treasuryFee, uint256 creatorFee)
    {
        treasuryFee = (grossIn * PROTOCOL_FEE_TREASURY_BPS) / BPS_DENOMINATOR;
        creatorFee = (grossIn * PROTOCOL_FEE_CREATOR_BPS) / BPS_DENOMINATOR;
        if (treasuryFee > 0) IERC20(token).safeTransfer(treasury, treasuryFee);
        if (creatorFee > 0) IERC20(token).safeTransfer(creatorRecipient, creatorFee);
        emit ProtocolFee(token, treasuryFee, creatorFee, creatorRecipient);
    }

    /// @inheritdoc IECTPair
    function skim(address to) external override lock {
        address _token0 = token0;
        address _token1 = token1;
        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - _reserve0);
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - _reserve1);
    }

    /// @inheritdoc IECTPair
    function sync() external override lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            _reserve0,
            _reserve1
        );
    }
}
