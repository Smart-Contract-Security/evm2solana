// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

contract TestLiquidityRouter {
    IPoolManager public immutable manager;
    address public immutable owner;

    struct CallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
        bytes hookData;
    }

    constructor(IPoolManager _manager) {
        manager = _manager;
        owner = msg.sender;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        require(msg.sender == owner, "only owner");
        delta = abi.decode(manager.unlock(abi.encode(CallbackData(msg.sender, key, params, hookData))), (BalanceDelta));
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool ok,) = owner.call{value: ethBal}("");
            require(ok);
        }
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (BalanceDelta delta,) = manager.modifyLiquidity(data.key, data.params, data.hookData);

        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        if (d0 < 0) {
            manager.settle{value: uint256(uint128(-d0))}();
        } else if (d0 > 0) {
            manager.take(data.key.currency0, data.sender, uint256(uint128(d0)));
        }

        if (d1 < 0) {
            manager.sync(data.key.currency1);
            IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                data.sender, address(manager), uint256(uint128(-d1))
            );
            manager.settle();
        } else if (d1 > 0) {
            manager.take(data.key.currency1, data.sender, uint256(uint128(d1)));
        }

        return abi.encode(delta);
    }

    function sweepETH() external {
        require(msg.sender == owner);
        (bool ok,) = owner.call{value: address(this).balance}("");
        require(ok);
    }

    function sweepERC20(address token) external {
        require(msg.sender == owner);
        uint256 bal = IERC20Minimal(token).balanceOf(address(this));
        if (bal > 0) IERC20Minimal(token).transfer(owner, bal);
    }

    receive() external payable {}
}
