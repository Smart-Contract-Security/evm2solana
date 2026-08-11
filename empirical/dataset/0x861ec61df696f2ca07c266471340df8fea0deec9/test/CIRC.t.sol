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

import {CIRC} from "../contracts/CIRC.sol";
import {CIRCHook, ICIRC} from "../contracts/CIRCHook.sol";
import {Create2Factory} from "../contracts/Create2Factory.sol";

/*//////////////////////////////////////////////////////////////
                         TOKEN-ONLY TESTS
    Exercise the MasterChef accumulator with no V4 dependency.
    circulator is a dedicated EOA (pranked) so the deployer
    treasury is a normal eligible holder. The deployer is set
    stagnant in setUp so `eligibleSupply` == the holders we create.
//////////////////////////////////////////////////////////////*/
contract CIRCTokenTest is Test {
    CIRC circ;
    address CIRCULATOR = makeAddr("circulator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        circ = new CIRC(address(this));
        circ.setCirculator(CIRCULATOR); // marks CIRCULATOR + token contract stagnant
        circ.setStagnant(address(this), true); // deployer treasury not eligible
    }

    function test_InitialSupply() public view {
        assertEq(circ.totalSupply(), 1_000_000_000 ether);
        assertEq(circ.balanceOf(address(this)), 1_000_000_000 ether);
        assertEq(circ.name(), "Recirculate");
        assertEq(circ.symbol(), "CIRC");
    }

    function test_SetCirculatorIsOneShot() public {
        vm.expectRevert(CIRC.CirculatorAlreadySet.selector);
        circ.setCirculator(alice);
    }

    function test_InjectFlowOnlyCirculator() public {
        vm.expectRevert(CIRC.NotCirculator.selector);
        vm.prank(alice);
        circ.injectFlow(1 ether);
    }

    function test_InjectFlowBumpsAcc() public {
        circ.transfer(alice, 1000 ether); // eligibleSupply = 1000
        vm.prank(CIRCULATOR);
        circ.injectFlow(100 ether);

        assertEq(circ.accTokensPerShare(), (100 ether * 1e18) / 1000 ether);
        // reward is minted into the token contract, held until recirculated
        assertEq(circ.balanceOf(address(circ)), 100 ether);
    }

    function test_PendingFlowProRata() public {
        circ.transfer(alice, 60 ether);
        circ.transfer(bob, 40 ether); // eligibleSupply = 100, acc becomes exactly 1e18
        vm.prank(CIRCULATOR);
        circ.injectFlow(100 ether);

        assertEq(circ.pendingFlow(alice), 60 ether);
        assertEq(circ.pendingFlow(bob), 40 ether);
    }

    function test_RecirculateTransfersExactAndZeros() public {
        circ.transfer(alice, 100 ether); // eligibleSupply = 100
        vm.prank(CIRCULATOR);
        circ.injectFlow(50 ether); // pending(alice) = 50

        uint256 pre = circ.balanceOf(alice);
        vm.prank(alice);
        uint256 recirculated = circ.recirculate();

        assertEq(recirculated, 50 ether);
        assertEq(circ.balanceOf(alice), pre + 50 ether);
        assertEq(circ.pendingFlow(alice), 0);
    }

    function test_TransferAutoSettles() public {
        circ.transfer(alice, 10_000_000 ether); // alice holds 10M, sole eligible holder
        vm.prank(CIRCULATOR);
        circ.injectFlow(10_000_000 ether); // acc = 1e18 → pending(alice) = 10M

        assertEq(circ.pendingFlow(alice), 10_000_000 ether);

        vm.prank(alice);
        circ.transfer(bob, 5_000_000 ether);

        // A's pending was paid out during the transfer (auto-settle on _update).
        assertEq(circ.pendingFlow(alice), 0);
        assertEq(circ.balanceOf(alice), 15_000_000 ether);
        assertEq(circ.balanceOf(bob), 5_000_000 ether);
        assertEq(circ.pendingFlow(bob), 0);
        assertEq(circ.balanceOf(address(circ)), 0);
    }

    function test_StagnantDoNotEarn() public {
        circ.transfer(alice, 100 ether);
        circ.setStagnant(alice, true); // alice now stagnant
        circ.transfer(bob, 100 ether); // bob eligible so injectFlow doesn't route to dead

        vm.prank(CIRCULATOR);
        circ.injectFlow(50 ether);

        assertEq(circ.pendingFlow(alice), 0);
        assertGt(circ.pendingFlow(bob), 0);
    }

    function test_PrintFlowOnlyCirculator() public {
        vm.expectRevert(CIRC.NotCirculator.selector);
        vm.prank(alice);
        circ.printFlow(bob, 1 ether);

        vm.prank(CIRCULATOR);
        circ.printFlow(carol, 777 ether);
        assertEq(circ.balanceOf(carol), 777 ether);
    }
}

/*//////////////////////////////////////////////////////////////
                          HOOK + V4 TESTS
    Deploy a real PoolManager + routers, mine a hook address with
    the 0x00CC flag bits via HookMiner, init an ETH/CIRC pool and
    seed deep liquidity. Pool: currency0 = ETH (address 0),
    currency1 = CIRC (always > 0).
//////////////////////////////////////////////////////////////*/
contract CIRCHookTest is Test, Deployers {
    CIRC circ;
    CIRCHook hook;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    // full range for tickSpacing 60
    int24 constant MIN_TICK = -887220;
    int24 constant MAX_TICK = 887220;

    // 6% of tokens-received expressed as 1e18-scaled tokens per ETH-wei of net input.
    // rate = 1e18 → reward(tokens) = netEth (in wei). Keeps deposits to round numbers in tests.
    uint256 constant RATE = 1e18;

    function setUp() public {
        deployFreshManagerAndRouters();

        // 1. token
        circ = new CIRC(address(this));

        // 2. mine + deploy hook to an address with the required flag bits.
        //    Deploy THROUGH a CREATE2 factory to mirror production: msg.sender inside the hook
        //    constructor is the factory, so ownership must come from the explicit initialOwner arg.
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        Create2Factory factory = new Create2Factory();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(manager)), ICIRC(address(circ)), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(factory), flags, type(CIRCHook).creationCode, ctorArgs);
        address deployed = factory.deploy(abi.encodePacked(type(CIRCHook).creationCode, ctorArgs), salt);
        hook = CIRCHook(payable(deployed));
        require(deployed == hookAddr, "hook address mismatch");
        // sanity: lowest 14 bits == 0x00CC
        assertEq(uint160(address(hook)) & 0x3FFF, 0x00CC);
        // ownership came from the constructor arg, NOT the factory (regression guard)
        assertEq(hook.owner(), address(this));
        assertTrue(hook.owner() != address(factory));

        // 3. wire circulator + stagnant (mirror 01-deploy.js, plus deployer treasury + routers)
        circ.setCirculator(address(hook)); // marks hook + token contract stagnant
        circ.setStagnant(address(0xdEaD), true);
        circ.setStagnant(address(manager), true);
        circ.setStagnant(address(modifyLiquidityRouter), true);
        circ.setStagnant(address(swapRouter), true);
        circ.setStagnant(address(this), true); // deployer treasury not eligible

        // 4. init ETH/CIRC pool (fee 0, tickSpacing 60) at 1:1
        (key,) = initPool(
            CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(circ)), IHooks(address(hook)), 0, 60, SQRT_PRICE_1_1
        );

        // 5. seed deep full-range liquidity (~100 ETH / ~100 CIRC)
        vm.deal(address(this), 1000 ether);
        circ.approve(address(modifyLiquidityRouter), type(uint256).max);
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
        hook.setFlowRate(RATE);
    }

    // ---- helpers ----

    function _buy(address who, uint256 ethIn) internal returns (uint256 hookGain) {
        vm.deal(who, who.balance + ethIn);
        uint256 before = address(hook).balance;
        vm.prank(who);
        swapRouter.swap{value: ethIn}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true, // ETH(c0) -> CIRC(c1) == BUY
                amountSpecified: -int256(ethIn), // exact input
                sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        hookGain = address(hook).balance - before;
    }

    // returns (eth received by seller, sell tax taken by hook)
    function _sell(address who, uint256 circIn) internal returns (uint256 ethOut, uint256 hookGain) {
        vm.prank(who);
        circ.approve(address(swapRouter), circIn);
        uint256 ethBefore = who.balance;
        uint256 hookBefore = address(hook).balance;
        vm.prank(who);
        swapRouter.swap{value: 0}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: false, // CIRC(c1) -> ETH(c0) == SELL
                amountSpecified: -int256(circIn), // exact input
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

    function test_StartCirculationThenSwapSucceeds() public {
        hook.startCirculation();
        uint256 gain = _buy(alice, 1 ether);
        assertGt(circ.balanceOf(alice), 0); // received CIRC
        assertEq(gain, 0.06 ether); // and paid 6% tax
    }

    function test_StartCirculationIsOneWay() public {
        hook.startCirculation();
        vm.expectRevert(CIRCHook.AlreadyEnabled.selector);
        hook.startCirculation();
    }

    // ---- buy tax ----

    function test_BuyTaxIs6PercentOfInput() public {
        hook.startCirculation();
        uint256 gain = _buy(alice, 1 ether);
        assertEq(gain, 0.06 ether); // exactly 6% of the 1 ETH input
        assertEq(hook.totalEthCollected(), 0.06 ether);
    }

    function test_BuyInjectsFlowToTokenContract() public {
        hook.startCirculation();
        // need an eligible holder so the reward is distributed (not routed to dead)
        circ.transfer(alice, 1000 ether);

        uint256 contractBefore = circ.balanceOf(address(circ));
        _buy(bob, 1 ether);

        // net ETH = 1 - 0.06 = 0.94; reward = netEth * RATE / 1e18 = 0.94 ether tokens
        uint256 expectedReward = (0.94 ether * RATE) / 1e18;
        assertEq(circ.balanceOf(address(circ)) - contractBefore, expectedReward);
        assertEq(hook.totalRewardsMinted(), expectedReward);
    }

    // ---- sell tax (BalanceDelta sign convention) ----

    function test_SellTaxIs6PercentOfOutput() public {
        hook.startCirculation();
        // give bob CIRC to sell
        circ.transfer(bob, 1_000_000 ether);

        (uint256 ethOut, uint256 sellTax) = _sell(bob, 100 ether);

        assertGt(sellTax, 0);
        // gross output = what the seller netted + what the hook skimmed
        uint256 gross = ethOut + sellTax;
        // exact 6%: tax == gross * 600 / 10000 (integer math, same as the hook)
        assertEq(sellTax, (gross * 600) / 10_000);
        // and the seller received 94%, not 100%
        assertEq(ethOut, gross - sellTax);
    }

    // ---- owner powers ----

    function test_EaseTaxOnlyDecreases() public {
        hook.easeTax(400);
        assertEq(hook.taxBps(), 400);

        vm.expectRevert(CIRCHook.TaxCanOnlyDecrease.selector);
        hook.easeTax(500); // higher than current

        vm.expectRevert(CIRCHook.TaxCanOnlyDecrease.selector);
        hook.easeTax(400); // equal also rejected
    }

    function test_DrainCirculation() public {
        vm.deal(address(hook), 1 ether);

        uint256 bobBefore = bob.balance;
        hook.drainCirculation(payable(bob), 0.3 ether);
        assertEq(bob.balance, bobBefore + 0.3 ether);
        assertEq(address(hook).balance, 0.7 ether);

        // amount 0 drains the rest
        hook.drainCirculation(payable(bob), 0);
        assertEq(bob.balance, bobBefore + 1 ether);
        assertEq(address(hook).balance, 0);
    }

    function test_PrintFlowViaHook() public {
        hook.printFlow(carol, 50_000 ether);
        assertEq(circ.balanceOf(carol), 50_000 ether);
    }

    function test_NonOwnerCallsRevert() public {
        vm.startPrank(alice);
        bytes memory err = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);

        vm.expectRevert(err);
        hook.startCirculation();
        vm.expectRevert(err);
        hook.drainCirculation(payable(alice), 1);
        vm.expectRevert(err);
        hook.printFlow(alice, 1);
        vm.expectRevert(err);
        hook.easeTax(1);
        vm.expectRevert(err);
        hook.setFlowRate(1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TEST
    //////////////////////////////////////////////////////////////*/
    function test_Integration_BuyRecirculateSell() public {
        hook.startCirculation();

        // seed A and B as eligible holders (so buy rewards distribute, not route to dead)
        circ.transfer(alice, 1_000_000 ether);
        circ.transfer(bob, 1_000_000 ether);

        uint256 hookStart = address(hook).balance;

        // --- A buys 1 ETH, B buys 1 ETH; each pays an exact 6% ETH tax ---
        uint256 taxA = _buy(alice, 1 ether);
        assertEq(taxA, 0.06 ether);
        uint256 taxB = _buy(bob, 1 ether);
        assertEq(taxB, 0.06 ether);

        // Reset A and B to a common reward baseline with a self-transfer (auto-settles pending).
        vm.prank(alice);
        circ.transfer(alice, circ.balanceOf(alice));
        vm.prank(bob);
        circ.transfer(bob, circ.balanceOf(bob));
        assertEq(circ.pendingFlow(alice), 0);
        assertEq(circ.pendingFlow(bob), 0);

        uint256 balA = circ.balanceOf(alice);
        uint256 balB = circ.balanceOf(bob);

        // --- carol buys 1 ETH: her reward is shared pro-rata by the passive holders A and B ---
        uint256 taxC = _buy(carol, 1 ether);
        assertEq(taxC, 0.06 ether);

        uint256 pendA = circ.pendingFlow(alice);
        uint256 pendB = circ.pendingFlow(bob);
        assertGt(pendA, 0);
        assertGt(pendB, 0);
        // proportional to balances on the same accumulator window: pendA/balA == pendB/balB
        assertApproxEqAbs(pendA * balB, pendB * balA, balA + balB);

        // --- A recirculates: receives exactly its pending, then zero ---
        uint256 aBefore = circ.balanceOf(alice);
        vm.prank(alice);
        uint256 recirculated = circ.recirculate();
        assertEq(recirculated, pendA);
        assertEq(circ.balanceOf(alice), aBefore + pendA);
        assertEq(circ.pendingFlow(alice), 0);

        // --- B sells half their CIRC, pays a 6% ETH sell tax ---
        uint256 sellAmt = circ.balanceOf(bob) / 2;
        (uint256 ethOut, uint256 sellTax) = _sell(bob, sellAmt);
        uint256 gross = ethOut + sellTax;
        assertEq(sellTax, (gross * 600) / 10_000);
        assertGt(sellTax, 0);

        // --- hook balance == 3 buy taxes (A, B, carol) + B's sell tax ---
        assertEq(address(hook).balance, hookStart + taxA + taxB + taxC + sellTax);
        assertEq(address(hook).balance, hookStart + 0.18 ether + sellTax);
    }
}
