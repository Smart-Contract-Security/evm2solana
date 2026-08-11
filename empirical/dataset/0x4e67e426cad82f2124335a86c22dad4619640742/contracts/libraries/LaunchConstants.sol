// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Launch math and parameter bounds for the one-shot presale/bootstrap path.
/// @dev Keeps contribution sizing, fixed claim inventory, pool ordering, and launch price derivation in one library
/// so deploy tooling and Solidity enforce the same token/WETH path.
library LaunchConstants {
    error IdenticalLaunchCurrencies();
    error ZeroContributionAmount();
    error ZeroMaxRaiseWeth();
    error MaxRaiseNotMultiple(uint256 maxRaiseWeth, uint256 contributionAmount);
    error InvalidContributorBounds(uint256 maxContributors, uint256 minimum, uint256 maximum);
    error PresaleAllocationExceedsSupply(uint256 requiredToken, uint256 initialSupply);
    error ExpectedSqrtPriceOutOfBounds(uint256 sqrtPriceX96);

    uint24 internal constant STATIC_LP_FEE = 0;
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant INITIAL_SUPPLY = 802_200 ether;
    uint256 internal constant CLAIM_AMOUNT = 13_370 ether;
    uint256 internal constant MAX_CONTRIBUTORS = 30;
    uint256 internal constant MIN_CONTRIBUTORS = 10;
    uint256 internal constant SALE_DURATION = 42 minutes;
    uint256 internal constant ALLOCATION_DUST_CAP = 500 wei;
    uint256 internal constant Q192 = 1 << 192;
    bytes32 internal constant LP_SALT = bytes32(uint256(1));

    struct SaleParams {
        uint256 contributionAmount;
        uint256 maxRaiseWeth;
        uint256 maxContributors;
    }

    function validateSaleParams(uint256 contributionAmount, uint256 maxRaiseWeth)
        internal
        pure
        returns (SaleParams memory params)
    {
        if (contributionAmount == 0) revert ZeroContributionAmount();
        if (maxRaiseWeth == 0) revert ZeroMaxRaiseWeth();
        if (maxRaiseWeth % contributionAmount != 0) {
            revert MaxRaiseNotMultiple(maxRaiseWeth, contributionAmount);
        }

        uint256 maxContributors = maxRaiseWeth / contributionAmount;
        if (maxContributors < MIN_CONTRIBUTORS || maxContributors > MAX_CONTRIBUTORS) {
            revert InvalidContributorBounds(maxContributors, MIN_CONTRIBUTORS, MAX_CONTRIBUTORS);
        }

        uint256 requiredToken = maxContributors * CLAIM_AMOUNT * 2;
        if (requiredToken > INITIAL_SUPPLY) revert PresaleAllocationExceedsSupply(requiredToken, INITIAL_SUPPLY);

        params = SaleParams({
            contributionAmount: contributionAmount, maxRaiseWeth: maxRaiseWeth, maxContributors: maxContributors
        });
    }

    function tickLower() internal pure returns (int24) {
        return TickMath.minUsableTick(TICK_SPACING);
    }

    function tickUpper() internal pure returns (int24) {
        return TickMath.maxUsableTick(TICK_SPACING);
    }

    function orderedLaunchAmounts(address token, address weth, uint256 tokenAmount, uint256 wethAmount)
        internal
        pure
        returns (Currency currency0, Currency currency1, uint256 amount0, uint256 amount1, bool tokenIsCurrency0)
    {
        if (token == weth) revert IdenticalLaunchCurrencies();
        tokenIsCurrency0 = token < weth;
        if (tokenIsCurrency0) {
            return (Currency.wrap(token), Currency.wrap(weth), tokenAmount, wethAmount, true);
        }
        return (Currency.wrap(weth), Currency.wrap(token), wethAmount, tokenAmount, false);
    }

    function orderedLaunchCurrencies(address token, address weth)
        internal
        pure
        returns (Currency currency0, Currency currency1)
    {
        if (token == weth) revert IdenticalLaunchCurrencies();
        if (token < weth) return (Currency.wrap(token), Currency.wrap(weth));
        return (Currency.wrap(weth), Currency.wrap(token));
    }

    function orderedLaunchAmountValues(address token, address weth, uint256 tokenAmount, uint256 wethAmount)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (token == weth) revert IdenticalLaunchCurrencies();
        if (token < weth) return (tokenAmount, wethAmount);
        return (wethAmount, tokenAmount);
    }

    /// @dev Derives the launch sqrt price from contribution WETH per fixed claim amount, normalized by token order.
    function expectedSqrtPriceX96(address token, address weth, uint256 contributionAmount)
        internal
        pure
        returns (uint160)
    {
        (uint256 amount0, uint256 amount1) = orderedLaunchAmountValues(token, weth, CLAIM_AMOUNT, contributionAmount);
        if ((amount1 >> 64) >= amount0) revert ExpectedSqrtPriceOutOfBounds(type(uint256).max);
        uint256 sqrtPriceX96 = Math.sqrt(FullMath.mulDiv(amount1, Q192, amount0));
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) {
            revert ExpectedSqrtPriceOutOfBounds(sqrtPriceX96);
        }
        return uint160(sqrtPriceX96);
    }

    function expectedLiquidity(
        address token,
        address weth,
        uint256 tokenAmount,
        uint256 wethAmount,
        uint256 contributionAmount
    ) internal pure returns (uint128 liquidity) {
        (uint256 amount0, uint256 amount1) = orderedLaunchAmountValues(token, weth, tokenAmount, wethAmount);
        uint160 sqrtPriceX96 = expectedSqrtPriceX96(token, weth, contributionAmount);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower()),
            TickMath.getSqrtPriceAtTick(tickUpper()),
            amount0,
            amount1
        );
    }
}
