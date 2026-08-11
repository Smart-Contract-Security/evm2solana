// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMechanic} from "../interfaces/IMechanic.sol";
import {IHolderAccounting} from "../interfaces/IHolderAccounting.sol";

import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @notice WETH vault and payout engine for protocol fees, buybacks, and holder rewards.
/// @dev All protocol-owned WETH rests here between transactions. Incoming hook
/// fees are split into treasury accrual and the free sink. Confirmed highs move
/// free-sink WETH into buyback reserve and holder reserve. Buyback reserve is
/// released only to the hook for internal execution; holder reserve is paid
/// through snapshot-weighted claims.
///
/// This contract is custody, not market control. It does not decide epochs,
/// detect all-time highs, size buybacks, unlock PoolManager liquidity, or expose
/// an admin rescue path. The hook sends accounting signals; this mechanic holds
/// buckets, enforces the tracked-WETH invariant, records execution, and pays the
/// entitled addresses.
///
/// Holder claims walk the apex record. Each claim uses the holder's snapshot
/// weight, skips accounts disqualified before confirmation, advances a bounded
/// cursor, and transfers only from reserved holder WETH. Treasury claims can
/// touch only accrued treasury WETH. Surplus WETH can be moved into the free
/// sink, but no generic sweep exists.
///
/// Every tracked wei has a bucket, every bucket has a purpose, and every payout
/// leaves an event trail.
contract Mechanic is IMechanic {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant TREASURY_FEE_BPS = 1_500;
    uint256 public constant override MAX_CLAIM_APEXES_PER_CALL = 5;

    address public immutable override weth;
    address public immutable override hook;
    address public immutable override treasury;
    address public immutable override token;

    uint256 public override freeSinkWeth;
    uint256 public override holderReservedWeth;
    uint256 public override buybackReservedWeth;
    uint256 public override treasuryAccruedWeth;
    bool public override buybackDue;
    uint256 public override buybackArmCount;
    uint256 public override buybackExecutionSignalCount;
    uint256 public override buybackExecutionSuccessCount;
    uint256 public override totalBuybackWethSpent;
    uint256 public override totalBuybackTokenBurned;
    uint256 public override holderApexCount;
    mapping(address holder => uint256 apexId) public override nextClaimApex;
    mapping(address holder => bool initialized) public override claimCursorInitialized;
    mapping(uint256 apexId => uint256 claimedWeth) public override holderApexClaimedWeth;
    mapping(uint256 contextId => bool processed) public override holderApexContextProcessed;
    mapping(uint256 contextId => uint256 apexIdPlusOne) public override holderApexIdPlusOneByContext;
    mapping(uint256 contextId => IMechanic.HolderApexSkipReason reason) public override holderApexSkipReasonByContext;
    IMechanic.HolderApex[] internal _holderApexes;
    uint48 private _lastHolderApexSnapshotBlock;

    error ZeroWeth();
    error WethHasNoCode(address weth);
    error ZeroHook();
    error ZeroTreasury();
    error ZeroToken();
    error TokenHasNoCode(address token);
    error NotHook(address caller, address expected);
    error NotTreasury(address caller, address expected);
    error WethAccountingInvariantBroken(uint256 wethBalance, uint256 trackedWeth);
    error InsufficientFreeSinkWeth(uint256 requestedWeth, uint256 availableWeth);
    error WethTransferFailed(address to, uint256 amount);
    error InvalidBuybackExecutionRecord(uint256 spentWeth, uint256 tokenBurned);
    error HolderApexContextAlreadyProcessed(uint256 contextId);
    error HolderContextNotClosed(uint256 contextId, IHolderAccounting.HolderContextStatus status);
    error InvalidHolderDenominator(uint256 totalSnapshotWeight, uint256 finalDisqualifiedWeight);
    error HolderApexSnapshotOutOfOrder(uint48 snapshotBlock, uint48 lastSnapshotBlock);
    error InvalidHolderApexId(uint256 apexId);
    error HolderApexNotRecordedForContext(uint256 contextId);
    error ZeroClaimRecipient();
    error InvalidHolderApexDenominator(uint256 apexId);
    error InvalidHolderWeight(uint256 apexId, uint256 holderWeight, uint256 eligibleWeight);
    error HolderApexOverclaimed(uint256 apexId, uint256 claimedWeth, uint256 holderWeth);
    error InsufficientHolderReservedWeth(uint256 requestedWeth, uint256 availableWeth);

    event SwapFeeRecorded(uint256 totalFeeWeth, uint256 treasuryShareWeth, uint256 sinkShareWeth);
    event TreasuryWethClaimed(address indexed treasury, uint256 amountWeth);
    event SurplusWethSwept(uint256 surplusWeth);
    event BuybackArmed(uint256 reserveWeth, uint256 armCount);
    event BuybackExecutionSignaled(uint256 reserveWeth, uint256 signalCount);
    event BuybackWethClaimed(uint256 amountWeth, uint256 reserveRemainingWeth);
    event BuybackExecutionRecorded(uint256 spentWeth, uint256 tokenBurned, uint256 successCount);
    event ApexPayoutReserved(uint256 buybackWeth, uint256 holderWeth, uint256 freeSinkRemainingWeth);
    event BuybackDueCleared();
    event HolderApexRecorded(
        uint256 indexed holderApexId,
        uint256 indexed contextId,
        uint48 snapshotBlock,
        uint64 snapshotTimestamp,
        uint64 confirmationEpochId,
        uint256 holderWeth,
        uint256 eligibleWeight,
        uint256 totalSnapshotWeight,
        uint256 finalDisqualifiedWeight
    );
    event HolderApexSkipped(
        uint256 indexed contextId, IMechanic.HolderApexSkipReason reason, uint256 buybackWeth, uint256 nominalHolderWeth
    );
    event HolderRewardsClaimed(
        address indexed holder,
        address indexed recipient,
        uint256 startApexId,
        uint256 endApexIdExclusive,
        uint256 processedApexes,
        uint256 paidWeth,
        uint256 nextClaimApex
    );

    constructor(address weth_, address hook_, address treasury_, address token_) {
        if (weth_ == address(0)) revert ZeroWeth();
        if (weth_.code.length == 0) revert WethHasNoCode(weth_);
        if (hook_ == address(0)) revert ZeroHook();
        if (treasury_ == address(0)) revert ZeroTreasury();
        if (token_ == address(0)) revert ZeroToken();
        if (token_.code.length == 0) revert TokenHasNoCode(token_);

        weth = weth_;
        hook = hook_;
        treasury = treasury_;
        token = token_;
    }

    function totalTrackedWeth() public view override returns (uint256) {
        return freeSinkWeth + holderReservedWeth + buybackReservedWeth + treasuryAccruedWeth;
    }

    function surplusWeth() public view returns (uint256) {
        uint256 balance = IERC20Minimal(weth).balanceOf(address(this));
        uint256 tracked = totalTrackedWeth();
        if (balance <= tracked) return 0;
        return balance - tracked;
    }

    function holderApexById(uint256 apexId) external view override returns (IMechanic.HolderApex memory) {
        if (apexId >= holderApexCount) revert InvalidHolderApexId(apexId);
        return _holderApexes[apexId];
    }

    function holderApexByContextId(uint256 contextId) external view override returns (IMechanic.HolderApex memory) {
        uint256 apexIdPlusOne = holderApexIdPlusOneByContext[contextId];
        if (apexIdPlusOne == 0) revert HolderApexNotRecordedForContext(contextId);
        return _holderApexes[apexIdPlusOne - 1];
    }

    function recordSwapFee(uint256 totalFeeWeth) external override {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);
        if (totalFeeWeth == 0) return;

        uint256 treasuryShare = FullMath.mulDiv(totalFeeWeth, TREASURY_FEE_BPS, BPS_DENOMINATOR);
        uint256 sinkShare = totalFeeWeth - treasuryShare;

        treasuryAccruedWeth += treasuryShare;
        freeSinkWeth += sinkShare;

        _assertWethInvariant();

        emit SwapFeeRecorded(totalFeeWeth, treasuryShare, sinkShare);
    }

    /// @dev Treasury withdrawals are limited to the accrued WETH bucket. They cannot touch sink,
    /// holder-reserved, or buyback-reserved WETH.
    function claimTreasuryWeth() external override returns (uint256 claimedWeth) {
        if (msg.sender != treasury) revert NotTreasury(msg.sender, treasury);

        claimedWeth = treasuryAccruedWeth;
        if (claimedWeth == 0) return 0;

        treasuryAccruedWeth = 0;

        if (!IERC20Minimal(weth).transfer(treasury, claimedWeth)) revert WethTransferFailed(treasury, claimedWeth);

        _assertWethInvariant();

        emit TreasuryWethClaimed(treasury, claimedWeth);
    }

    /// @dev The first eligible buy arms the buyback signal; a later eligible buy may execute it.
    function notifyEligibleExactInputBuy()
        external
        virtual
        override
        returns (IMechanic.BuybackNotificationResult result)
    {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);

        uint256 reserve = buybackReservedWeth;
        if (reserve == 0) return IMechanic.BuybackNotificationResult.NoReserve;

        if (!buybackDue) {
            buybackDue = true;
            buybackArmCount++;
            emit BuybackArmed(reserve, buybackArmCount);
            return IMechanic.BuybackNotificationResult.Armed;
        }

        buybackExecutionSignalCount++;
        emit BuybackExecutionSignaled(reserve, buybackExecutionSignalCount);
        return IMechanic.BuybackNotificationResult.ExecutionSignaled;
    }

    function claimBuybackWeth(uint256 requestedWeth) external virtual override returns (uint256 claimedWeth) {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);

        uint256 reserve = buybackReservedWeth;
        if (requestedWeth == 0 || reserve == 0) return 0;

        claimedWeth = requestedWeth < reserve ? requestedWeth : reserve;
        buybackReservedWeth = reserve - claimedWeth;

        if (!IERC20Minimal(weth).transfer(hook, claimedWeth)) revert WethTransferFailed(hook, claimedWeth);

        _assertWethInvariant();

        emit BuybackWethClaimed(claimedWeth, buybackReservedWeth);
    }

    /// @dev Trusts the authorized hook to report values from a completed internal buyback self-call.
    /// The hook spends WETH, burns received tokens, then reports the actual execution record here.
    function recordBuybackExecution(uint256 spentWeth, uint256 tokenBurned) external virtual override {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);
        if (spentWeth == 0 || tokenBurned == 0) {
            revert InvalidBuybackExecutionRecord(spentWeth, tokenBurned);
        }

        buybackDue = false;
        buybackExecutionSuccessCount++;
        totalBuybackWethSpent += spentWeth;
        totalBuybackTokenBurned += tokenBurned;

        _assertWethInvariant();

        emit BuybackExecutionRecorded(spentWeth, tokenBurned, buybackExecutionSuccessCount);
    }

    function reserveApexPayout(uint256 buybackWeth, uint256 holderWeth) external override {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);

        uint256 totalPayout = buybackWeth + holderWeth;
        if (totalPayout > freeSinkWeth) revert InsufficientFreeSinkWeth(totalPayout, freeSinkWeth);

        if (totalPayout != 0) {
            freeSinkWeth -= totalPayout;
            buybackReservedWeth += buybackWeth;
            holderReservedWeth += holderWeth;
        }

        _assertWethInvariant();

        emit ApexPayoutReserved(buybackWeth, holderWeth, freeSinkWeth);
    }

    function reserveApexPayoutWithHolderRecord(uint256 buybackWeth, uint256 holderWeth, uint256 contextId)
        external
        override
        returns (bool holderApexCreated, uint256 holderApexId)
    {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);
        if (holderApexContextProcessed[contextId]) revert HolderApexContextAlreadyProcessed(contextId);

        IHolderAccounting.HolderContext memory context = IHolderAccounting(token).holderContext(contextId);
        if (context.status != IHolderAccounting.HolderContextStatus.Closed) {
            revert HolderContextNotClosed(contextId, context.status);
        }

        IMechanic.HolderApexSkipReason skipReason = _denominatorFreeSkipReason(context, holderWeth);
        uint256 totalSnapshotWeight = 0;
        uint256 eligibleWeight = 0;
        if (skipReason == IMechanic.HolderApexSkipReason.None) {
            totalSnapshotWeight =
                IHolderAccounting(token).globalWeightAtSnapshot(context.snapshotBlock, context.snapshotTimestamp);
            if (context.finalDisqualifiedWeight > totalSnapshotWeight) {
                revert InvalidHolderDenominator(totalSnapshotWeight, context.finalDisqualifiedWeight);
            }
            // Holder reward denominator is the snapshot weight minus accounts disqualified before confirmation.
            eligibleWeight = totalSnapshotWeight - context.finalDisqualifiedWeight;
            if (eligibleWeight == 0) skipReason = IMechanic.HolderApexSkipReason.ZeroEligibleWeight;
        }

        uint256 requiredFreeSink =
            skipReason == IMechanic.HolderApexSkipReason.None ? buybackWeth + holderWeth : buybackWeth;
        if (requiredFreeSink > freeSinkWeth) revert InsufficientFreeSinkWeth(requiredFreeSink, freeSinkWeth);

        holderApexContextProcessed[contextId] = true;
        if (skipReason == IMechanic.HolderApexSkipReason.None) {
            holderApexId = holderApexCount;
            _recordHolderApex(holderApexId, contextId, context, holderWeth, eligibleWeight, totalSnapshotWeight);
            holderApexCreated = true;
            holderReservedWeth += holderWeth;
        } else {
            holderApexSkipReasonByContext[contextId] = skipReason;
            emit HolderApexSkipped(contextId, skipReason, buybackWeth, holderWeth);
        }

        if (requiredFreeSink != 0) {
            freeSinkWeth -= requiredFreeSink;
            buybackReservedWeth += buybackWeth;
        }

        _assertWethInvariant();
        emit ApexPayoutReserved(
            buybackWeth, skipReason == IMechanic.HolderApexSkipReason.None ? holderWeth : 0, freeSinkWeth
        );
    }

    function claim(uint256 maxApexes) external override returns (uint256 paidWeth, uint256 processedApexes) {
        return _claim(msg.sender, msg.sender, maxApexes);
    }

    function claimTo(address recipient, uint256 maxApexes)
        external
        override
        returns (uint256 paidWeth, uint256 processedApexes)
    {
        if (recipient == address(0)) revert ZeroClaimRecipient();
        return _claim(msg.sender, recipient, maxApexes);
    }

    function clearBuybackDue() external override {
        if (msg.sender != hook) revert NotHook(msg.sender, hook);
        if (!buybackDue) return;

        buybackDue = false;

        emit BuybackDueCleared();
    }

    function sweepSurplusWethToFreeSink() external {
        uint256 balance = IERC20Minimal(weth).balanceOf(address(this));
        uint256 tracked = totalTrackedWeth();
        if (balance < tracked) revert WethAccountingInvariantBroken(balance, tracked);

        uint256 surplus = balance - tracked;
        if (surplus == 0) return;

        freeSinkWeth += surplus;

        emit SurplusWethSwept(surplus);
    }

    function _reserveBuybackFromFreeSink(uint256 amount) internal {
        if (amount > freeSinkWeth) revert InsufficientFreeSinkWeth(amount, freeSinkWeth);

        freeSinkWeth -= amount;
        buybackReservedWeth += amount;

        _assertWethInvariant();
    }

    function _claim(address holder, address recipient, uint256 maxApexes)
        private
        returns (uint256 paidWeth, uint256 processedApexes)
    {
        if (maxApexes == 0) return (0, 0);

        uint256 apexCount = holderApexCount;
        if (apexCount == 0) return (0, 0);

        uint256 cursor = nextClaimApex[holder];
        if (!claimCursorInitialized[holder]) {
            uint64 firstHeld = IHolderAccounting(token).firstHeldBlock(holder);
            if (firstHeld == 0) return (0, 0);

            cursor = _firstClaimableApex(firstHeld, apexCount);
            nextClaimApex[holder] = cursor;
            claimCursorInitialized[holder] = true;
        }

        if (cursor >= apexCount) return (0, 0);

        uint256 requested = maxApexes < MAX_CLAIM_APEXES_PER_CALL ? maxApexes : MAX_CLAIM_APEXES_PER_CALL;
        uint256 remaining = apexCount - cursor;
        processedApexes = requested < remaining ? requested : remaining;
        uint256 endApexIdExclusive = cursor + processedApexes;

        uint256[] memory claimedApexIds = new uint256[](MAX_CLAIM_APEXES_PER_CALL);
        uint256[] memory claimedPayouts = new uint256[](MAX_CLAIM_APEXES_PER_CALL);
        uint256 claimedCount = 0;
        IHolderAccounting holderToken = IHolderAccounting(token);

        for (uint256 apexId = cursor; apexId < endApexIdExclusive; apexId++) {
            IMechanic.HolderApex memory apex = _holderApexes[apexId];
            if (apex.eligibleWeight == 0) revert InvalidHolderApexDenominator(apexId);

            uint256 payout = 0;
            if (!holderToken.isAccountDisqualifiedForConfirmation(holder, apex.contextId, apex.confirmationEpochId)) {
                uint256 holderWeight =
                    holderToken.accountWeightAtSnapshot(holder, apex.snapshotBlock, apex.snapshotTimestamp);
                if (holderWeight > apex.eligibleWeight) {
                    revert InvalidHolderWeight(apexId, holderWeight, apex.eligibleWeight);
                }
                if (holderWeight != 0) {
                    payout = FullMath.mulDiv(apex.holderWeth, holderWeight, apex.eligibleWeight);
                }
            }

            if (payout != 0) {
                uint256 newClaimed = holderApexClaimedWeth[apexId] + payout;
                if (newClaimed > apex.holderWeth) revert HolderApexOverclaimed(apexId, newClaimed, apex.holderWeth);
                claimedApexIds[claimedCount] = apexId;
                claimedPayouts[claimedCount] = payout;
                claimedCount++;
                paidWeth += payout;
            }
        }

        if (paidWeth > holderReservedWeth) revert InsufficientHolderReservedWeth(paidWeth, holderReservedWeth);

        nextClaimApex[holder] = endApexIdExclusive;
        for (uint256 i = 0; i < claimedCount; i++) {
            holderApexClaimedWeth[claimedApexIds[i]] += claimedPayouts[i];
        }

        if (paidWeth != 0) {
            holderReservedWeth -= paidWeth;
            if (!IERC20Minimal(weth).transfer(recipient, paidWeth)) revert WethTransferFailed(recipient, paidWeth);
        }

        _assertWethInvariant();
        emit HolderRewardsClaimed(
            holder, recipient, cursor, endApexIdExclusive, processedApexes, paidWeth, nextClaimApex[holder]
        );
    }

    function _firstClaimableApex(uint64 firstHeldBlock_, uint256 apexCount) private view returns (uint256) {
        uint256 low = 0;
        uint256 high = apexCount;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (uint64(_holderApexes[mid].snapshotBlock) < firstHeldBlock_) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return low;
    }

    function _denominatorFreeSkipReason(IHolderAccounting.HolderContext memory context, uint256 holderWeth)
        private
        pure
        returns (IMechanic.HolderApexSkipReason)
    {
        if (context.epochId == 0) return IMechanic.HolderApexSkipReason.EpochZero;
        if (holderWeth == 0) return IMechanic.HolderApexSkipReason.ZeroHolderWeth;
        return IMechanic.HolderApexSkipReason.None;
    }

    function _recordHolderApex(
        uint256 holderApexId,
        uint256 contextId,
        IHolderAccounting.HolderContext memory context,
        uint256 holderWeth,
        uint256 eligibleWeight,
        uint256 totalSnapshotWeight
    ) private {
        if (context.snapshotBlock < _lastHolderApexSnapshotBlock) {
            revert HolderApexSnapshotOutOfOrder(context.snapshotBlock, _lastHolderApexSnapshotBlock);
        }

        IMechanic.HolderApex memory apex = IMechanic.HolderApex({
            contextId: contextId,
            snapshotBlock: context.snapshotBlock,
            snapshotTimestamp: context.snapshotTimestamp,
            confirmationEpochId: context.confirmationEpochId,
            holderWeth: holderWeth,
            eligibleWeight: eligibleWeight,
            totalSnapshotWeight: totalSnapshotWeight,
            finalDisqualifiedWeight: context.finalDisqualifiedWeight
        });
        _holderApexes.push(apex);
        holderApexCount = holderApexId + 1;
        holderApexIdPlusOneByContext[contextId] = holderApexId + 1;
        _lastHolderApexSnapshotBlock = context.snapshotBlock;

        emit HolderApexRecorded(
            holderApexId,
            contextId,
            context.snapshotBlock,
            context.snapshotTimestamp,
            context.confirmationEpochId,
            holderWeth,
            eligibleWeight,
            totalSnapshotWeight,
            context.finalDisqualifiedWeight
        );
    }

    function _assertWethInvariant() internal view {
        uint256 balance = IERC20Minimal(weth).balanceOf(address(this));
        uint256 tracked = totalTrackedWeth();
        if (balance < tracked) revert WethAccountingInvariantBroken(balance, tracked);
    }
}
