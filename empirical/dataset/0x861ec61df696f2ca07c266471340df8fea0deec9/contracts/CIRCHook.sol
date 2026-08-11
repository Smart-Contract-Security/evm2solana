// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ICIRC {
    function injectFlow(uint256 amount) external;
    function printFlow(address recipient, uint256 amount) external;
}

/**
 * @title CIRCHook
 * @notice Uniswap V4 hook for the $CIRC (Recirculate) pool. ETH<>CIRC only.
 *
 *         On every exact-input swap:
 *           BUY  (ETH in, CIRC out):  tax 6% of ETH input  in beforeSwap
 *                                     + mint 6% reward tokens via accumulator
 *           SELL (CIRC in, ETH out):  tax 6% of ETH output in afterSwap
 *
 *         Sells are not "rewarded" — the reward mint fires on buys only (rewards holders for
 *         buy pressure, not exit). Both sides feed the ETH treasury.
 *
 *         Trading gate: blocks all swaps until owner starts circulation (anti-snipe).
 *
 *         REQUIRED HOOK ADDRESS FLAG BITS (lower 14 bits):
 *           BEFORE_SWAP_FLAG               (1<<7)  = 0x0080
 *           AFTER_SWAP_FLAG                (1<<6)  = 0x0040
 *           BEFORE_SWAP_RETURNS_DELTA_FLAG (1<<3)  = 0x0008
 *           AFTER_SWAP_RETURNS_DELTA_FLAG  (1<<2)  = 0x0004
 *           ─────────────────────────────────────  = 0x00CC
 *
 *         Use scripts/mine-salt.js (target = 0x00CC).
 */
contract CIRCHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;

    ICIRC public immutable circ;

    uint256 public taxBps = 600;        // 6%, owner can lower only
    uint256 public constant BPS = 10_000;

    /// @notice tokens minted (1e18-form) per 1 ETH of net buy input. Calibrate at launch.
    uint256 public rewardMintRate;

    bool public tradingEnabled;
    PoolId public servicedPool;
    bool public poolBound;

    uint256 public totalEthCollected;
    uint256 public totalRewardsMinted;

    event Tax(address indexed payer, uint256 ethAmount, bool isSell);
    event RewardMinted(uint256 ethTax, uint256 tokensMinted);
    event CirculationDrained(address indexed to, uint256 amount);
    event FlowPrinted(address indexed recipient, uint256 amount);
    event CirculationStarted();
    event TaxEased(uint256 newBps);
    event FlowRateUpdated(uint256 newRate);

    error InvalidPool();
    error InvalidPair();
    error TradingNotEnabled();
    error TaxCanOnlyDecrease();
    error AlreadyEnabled();

    /// @param initialOwner owner of the hook. Passed explicitly because the hook is deployed
    ///        through a CREATE2 factory (to land on the 0x00CC flag address), so msg.sender
    ///        inside this constructor is the factory, not the launching EOA.
    constructor(IPoolManager _manager, ICIRC _circ, address initialOwner)
        BaseHook(_manager)
        Ownable(initialOwner)
    {
        circ = _circ;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -------------------------------------------------------------------
    // BUY TAX — beforeSwap
    // -------------------------------------------------------------------
    function _beforeSwap(
        address, /* sender */
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!tradingEnabled) revert TradingNotEnabled();

        if (!poolBound) {
            servicedPool = key.toId();
            poolBound = true;
        } else if (PoolId.unwrap(key.toId()) != PoolId.unwrap(servicedPool)) {
            revert InvalidPool();
        }

        // Must be ETH<>TOKEN. Since address(0) < any token, currency0 IS ETH here.
        bool c0IsEth = key.currency0.isAddressZero();
        bool c1IsEth = key.currency1.isAddressZero();
        if (!c0IsEth && !c1IsEth) revert InvalidPair();

        bool ethIsInput = c0IsEth ? params.zeroForOne : !params.zeroForOne;
        bool exactInput = params.amountSpecified < 0;

        // Tax-on-buy only here; sells handled in afterSwap.
        if (!exactInput || !ethIsInput) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 inputAmount = uint256(-params.amountSpecified);
        uint256 tax = (inputAmount * taxBps) / BPS;
        if (tax == 0) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        Currency ethCurrency = c0IsEth ? key.currency0 : key.currency1;
        poolManager.take(ethCurrency, address(this), tax);
        totalEthCollected += tax;
        emit Tax(tx.origin, tax, false);

        // Mint reward tokens based on net ETH input (post-tax)
        uint256 netEth = inputAmount - tax;
        uint256 rewardAmount = (netEth * rewardMintRate) / 1e18;
        if (rewardAmount > 0) {
            circ.injectFlow(rewardAmount);
            totalRewardsMinted += rewardAmount;
            emit RewardMinted(tax, rewardAmount);
        }

        // Specified-side delta: we removed `tax` from the input
        return (
            this.beforeSwap.selector,
            toBeforeSwapDelta(int128(int256(tax)), int128(0)),
            0
        );
    }

    // -------------------------------------------------------------------
    // SELL TAX — afterSwap
    // -------------------------------------------------------------------
    function _afterSwap(
        address, /* sender */
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Determine if this was a SELL (token in, ETH out).
        bool c0IsEth = key.currency0.isAddressZero();
        bool ethIsInput = c0IsEth ? params.zeroForOne : !params.zeroForOne;
        bool exactInput = params.amountSpecified < 0;

        // Only handle sells with exact-input swaps in this version.
        // Buys are already taxed in beforeSwap; skip.
        if (!exactInput || ethIsInput) {
            return (this.afterSwap.selector, 0);
        }

        // For a sell, ETH is the UNSPECIFIED output (positive in the delta).
        // amount0/amount1 in BalanceDelta represents the swapper's perspective:
        //   positive = received, negative = paid
        int128 ethDelta = c0IsEth ? delta.amount0() : delta.amount1();
        if (ethDelta <= 0) return (this.afterSwap.selector, 0); // sanity

        uint256 ethOut = uint256(uint128(ethDelta));
        uint256 tax = (ethOut * taxBps) / BPS;
        if (tax == 0) return (this.afterSwap.selector, 0);

        Currency ethCurrency = c0IsEth ? key.currency0 : key.currency1;
        poolManager.take(ethCurrency, address(this), tax);
        totalEthCollected += tax;
        emit Tax(tx.origin, tax, true);

        // Return positive int128 on the unspecified (output) side to reduce user's output by `tax`.
        // In afterSwap return delta convention, this is on the unspecified currency.
        return (this.afterSwap.selector, int128(int256(tax)));
    }

    // -------------------------------------------------------------------
    // OWNER FUNCTIONS
    // -------------------------------------------------------------------

    function startCirculation() external onlyOwner {
        if (tradingEnabled) revert AlreadyEnabled();
        tradingEnabled = true;
        emit CirculationStarted();
    }

    function drainCirculation(address payable to, uint256 amount) external onlyOwner {
        if (amount == 0) amount = address(this).balance;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "eth send failed");
        emit CirculationDrained(to, amount);
    }

    function printFlow(address recipient, uint256 amount) external onlyOwner {
        circ.printFlow(recipient, amount);
        emit FlowPrinted(recipient, amount);
    }

    function easeTax(uint256 newBps) external onlyOwner {
        if (newBps >= taxBps) revert TaxCanOnlyDecrease();
        taxBps = newBps;
        emit TaxEased(newBps);
    }

    function setFlowRate(uint256 newRate) external onlyOwner {
        rewardMintRate = newRate;
        emit FlowRateUpdated(newRate);
    }

    receive() external payable {}
}
