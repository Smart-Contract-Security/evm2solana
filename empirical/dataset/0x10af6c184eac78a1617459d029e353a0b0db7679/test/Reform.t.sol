// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Reform} from "../contracts/Reform.sol";
import {ReformHook, IReform} from "../contracts/ReformHook.sol";
import {Create2Factory} from "../contracts/Create2Factory.sol";

/*//////////////////////////////////////////////////////////////
                         TOKEN-ONLY TESTS
    Exercise the MasterChef accumulator with no V4 dependency.
    minter is a dedicated EOA (pranked) so the deployer treasury
    is a normal eligible holder. The deployer is excluded from
    rewards in setUp so `eligibleSupply` == the holders we create.
//////////////////////////////////////////////////////////////*/
contract ReformTokenTest is Test {
    Reform reform;
    address MINTER = makeAddr("minter");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        reform = new Reform(address(this));
        reform.setMinter(MINTER); // excludes MINTER + token contract
        reform.setExcludedFromRewards(address(this), true); // deployer treasury not eligible
    }

    function test_InitialSupply() public view {
        assertEq(reform.totalSupply(), 100_000_000 ether);
        assertEq(reform.balanceOf(address(this)), 100_000_000 ether);
    }

    function test_SetMinterIsOneShot() public {
        vm.expectRevert(Reform.MinterAlreadySet.selector);
        reform.setMinter(alice);
    }

    function test_DepositRewardOnlyMinter() public {
        vm.expectRevert(Reform.NotMinter.selector);
        vm.prank(alice);
        reform.depositReward(1 ether);
    }

    function test_DepositRewardBumpsAcc() public {
        reform.transfer(alice, 1000 ether); // eligibleSupply = 1000
        vm.prank(MINTER);
        reform.depositReward(100 ether);

        assertEq(reform.accTokensPerShare(), (100 ether * 1e18) / 1000 ether);
        // reward is minted into the token contract, held until claimed
        assertEq(reform.balanceOf(address(reform)), 100 ether);
    }

    function test_PendingRewardsProRata() public {
        reform.transfer(alice, 60 ether);
        reform.transfer(bob, 40 ether); // eligibleSupply = 100, acc becomes exactly 1e18
        vm.prank(MINTER);
        reform.depositReward(100 ether);

        assertEq(reform.pendingRewards(alice), 60 ether);
        assertEq(reform.pendingRewards(bob), 40 ether);
    }

    function test_ClaimTransfersExactAndZeros() public {
        reform.transfer(alice, 100 ether); // eligibleSupply = 100
        vm.prank(MINTER);
        reform.depositReward(50 ether); // pending(alice) = 50

        uint256 pre = reform.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = reform.claim();

        assertEq(claimed, 50 ether);
        assertEq(reform.balanceOf(alice), pre + 50 ether);
        assertEq(reform.pendingRewards(alice), 0);
    }

    function test_TransferAutoSettles() public {
        reform.transfer(alice, 10_000_000 ether); // alice holds 10M, sole eligible holder
        vm.prank(MINTER);
        reform.depositReward(10_000_000 ether); // acc = 1e18 → pending(alice) = 10M

        assertEq(reform.pendingRewards(alice), 10_000_000 ether);

        vm.prank(alice);
        reform.transfer(bob, 5_000_000 ether);

        // A's pending was paid out during the transfer (auto-settle on _update).
        // A: 10M held + 10M reward received - 5M sent = 15M, zero pending.
        assertEq(reform.pendingRewards(alice), 0);
        assertEq(reform.balanceOf(alice), 15_000_000 ether);
        // B starts with the 5M received and zero pending (debt set at receive).
        assertEq(reform.balanceOf(bob), 5_000_000 ether);
        assertEq(reform.pendingRewards(bob), 0);
        // contract emptied out the reward it minted
        assertEq(reform.balanceOf(address(reform)), 0);
    }

    function test_ExcludedDoNotEarn() public {
        reform.transfer(alice, 100 ether);
        reform.setExcludedFromRewards(alice, true); // alice now excluded
        reform.transfer(bob, 100 ether); // bob eligible so deposit doesn't route to dead

        vm.prank(MINTER);
        reform.depositReward(50 ether);

        assertEq(reform.pendingRewards(alice), 0);
        assertGt(reform.pendingRewards(bob), 0);
    }

    function test_SurpriseMintOnlyMinter() public {
        vm.expectRevert(Reform.NotMinter.selector);
        vm.prank(alice);
        reform.surpriseMint(bob, 1 ether);

        vm.prank(MINTER);
        reform.surpriseMint(carol, 777 ether);
        assertEq(reform.balanceOf(carol), 777 ether);
    }
}

/*//////////////////////////////////////////////////////////////
                          HOOK + V4 TESTS
    Deploy a real PoolManager + routers, mine a hook address with
    the 0x00CC flag bits via HookMiner, init an ETH/REFORM pool and
    seed deep liquidity. Pool: currency0 = ETH (address 0),
    currency1 = REFORM (always > 0).
//////////////////////////////////////////////////////////////*/
contract ReformHookTest is Test, Deployers {
    Reform reform;
    ReformHook hook;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    // full range for tickSpacing 60
    int24 constant MIN_TICK = -887220;
    int24 constant MAX_TICK = 887220;

    // 5% of tokens-received expressed as 1e18-scaled tokens per ETH-wei of net input.
    // rate = 1e18 → reward(tokens) = netEth (in wei). Keeps deposits to round numbers in tests.
    uint256 constant RATE = 1e18;

    function setUp() public {
        deployFreshManagerAndRouters();

        // 1. token
        reform = new Reform(address(this));

        // 2. mine + deploy hook to an address with the required flag bits.
        //    Deploy THROUGH a CREATE2 factory to mirror production: msg.sender inside the hook
        //    constructor is the factory, so ownership must come from the explicit initialOwner arg.
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        Create2Factory factory = new Create2Factory();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(manager)), IReform(address(reform)), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(factory), flags, type(ReformHook).creationCode, ctorArgs);
        address deployed = factory.deploy(abi.encodePacked(type(ReformHook).creationCode, ctorArgs), salt);
        hook = ReformHook(payable(deployed));
        require(deployed == hookAddr, "hook address mismatch");
        // sanity: lowest 14 bits == 0x00CC
        assertEq(uint160(address(hook)) & 0x3FFF, 0x00CC);
        // ownership came from the constructor arg, NOT the factory (regression guard)
        assertEq(hook.owner(), address(this));
        assertTrue(hook.owner() != address(factory));

        // 3. wire minter + exclusions (mirror 01-deploy.js, plus deployer treasury + routers)
        reform.setMinter(address(hook)); // excludes hook + token contract
        reform.setExcludedFromRewards(address(0xdEaD), true);
        reform.setExcludedFromRewards(address(manager), true);
        reform.setExcludedFromRewards(address(modifyLiquidityRouter), true);
        reform.setExcludedFromRewards(address(swapRouter), true);
        reform.setExcludedFromRewards(address(this), true); // deployer treasury not eligible

        // 4. init ETH/REFORM pool (fee 0, tickSpacing 60) at 1:1
        (key,) = initPool(
            CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(reform)), IHooks(address(hook)), 0, 60, SQRT_PRICE_1_1
        );

        // 5. seed deep full-range liquidity (~100 ETH / ~100 REFORM)
        vm.deal(address(this), 1000 ether);
        reform.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: 200 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: int256(uint256(100 ether)),
                salt: 0
            }),
            ZERO_BYTES
        );

        // 6. calibrate reward rate (trading still disabled)
        hook.setRewardMintRate(RATE);
    }

    // ---- helpers ----

    function _buy(address who, uint256 ethIn) internal returns (uint256 hookGain) {
        vm.deal(who, who.balance + ethIn);
        uint256 before = address(hook).balance;
        vm.prank(who);
        swapRouter.swap{value: ethIn}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true, // ETH(c0) -> REFORM(c1) == BUY
                amountSpecified: -int256(ethIn), // exact input
                sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        hookGain = address(hook).balance - before;
    }

    // returns (eth received by seller, sell tax taken by hook)
    function _sell(address who, uint256 reformIn) internal returns (uint256 ethOut, uint256 hookGain) {
        vm.prank(who);
        reform.approve(address(swapRouter), reformIn);
        uint256 ethBefore = who.balance;
        uint256 hookBefore = address(hook).balance;
        vm.prank(who);
        swapRouter.swap{value: 0}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: false, // REFORM(c1) -> ETH(c0) == SELL
                amountSpecified: -int256(reformIn), // exact input
                sqrtPriceLimitX96: MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        ethOut = who.balance - ethBefore;
        hookGain = address(hook).balance - hookBefore;
    }

    // ---- gate ----

    function test_TradingDisabledByDefault() public {
        // hook reverts TradingNotEnabled() in beforeSwap; PoolManager wraps it (HookCallFailed),
        // so we assert any revert rather than a specific selector.
        vm.expectRevert();
        _buy(alice, 1 ether);
    }

    function test_EnableThenSwapSucceeds() public {
        hook.enableTrading();
        uint256 gain = _buy(alice, 1 ether);
        assertGt(reform.balanceOf(alice), 0); // received REFORM
        assertEq(gain, 0.05 ether); // and paid tax
    }

    function test_EnableTradingIsOneWay() public {
        hook.enableTrading();
        vm.expectRevert(ReformHook.AlreadyEnabled.selector);
        hook.enableTrading();
    }

    // ---- buy tax ----

    function test_BuyTaxIs5PercentOfInput() public {
        hook.enableTrading();
        uint256 gain = _buy(alice, 1 ether);
        assertEq(gain, 0.05 ether); // exactly 5% of the 1 ETH input
        assertEq(hook.totalEthCollected(), 0.05 ether);
    }

    function test_BuyMintsRewardToTokenContract() public {
        hook.enableTrading();
        // need an eligible holder so the reward is distributed (not routed to dead)
        reform.transfer(alice, 1000 ether);

        uint256 contractBefore = reform.balanceOf(address(reform));
        _buy(bob, 1 ether);

        // net ETH = 1 - 0.05 = 0.95; reward = netEth * RATE / 1e18 = 0.95 ether tokens
        uint256 expectedReward = (0.95 ether * RATE) / 1e18;
        assertEq(reform.balanceOf(address(reform)) - contractBefore, expectedReward);
        assertEq(hook.totalRewardsMinted(), expectedReward);
    }

    // ---- sell tax (known-unknown #5: BalanceDelta sign convention) ----

    function test_SellTaxIs5PercentOfOutput() public {
        hook.enableTrading();
        // give bob REFORM to sell
        reform.transfer(bob, 1_000_000 ether);

        (uint256 ethOut, uint256 sellTax) = _sell(bob, 100 ether);

        assertGt(sellTax, 0);
        // gross output = what the seller netted + what the hook skimmed
        uint256 gross = ethOut + sellTax;
        // exact 5%: tax == gross * 500 / 10000 (integer math, same as the hook)
        assertEq(sellTax, (gross * 500) / 10_000);
        // and the seller received 95%, not 100%
        assertEq(ethOut, gross - sellTax);
    }

    // ---- owner powers ----

    function test_LowerTaxOnlyDecreases() public {
        hook.lowerTax(300);
        assertEq(hook.taxBps(), 300);

        vm.expectRevert(ReformHook.TaxCanOnlyDecrease.selector);
        hook.lowerTax(400); // higher than current

        vm.expectRevert(ReformHook.TaxCanOnlyDecrease.selector);
        hook.lowerTax(300); // equal also rejected
    }

    function test_EmergencyWithdrawETH() public {
        vm.deal(address(hook), 1 ether);

        uint256 bobBefore = bob.balance;
        hook.emergencyWithdrawETH(payable(bob), 0.3 ether);
        assertEq(bob.balance, bobBefore + 0.3 ether);
        assertEq(address(hook).balance, 0.7 ether);

        // amount 0 drains the rest
        hook.emergencyWithdrawETH(payable(bob), 0);
        assertEq(bob.balance, bobBefore + 1 ether);
        assertEq(address(hook).balance, 0);
    }

    function test_SurpriseMintViaHook() public {
        hook.surpriseMint(carol, 50_000 ether);
        assertEq(reform.balanceOf(carol), 50_000 ether);
    }

    function test_NonOwnerCallsRevert() public {
        vm.startPrank(alice);
        bytes memory err = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);

        vm.expectRevert(err);
        hook.enableTrading();
        vm.expectRevert(err);
        hook.emergencyWithdrawETH(payable(alice), 1);
        vm.expectRevert(err);
        hook.surpriseMint(alice, 1);
        vm.expectRevert(err);
        hook.lowerTax(1);
        vm.expectRevert(err);
        hook.setRewardMintRate(1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TEST
    //////////////////////////////////////////////////////////////*/
    function test_Integration_BuyClaimSell() public {
        hook.enableTrading();

        // seed A and B as eligible holders (so buy rewards distribute, not route to dead)
        reform.transfer(alice, 1_000_000 ether);
        reform.transfer(bob, 1_000_000 ether);

        uint256 hookStart = address(hook).balance;

        // --- A buys 1 ETH, B buys 1 ETH; each pays an exact 5% ETH tax ---
        uint256 taxA = _buy(alice, 1 ether);
        assertEq(taxA, 0.05 ether);
        uint256 taxB = _buy(bob, 1 ether);
        assertEq(taxB, 0.05 ether);

        // Reset A and B to a common reward baseline with a self-transfer (auto-settles pending).
        // Needed because a buyer's own pending is auto-settled when they RECEIVE swap output,
        // leaving the two holders on different accumulator windows otherwise.
        vm.prank(alice);
        reform.transfer(alice, reform.balanceOf(alice));
        vm.prank(bob);
        reform.transfer(bob, reform.balanceOf(bob));
        assertEq(reform.pendingRewards(alice), 0);
        assertEq(reform.pendingRewards(bob), 0);

        uint256 balA = reform.balanceOf(alice);
        uint256 balB = reform.balanceOf(bob);

        // --- carol buys 1 ETH: her reward is shared pro-rata by the passive holders A and B ---
        uint256 taxC = _buy(carol, 1 ether);
        assertEq(taxC, 0.05 ether);

        uint256 pendA = reform.pendingRewards(alice);
        uint256 pendB = reform.pendingRewards(bob);
        assertGt(pendA, 0);
        assertGt(pendB, 0);
        // proportional to balances on the same accumulator window: pendA/balA == pendB/balB
        assertApproxEqAbs(pendA * balB, pendB * balA, balA + balB);

        // --- A claims: receives exactly its pending, then zero ---
        uint256 aBefore = reform.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = reform.claim();
        assertEq(claimed, pendA);
        assertEq(reform.balanceOf(alice), aBefore + pendA);
        assertEq(reform.pendingRewards(alice), 0);

        // --- B sells half their REFORM, pays a 5% ETH sell tax ---
        uint256 sellAmt = reform.balanceOf(bob) / 2;
        (uint256 ethOut, uint256 sellTax) = _sell(bob, sellAmt);
        uint256 gross = ethOut + sellTax;
        assertEq(sellTax, (gross * 500) / 10_000);
        assertGt(sellTax, 0);

        // --- hook balance == 3 buy taxes (A, B, carol) + B's sell tax ---
        assertEq(address(hook).balance, hookStart + taxA + taxB + taxC + sellTax);
        assertEq(address(hook).balance, hookStart + 0.15 ether + sellTax);
    }
}
