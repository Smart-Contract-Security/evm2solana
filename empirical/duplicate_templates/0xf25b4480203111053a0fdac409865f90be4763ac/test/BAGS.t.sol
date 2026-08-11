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

import {BAGS} from "../contracts/BAGS.sol";
import {BAGSHook, IBAGS} from "../contracts/BAGSHook.sol";
import {Create2Factory} from "../contracts/Create2Factory.sol";

/*//////////////////////////////////////////////////////////////
                         TOKEN-ONLY TESTS
    Exercise the MasterChef accumulator with no V4 dependency.
    bagger is a dedicated EOA (pranked) so the deployer treasury
    is a normal eligible holder. The deployer is set bagless in
    setUp so `eligibleSupply` == the holders we create.
//////////////////////////////////////////////////////////////*/
contract BAGSTokenTest is Test {
    BAGS bags;
    address BAGGER = makeAddr("bagger");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        bags = new BAGS(address(this));
        bags.setBagger(BAGGER); // marks BAGGER + token contract bagless
        bags.setBagless(address(this), true); // deployer treasury not eligible
    }

    function test_InitialSupply() public view {
        assertEq(bags.totalSupply(), 1_000_000_000 ether);
        assertEq(bags.balanceOf(address(this)), 1_000_000_000 ether);
        assertEq(bags.name(), "Beta Alpha Gamma Sigma");
        assertEq(bags.symbol(), "BAGS");
    }

    function test_SetBaggerIsOneShot() public {
        vm.expectRevert(BAGS.BaggerAlreadySet.selector);
        bags.setBagger(alice);
    }

    function test_FillBagOnlyBagger() public {
        vm.expectRevert(BAGS.NotBagger.selector);
        vm.prank(alice);
        bags.fillBag(1 ether);
    }

    function test_FillBagBumpsAcc() public {
        bags.transfer(alice, 1000 ether); // eligibleSupply = 1000
        vm.prank(BAGGER);
        bags.fillBag(100 ether);

        assertEq(bags.accTokensPerShare(), (100 ether * 1e18) / 1000 ether);
        // reward is minted into the token contract, held until secured
        assertEq(bags.balanceOf(address(bags)), 100 ether);
    }

    function test_PendingBagProRata() public {
        bags.transfer(alice, 60 ether);
        bags.transfer(bob, 40 ether); // eligibleSupply = 100, acc becomes exactly 1e18
        vm.prank(BAGGER);
        bags.fillBag(100 ether);

        assertEq(bags.pendingBag(alice), 60 ether);
        assertEq(bags.pendingBag(bob), 40 ether);
    }

    function test_SecureBagTransfersExactAndZeros() public {
        bags.transfer(alice, 100 ether); // eligibleSupply = 100
        vm.prank(BAGGER);
        bags.fillBag(50 ether); // pending(alice) = 50

        uint256 pre = bags.balanceOf(alice);
        vm.prank(alice);
        uint256 secured = bags.secureBag();

        assertEq(secured, 50 ether);
        assertEq(bags.balanceOf(alice), pre + 50 ether);
        assertEq(bags.pendingBag(alice), 0);
    }

    function test_TransferAutoSettles() public {
        bags.transfer(alice, 10_000_000 ether); // alice holds 10M, sole eligible holder
        vm.prank(BAGGER);
        bags.fillBag(10_000_000 ether); // acc = 1e18 → pending(alice) = 10M

        assertEq(bags.pendingBag(alice), 10_000_000 ether);

        vm.prank(alice);
        bags.transfer(bob, 5_000_000 ether);

        // A's pending was paid out during the transfer (auto-settle on _update).
        assertEq(bags.pendingBag(alice), 0);
        assertEq(bags.balanceOf(alice), 15_000_000 ether);
        assertEq(bags.balanceOf(bob), 5_000_000 ether);
        assertEq(bags.pendingBag(bob), 0);
        assertEq(bags.balanceOf(address(bags)), 0);
    }

    function test_BaglessDoNotEarn() public {
        bags.transfer(alice, 100 ether);
        bags.setBagless(alice, true); // alice now bagless
        bags.transfer(bob, 100 ether); // bob eligible so fillBag doesn't route to dead

        vm.prank(BAGGER);
        bags.fillBag(50 ether);

        assertEq(bags.pendingBag(alice), 0);
        assertGt(bags.pendingBag(bob), 0);
    }

    function test_DropBagOnlyBagger() public {
        vm.expectRevert(BAGS.NotBagger.selector);
        vm.prank(alice);
        bags.dropBag(bob, 1 ether);

        vm.prank(BAGGER);
        bags.dropBag(carol, 777 ether);
        assertEq(bags.balanceOf(carol), 777 ether);
    }
}

/*//////////////////////////////////////////////////////////////
                          HOOK + V4 TESTS
    Deploy a real PoolManager + routers, mine a hook address with
    the 0x00CC flag bits via HookMiner, init an ETH/BAGS pool and
    seed deep liquidity. Pool: currency0 = ETH (address 0),
    currency1 = BAGS (always > 0).
//////////////////////////////////////////////////////////////*/
contract BAGSHookTest is Test, Deployers {
    BAGS bags;
    BAGSHook hook;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    // full range for tickSpacing 60
    int24 constant MIN_TICK = -887220;
    int24 constant MAX_TICK = 887220;

    // 3% of tokens-received expressed as 1e18-scaled tokens per ETH-wei of net input.
    // rate = 1e18 → reward(tokens) = netEth (in wei). Keeps deposits to round numbers in tests.
    uint256 constant RATE = 1e18;

    function setUp() public {
        deployFreshManagerAndRouters();

        // 1. token
        bags = new BAGS(address(this));

        // 2. mine + deploy hook to an address with the required flag bits.
        //    Deploy THROUGH a CREATE2 factory to mirror production: msg.sender inside the hook
        //    constructor is the factory, so ownership must come from the explicit initialOwner arg.
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        Create2Factory factory = new Create2Factory();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(manager)), IBAGS(address(bags)), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(factory), flags, type(BAGSHook).creationCode, ctorArgs);
        address deployed = factory.deploy(abi.encodePacked(type(BAGSHook).creationCode, ctorArgs), salt);
        hook = BAGSHook(payable(deployed));
        require(deployed == hookAddr, "hook address mismatch");
        // sanity: lowest 14 bits == 0x00CC
        assertEq(uint160(address(hook)) & 0x3FFF, 0x00CC);
        // ownership came from the constructor arg, NOT the factory (regression guard)
        assertEq(hook.owner(), address(this));
        assertTrue(hook.owner() != address(factory));

        // 3. wire bagger + bagless (mirror 01-deploy.js, plus deployer treasury + routers)
        bags.setBagger(address(hook)); // marks hook + token contract bagless
        bags.setBagless(address(0xdEaD), true);
        bags.setBagless(address(manager), true);
        bags.setBagless(address(modifyLiquidityRouter), true);
        bags.setBagless(address(swapRouter), true);
        bags.setBagless(address(this), true); // deployer treasury not eligible

        // 4. init ETH/BAGS pool (fee 0, tickSpacing 60) at 1:1
        (key,) = initPool(
            CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(bags)), IHooks(address(hook)), 0, 60, SQRT_PRICE_1_1
        );

        // 5. seed deep full-range liquidity (~100 ETH / ~100 BAGS)
        vm.deal(address(this), 1000 ether);
        bags.approve(address(modifyLiquidityRouter), type(uint256).max);
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
        hook.setBagRate(RATE);
    }

    // ---- helpers ----

    function _buy(address who, uint256 ethIn) internal returns (uint256 hookGain) {
        vm.deal(who, who.balance + ethIn);
        uint256 before = address(hook).balance;
        vm.prank(who);
        swapRouter.swap{value: ethIn}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true, // ETH(c0) -> BAGS(c1) == BUY
                amountSpecified: -int256(ethIn), // exact input
                sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        hookGain = address(hook).balance - before;
    }

    // returns (eth received by seller, sell tax taken by hook)
    function _sell(address who, uint256 bagsIn) internal returns (uint256 ethOut, uint256 hookGain) {
        vm.prank(who);
        bags.approve(address(swapRouter), bagsIn);
        uint256 ethBefore = who.balance;
        uint256 hookBefore = address(hook).balance;
        vm.prank(who);
        swapRouter.swap{value: 0}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: false, // BAGS(c1) -> ETH(c0) == SELL
                amountSpecified: -int256(bagsIn), // exact input
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

    function test_OpenBagsThenSwapSucceeds() public {
        hook.openBags();
        uint256 gain = _buy(alice, 1 ether);
        assertGt(bags.balanceOf(alice), 0); // received BAGS
        assertEq(gain, 0.03 ether); // and paid 3% tax
    }

    function test_OpenBagsIsOneWay() public {
        hook.openBags();
        vm.expectRevert(BAGSHook.AlreadyEnabled.selector);
        hook.openBags();
    }

    // ---- buy tax ----

    function test_BuyTaxIs3PercentOfInput() public {
        hook.openBags();
        uint256 gain = _buy(alice, 1 ether);
        assertEq(gain, 0.03 ether); // exactly 3% of the 1 ETH input
        assertEq(hook.totalEthCollected(), 0.03 ether);
    }

    function test_BuyFillsBagToTokenContract() public {
        hook.openBags();
        // need an eligible holder so the reward is distributed (not routed to dead)
        bags.transfer(alice, 1000 ether);

        uint256 contractBefore = bags.balanceOf(address(bags));
        _buy(bob, 1 ether);

        // net ETH = 1 - 0.03 = 0.97; reward = netEth * RATE / 1e18 = 0.97 ether tokens
        uint256 expectedReward = (0.97 ether * RATE) / 1e18;
        assertEq(bags.balanceOf(address(bags)) - contractBefore, expectedReward);
        assertEq(hook.totalRewardsMinted(), expectedReward);
    }

    // ---- sell tax (BalanceDelta sign convention) ----

    function test_SellTaxIs3PercentOfOutput() public {
        hook.openBags();
        // give bob BAGS to sell
        bags.transfer(bob, 1_000_000 ether);

        (uint256 ethOut, uint256 sellTax) = _sell(bob, 100 ether);

        assertGt(sellTax, 0);
        // gross output = what the seller netted + what the hook skimmed
        uint256 gross = ethOut + sellTax;
        // exact 3%: tax == gross * 300 / 10000 (integer math, same as the hook)
        assertEq(sellTax, (gross * 300) / 10_000);
        // and the seller received 97%, not 100%
        assertEq(ethOut, gross - sellTax);
    }

    // ---- owner powers ----

    function test_LightenBagOnlyDecreases() public {
        hook.lightenBag(200);
        assertEq(hook.taxBps(), 200);

        vm.expectRevert(BAGSHook.TaxCanOnlyDecrease.selector);
        hook.lightenBag(300); // higher than current

        vm.expectRevert(BAGSHook.TaxCanOnlyDecrease.selector);
        hook.lightenBag(200); // equal also rejected
    }

    function test_EmptyBags() public {
        vm.deal(address(hook), 1 ether);

        uint256 bobBefore = bob.balance;
        hook.emptyBags(payable(bob), 0.3 ether);
        assertEq(bob.balance, bobBefore + 0.3 ether);
        assertEq(address(hook).balance, 0.7 ether);

        // amount 0 drains the rest
        hook.emptyBags(payable(bob), 0);
        assertEq(bob.balance, bobBefore + 1 ether);
        assertEq(address(hook).balance, 0);
    }

    function test_DropBagViaHook() public {
        hook.dropBag(carol, 50_000 ether);
        assertEq(bags.balanceOf(carol), 50_000 ether);
    }

    function test_NonOwnerCallsRevert() public {
        vm.startPrank(alice);
        bytes memory err = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);

        vm.expectRevert(err);
        hook.openBags();
        vm.expectRevert(err);
        hook.emptyBags(payable(alice), 1);
        vm.expectRevert(err);
        hook.dropBag(alice, 1);
        vm.expectRevert(err);
        hook.lightenBag(1);
        vm.expectRevert(err);
        hook.setBagRate(1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TEST
    //////////////////////////////////////////////////////////////*/
    function test_Integration_BuySecureSell() public {
        hook.openBags();

        // seed A and B as eligible holders (so buy rewards distribute, not route to dead)
        bags.transfer(alice, 1_000_000 ether);
        bags.transfer(bob, 1_000_000 ether);

        uint256 hookStart = address(hook).balance;

        // --- A buys 1 ETH, B buys 1 ETH; each pays an exact 3% ETH tax ---
        uint256 taxA = _buy(alice, 1 ether);
        assertEq(taxA, 0.03 ether);
        uint256 taxB = _buy(bob, 1 ether);
        assertEq(taxB, 0.03 ether);

        // Reset A and B to a common reward baseline with a self-transfer (auto-settles pending).
        vm.prank(alice);
        bags.transfer(alice, bags.balanceOf(alice));
        vm.prank(bob);
        bags.transfer(bob, bags.balanceOf(bob));
        assertEq(bags.pendingBag(alice), 0);
        assertEq(bags.pendingBag(bob), 0);

        uint256 balA = bags.balanceOf(alice);
        uint256 balB = bags.balanceOf(bob);

        // --- carol buys 1 ETH: her reward is shared pro-rata by the passive holders A and B ---
        uint256 taxC = _buy(carol, 1 ether);
        assertEq(taxC, 0.03 ether);

        uint256 pendA = bags.pendingBag(alice);
        uint256 pendB = bags.pendingBag(bob);
        assertGt(pendA, 0);
        assertGt(pendB, 0);
        // proportional to balances on the same accumulator window: pendA/balA == pendB/balB
        assertApproxEqAbs(pendA * balB, pendB * balA, balA + balB);

        // --- A secures its bag: receives exactly its pending, then zero ---
        uint256 aBefore = bags.balanceOf(alice);
        vm.prank(alice);
        uint256 secured = bags.secureBag();
        assertEq(secured, pendA);
        assertEq(bags.balanceOf(alice), aBefore + pendA);
        assertEq(bags.pendingBag(alice), 0);

        // --- B sells half their BAGS, pays a 3% ETH sell tax ---
        uint256 sellAmt = bags.balanceOf(bob) / 2;
        (uint256 ethOut, uint256 sellTax) = _sell(bob, sellAmt);
        uint256 gross = ethOut + sellTax;
        assertEq(sellTax, (gross * 300) / 10_000);
        assertGt(sellTax, 0);

        // --- hook balance == 3 buy taxes (A, B, carol) + B's sell tax ---
        assertEq(address(hook).balance, hookStart + taxA + taxB + taxC + sellTax);
        assertEq(address(hook).balance, hookStart + 0.09 ether + sellTax);
    }
}
