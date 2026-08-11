// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* -----------------------------------------------------------------------
 *                          DAEMONS V4 Router
 * -----------------------------------------------------------------------
 * Trust-minimized helper for the ETH / DAEMON Uniswap v4 pool.
 *
 * Website: https://daemons.life
 * Twitter: https://x.com/DAEMONSv4
 *
 * @title DAEMONS V4 Router
 * @author DAEMONSv4
 * @notice Convenience buy/sell router for the DAEMON hook pool.
 * -------------------------------------------------------------------- */

import "./ChainConfig.sol";
import "./DaemonToken.sol";

interface IPoolManagerSwap {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta swapDelta);
    function sync(Currency currency) external;
    function take(Currency currency, address to, uint256 amount) external;
    function settle() external payable returns (uint256 paid);
}

interface IERC20RouterMinimal {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract DaemonV4Router {
    IPoolManagerSwap public immutable MANAGER;

    uint256 public constant CONTRACT_REVISION = 2;
    uint160 public constant MIN_SQRT_PRICE_LIMIT_X96 = 4295128740;
    uint160 public constant MAX_SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;

    event Bought(address indexed buyer, address indexed token, uint256 ethIn, uint256 tokenOut);
    event Sold(address indexed seller, address indexed token, uint256 tokenIn, uint256 ethOut);

    error ManagerOnly();
    error InvalidPool();
    error NoEthSent();
    error InvalidAmount();
    error TransferFromFailed();
    error NativeRefundFailed();

    constructor() {
        MANAGER = IPoolManagerSwap(ChainConfig.poolManager(block.chainid));
    }

    receive() external payable {}

    function buy(PoolKey calldata key, address recipient) external payable returns (BalanceDelta delta) {
        if (msg.value == 0) revert NoEthSent();
        if (Currency.unwrap(key.currency0) != address(0)) revert InvalidPool();
        if (Currency.unwrap(key.currency1) == address(0)) revert InvalidPool();

        address actualRecipient = recipient == address(0) ? msg.sender : recipient;

        delta = abi.decode(
            MANAGER.unlock(
                abi.encode(
                    msg.sender,
                    actualRecipient,
                    key,
                    SwapParams({
                        zeroForOne: true,
                        amountSpecified: -int256(msg.value),
                        sqrtPriceLimitX96: MIN_SQRT_PRICE_LIMIT_X96
                    })
                )
            ),
            (BalanceDelta)
        );

        uint256 tokenOut = _abs(_amount1(delta));
        emit Bought(actualRecipient, Currency.unwrap(key.currency1), msg.value, tokenOut);

        _refundNative(msg.sender);
    }

    function sell(PoolKey calldata key, uint256 tokenAmountIn, address recipient)
        external
        returns (BalanceDelta delta)
    {
        if (tokenAmountIn == 0 || tokenAmountIn > uint256(type(int256).max)) {
            revert InvalidAmount();
        }
        if (Currency.unwrap(key.currency0) != address(0)) revert InvalidPool();
        if (Currency.unwrap(key.currency1) == address(0)) revert InvalidPool();

        address actualRecipient = recipient == address(0) ? msg.sender : recipient;

        delta = abi.decode(
            MANAGER.unlock(
                abi.encode(
                    msg.sender,
                    actualRecipient,
                    key,
                    SwapParams({
                        zeroForOne: false,
                        // Cast is safe because tokenAmountIn is bounded above by int256 max.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        amountSpecified: -int256(tokenAmountIn),
                        sqrtPriceLimitX96: MAX_SQRT_PRICE_LIMIT_X96
                    })
                )
            ),
            (BalanceDelta)
        );

        uint256 ethOut = _abs(_amount0(delta));
        emit Sold(actualRecipient, Currency.unwrap(key.currency1), tokenAmountIn, ethOut);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory result) {
        if (msg.sender != address(MANAGER)) revert ManagerOnly();

        (address payer, address recipient, PoolKey memory key, SwapParams memory params) =
            abi.decode(data, (address, address, PoolKey, SwapParams));

        BalanceDelta delta = MANAGER.swap(key, params, abi.encode(recipient));

        _settleOrTake(key.currency0, payer, recipient, _amount0(delta));
        _settleOrTake(key.currency1, payer, recipient, _amount1(delta));

        if (address(this).balance != 0) {
            _refundNative(payer);
        }

        return abi.encode(delta);
    }

    function _settleOrTake(Currency currency, address payer, address recipient, int128 amount) internal {
        if (amount < 0) {
            uint256 owed = _abs(amount);
            if (Currency.unwrap(currency) == address(0)) {
                MANAGER.settle{value: owed}();
            } else {
                MANAGER.sync(currency);
                bool ok = IERC20RouterMinimal(Currency.unwrap(currency)).transferFrom(payer, address(MANAGER), owed);
                if (!ok) revert TransferFromFailed();
                MANAGER.settle();
            }
        } else if (amount > 0) {
            MANAGER.take(currency, recipient, uint256(uint128(amount)));
        }
    }

    function _refundNative(address to) internal {
        uint256 balance = address(this).balance;
        if (balance == 0) return;

        (bool ok,) = payable(to).call{value: balance}("");
        if (!ok) revert NativeRefundFailed();
    }

    function _amount0(BalanceDelta delta) internal pure returns (int128 amount) {
        int256 raw = BalanceDelta.unwrap(delta);
        assembly ("memory-safe") {
            amount := sar(128, raw)
        }
    }

    function _amount1(BalanceDelta delta) internal pure returns (int128 amount) {
        int256 raw = BalanceDelta.unwrap(delta);
        assembly ("memory-safe") {
            amount := signextend(15, raw)
        }
    }

    function _abs(int128 value) internal pure returns (uint256) {
        int256 signed = int256(value);
        unchecked {
            return uint256(signed >= 0 ? signed : -signed);
        }
    }
}
