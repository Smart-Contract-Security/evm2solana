// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {IECTPair} from "../interfaces/IECTPair.sol";
import {IECTPairFactory} from "../interfaces/IECTPairFactory.sol";
import {IECTRouter} from "../interfaces/IECTRouter.sol";

contract ECTRouter is IECTRouter {
    using SafeERC20 for IERC20;

    address public immutable override factory;
    address public immutable override ect;

    error Expired();
    error IdenticalAddresses();
    error ZeroAddress();
    error InsufficientAmount();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InvalidPath();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error ExcessiveInputAmount();
    error MustIncludeECT();

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    constructor(address factory_, address ect_) {
        if (factory_ == address(0) || ect_ == address(0)) revert ZeroAddress();
        factory = factory_;
        ect = ect_;
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address, address) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (t0 == address(0)) revert ZeroAddress();
        return (t0, t1);
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        pair = IECTPairFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) revert InsufficientLiquidity();
    }

    function _getReserves(address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint112 r0, uint112 r1,) = IECTPair(_pairFor(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
    }

    /// @inheritdoc IECTRouter
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        override
        returns (uint256 amountB)
    {
        if (amountA == 0) revert InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @inheritdoc IECTRouter
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        override
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        // Protocol fee (1.5%) leaves the pool; 98.5% of input goes into the AMM.
        uint256 amountInAfterProtocol = (amountIn * 9850) / 10_000;
        // 0.3% LP fee: multiply by 997, denominator scales by 1000.
        uint256 amountInWithFee = amountInAfterProtocol * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @inheritdoc IECTRouter
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        override
        returns (uint256 amountIn)
    {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        // Inverse of getAmountOut with K = 9850 * 997 = 9_820_450.
        // amountIn = ceil((amountOut * 10_000_000 * Rin) / (K * (Rout - amountOut)))
        if (amountOut >= reserveOut) revert InsufficientLiquidity();
        uint256 numerator = amountOut * 10_000_000 * reserveIn;
        uint256 denominator = uint256(9_820_450) * (reserveOut - amountOut);
        amountIn = numerator / denominator + 1; // round up
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; --i) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (IECTPairFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            revert InsufficientLiquidity();
        }
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) revert InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    struct AddLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }

    /// @inheritdoc IECTRouter
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        return _addLiquidityFull(
            AddLiquidityParams({
                tokenA: tokenA,
                tokenB: tokenB,
                amountADesired: amountADesired,
                amountBDesired: amountBDesired,
                amountAMin: amountAMin,
                amountBMin: amountBMin,
                to: to,
                deadline: deadline
            })
        );
    }

    function _addLiquidityFull(AddLiquidityParams memory p)
        internal
        ensure(p.deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB) = _addLiquidity(
            p.tokenA, p.tokenB, p.amountADesired, p.amountBDesired, p.amountAMin, p.amountBMin
        );
        address pair = _pairFor(p.tokenA, p.tokenB);
        IERC20(p.tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(p.tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IECTPair(pair).mint(p.to);
    }

    /// @inheritdoc IECTRouter
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IECTPair(pair).burn(to);
        (address token0,) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    /// @inheritdoc IECTRouter
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        // The pair LP token is plain ERC20 (no permit); soft-fail signals unsupported.
        try IERC20Permit(pair).permit(msg.sender, address(this), value, deadline, v, r, s) {}
            catch {
            revert ZeroAddress();
        }
        (amountA, amountB) =
            removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /// @dev Caller has already transferred the first hop's input to the first pair.
    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to =
                i < path.length - 2 ? _pairFor(output, path[i + 2]) : _to;
            IECTPair(_pairFor(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @inheritdoc IECTRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        _validateMultiHopPath(path);
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        IERC20(path[0]).safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), amountIn);
        _swap(amounts, path, to);
    }

    /// @inheritdoc IECTRouter
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        _validateMultiHopPath(path);
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert ExcessiveInputAmount();
        IERC20(path[0]).safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /// @dev Every adjacent pair on the path must exist in the factory.
    function _validateMultiHopPath(address[] calldata path) internal view {
        if (path.length < 2) revert InvalidPath();
        for (uint256 i; i < path.length - 1; ++i) {
            if (IECTPairFactory(factory).getPair(path[i], path[i + 1]) == address(0)) {
                revert InsufficientLiquidity();
            }
        }
    }
}
