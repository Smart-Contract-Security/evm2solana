// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title  YieldBasisArb v2
 * @notice Arbitrages both directions of YieldBasis VirtualPool vs Cryptopool spread.
 *
 * DIRECTION 0 — VP undervalues asset (VP gives more asset per crvUSD than CP):
 *   Flash loan crvUSD → VP.exchange(0→1) cheap asset → CP.exchange(1→0) sell high → repay
 *   Triggered when: VP.get_dy(1,0) < CP.get_dy(1,0)
 *
 * DIRECTION 1 — VP overvalues asset (VP pays more crvUSD per asset than CP):
 *   Flash loan ASSET → VP.exchange(1→0) above-market crvUSD → CP.exchange(0→1) buy asset cheap → repay
 *   Triggered when: VP.get_dy(1,0) > CP.get_dy(1,0)
 *
 * Both use Balancer V2 flash loans (0% fee).
 *
 * Deployment:
 *   Balancer Vault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8
 *   crvUSD:        0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E
 */

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface ICurvePool {
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function coins(uint256 i) external view returns (address);
}

contract YieldBasisArb is IFlashLoanRecipient {

    IBalancerVault public constant BALANCER =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address public constant CRVUSD =
        0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address public immutable OWNER;

    // Packed callback data
    struct CallbackData {
        address virtualPool;
        address cryptoPool;
        address assetToken;   // coins[1] of the pool pair
        uint256 direction;    // 0 = flash crvUSD, 1 = flash asset
        uint256 inputAmount;
        uint256 minProfit;
    }

    event ArbExecuted(
        address indexed virtualPool,
        uint256 direction,
        uint256 inputAmount,
        uint256 profit
    );

    constructor() {
        OWNER = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == OWNER, "not owner");
        _;
    }

    // ── SIMULATE (view) ────────────────────────────────────────────────────────

    /**
     * @notice Estimate profit for a given direction and input amount.
     * @param direction 0 = crvUSD input, 1 = asset input
     * @param amount    Input amount (crvUSD units for dir 0, asset units for dir 1)
     */
    function simulate(
        address virtualPool,
        address cryptoPool,
        uint256 direction,
        uint256 amount
    ) external view returns (uint256 out, uint256 profit) {
        if (direction == 0) {
            // crvUSD → VP → asset → CP → crvUSD
            uint256 assetOut  = ICurvePool(virtualPool).get_dy(0, 1, amount);
            uint256 crvUSDOut = ICurvePool(cryptoPool).get_dy(1, 0, assetOut);
            out    = crvUSDOut;
            profit = crvUSDOut > amount ? crvUSDOut - amount : 0;
        } else {
            // asset → VP → crvUSD → CP → asset
            uint256 crvUSDOut = ICurvePool(virtualPool).get_dy(1, 0, amount);
            uint256 assetOut  = ICurvePool(cryptoPool).get_dy(0, 1, crvUSDOut);
            out    = assetOut;
            profit = assetOut > amount ? assetOut - amount : 0;
        }
    }

    // ── MAIN ENTRY POINT ───────────────────────────────────────────────────────

    /**
     * @param virtualPool  YieldBasis VirtualPool address
     * @param cryptoPool   Curve Cryptopool address
     * @param direction    0 = flash crvUSD (VP undervalues asset)
     *                     1 = flash asset  (VP overvalues asset)
     * @param inputAmount  Flash loan amount (crvUSD for dir 0, asset for dir 1)
     * @param minProfit    Minimum profit to accept (in flash loan token units)
     */
    function arb(
        address virtualPool,
        address cryptoPool,
        uint256 direction,
        uint256 inputAmount,
        uint256 minProfit
    ) external onlyOwner {
        require(direction <= 1, "invalid direction");

        address assetToken = ICurvePool(cryptoPool).coins(1);
        address flashToken = direction == 0 ? CRVUSD : assetToken;

        bytes memory data = abi.encode(CallbackData({
            virtualPool : virtualPool,
            cryptoPool  : cryptoPool,
            assetToken  : assetToken,
            direction   : direction,
            inputAmount : inputAmount,
            minProfit   : minProfit
        }));

        address[] memory tokens  = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0]  = flashToken;
        amounts[0] = inputAmount;

        BALANCER.flashLoan(address(this), tokens, amounts, data);
    }

    // ── BALANCER CALLBACK ──────────────────────────────────────────────────────

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == address(BALANCER), "caller not Balancer");

        tokens; feeAmounts; // silence unused warnings

        CallbackData memory d = abi.decode(userData, (CallbackData));
        uint256 repayAmount   = amounts[0]; // Balancer fee = 0

        if (d.direction == 0) {
            _executeDir0(d, repayAmount);
        } else {
            _executeDir1(d, repayAmount);
        }
    }

    // ── DIRECTION 0: flash crvUSD → VP cheap asset → CP sell high ─────────────

    function _executeDir0(CallbackData memory d, uint256 repayAmount) internal {
        // Step 1: buy asset cheap from VirtualPool
        IERC20(CRVUSD).approve(d.virtualPool, d.inputAmount);
        uint256 assetReceived = ICurvePool(d.virtualPool).exchange(
            0, 1, d.inputAmount, 1
        );

        // Step 2: sell asset to Cryptopool for more crvUSD
        IERC20(d.assetToken).approve(d.cryptoPool, assetReceived);
        uint256 crvUSDReceived = ICurvePool(d.cryptoPool).exchange(
            1, 0, assetReceived, repayAmount
        );

        // Step 3: repay flash loan
        require(crvUSDReceived >= repayAmount, "cannot repay");
        IERC20(CRVUSD).transfer(address(BALANCER), repayAmount);

        // Step 4: profit to owner
        uint256 profit = crvUSDReceived - repayAmount;
        require(profit >= d.minProfit, "below min profit");
        if (profit > 0) IERC20(CRVUSD).transfer(OWNER, profit);

        emit ArbExecuted(d.virtualPool, 0, d.inputAmount, profit);
    }

    // ── DIRECTION 1: flash asset → VP above-market crvUSD → CP buy asset cheap ─

    function _executeDir1(CallbackData memory d, uint256 repayAmount) internal {
        // Step 1: sell asset to VirtualPool for above-market crvUSD
        IERC20(d.assetToken).approve(d.virtualPool, d.inputAmount);
        uint256 crvUSDReceived = ICurvePool(d.virtualPool).exchange(
            1, 0, d.inputAmount, 1
        );

        // Step 2: use crvUSD to buy asset back from Cryptopool cheaply
        IERC20(CRVUSD).approve(d.cryptoPool, crvUSDReceived);
        uint256 assetReceived = ICurvePool(d.cryptoPool).exchange(
            0, 1, crvUSDReceived, repayAmount
        );

        // Step 3: repay flash loan (in asset token)
        require(assetReceived >= repayAmount, "cannot repay");
        IERC20(d.assetToken).transfer(address(BALANCER), repayAmount);

        // Step 4: profit to owner (in asset token)
        uint256 profit = assetReceived - repayAmount;
        require(profit >= d.minProfit, "below min profit");
        if (profit > 0) IERC20(d.assetToken).transfer(OWNER, profit);

        emit ArbExecuted(d.virtualPool, 1, d.inputAmount, profit);
    }

    // ── RESCUE ─────────────────────────────────────────────────────────────────

    function rescueToken(address token) external onlyOwner {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "nothing");
        IERC20(token).transfer(OWNER, bal);
    }

    receive() external payable {}
}
