// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ISettlementPool } from "../interfaces/ISettlementPool.sol";
import { ISettlementPoolFactory } from "../interfaces/ISettlementPoolFactory.sol";
import { IOracle } from "../oracles/IOracle.sol";
import { Errors } from "../libraries/helpers/Errors.sol";
import { FeeLogic } from "../libraries/logic/FeeLogic.sol";
import { PositionTypes } from "../libraries/types/Position.sol";
import { MathUtils } from "../../v2.1/libraries/math/MathUtils.sol";

/**
 * @title SettlementPool
 * @notice Cohort-accounted Settlement v3 pool. Deposits are always accepted,
 *         but capital only participates in positions it actually funded.
 *
 *         There is no LP ERC20/ERC4626 token in the core pool. LP balances are
 *         internal non-transferable cohort units. A cohort is sealed the first
 *         time it funds a position; later deposits enter a fresh cohort and
 *         cannot share old position PnL.
 */
contract SettlementPool is ISettlementPool, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Re-exposed for off-chain consumers; actual fee math lives in FeeLogic.
  uint256 public constant PROTOCOL_FEE_BPS = FeeLogic.PROTOCOL_FEE_BPS; // 10%
  uint256 public constant ACC_PRECISION = 1e30;
  /// @notice Maximum positions accepted in a single fill call (audit I-02).
  ///         Caps the filler-bot footgun of submitting an oversized batch that
  ///         would revert atomically after burning gas; the call now reverts
  ///         early with `BatchTooLarge` instead.
  uint256 public constant MAX_BATCH_SIZE = 100;

  /*//////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  struct Cohort {
    uint256 idleDebt;
    uint256 deployedDebt;
    uint256 unitSupply;
    uint256 activePositions;
    uint256 accYieldPerUnit;
    bool isSealed;
  }

  struct UserCohort {
    uint256 units;
    uint256 yieldDebt;
    uint256 pendingYield;
  }

  /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  IOracle public immutable oracle;
  IERC20 public immutable collateralAsset;
  IERC20 public immutable debtAsset;
  ISettlementPoolFactory public immutable factory;

  /// @notice LTV cushion in RAY (e.g. 1e26 = 10%).
  uint256 public immutable buffer;
  /// @notice Floor fee at t = 0 in RAY (must be < buffer).
  uint256 public immutable floor;
  /// @notice Buffer-window in seconds (> 0).
  uint256 public immutable window;
  /// @notice Minimum D per open() (debt atomic units).
  uint256 public immutable minPositionSize;
  /// @notice Minimum amount per deposit (debt atomic units).
  uint256 public immutable minDepositSize;

  /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
  //////////////////////////////////////////////////////////////*/

  mapping(uint256 => PositionTypes.Position) public positions;
  mapping(uint256 => PositionTypes.FundingSlice[]) public positionFundingSlices;
  uint256 public nextId;
  uint256 public nextFillId;

  mapping(uint256 => Cohort) public cohorts;
  mapping(address => mapping(uint256 => UserCohort)) public userCohorts;
  uint256 public currentCohortId;

  /// @notice LP-supplied debt asset NOT currently deployed.
  uint256 public totalDebtAssetAtRest;
  /// @notice Sum of D across currently-open positions.
  uint256 public totalDebtAssetDeployed;
  /// @notice Sum of C across currently-open positions.
  uint256 public totalCollateralLocked;

  /// @notice Sum of pending debt-asset yield across all user cohorts.
  uint256 public totalPendingYield;
  /// @notice Sum of debt-asset LP yield accrued to cohort accumulators but not yet paid.
  uint256 public totalLpYieldLiability;

  /// @notice Per-borrower fallback bucket (debt asset).
  mapping(address => uint256) public pendingRefund;
  /// @notice Sum of pendingRefund[] across all borrowers.
  uint256 public totalPendingRefund;

  /// @notice Accumulated protocol fees by asset; sweepable by factory owner.
  mapping(address => uint256) public accProtocolFee;

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event Deposited(address indexed caller, address indexed receiver, uint256 indexed cohortId, uint256 assets, uint256 units);
  event Redeemed(address indexed owner, address indexed receiver, uint256 indexed cohortId, uint256 assets, uint256 units);
  event CohortSealed(uint256 indexed cohortId);

  event PositionOpened(
    uint256 indexed id,
    address indexed borrower,
    uint128 C,
    uint128 D,
    uint256 rateAtOpen,
    uint96 openTime
  );

  event PositionClosed(
    uint256 indexed id,
    address indexed closer,
    uint256 fee,
    uint256 debtPaid,
    uint256 fillerCollateralOut,
    uint256 lpYield,
    uint256 lpPrincipalLoss,
    uint256 fillerProtocolFee,
    uint256 cpProtocolFee
  );

  event PositionPartiallyFilled(
    uint256 indexed id,
    address indexed closer,
    uint256 fee,
    uint256 debtPaid,
    uint256 fillerCollateralOut,
    uint256 lpYield,
    uint256 lpPrincipalLoss,
    uint256 fillerProtocolFee,
    uint256 cpProtocolFee,
    uint128 remainingC,
    uint128 remainingD
  );

  event RefundPaid(uint256 indexed id, address indexed borrower, uint256 amount);
  event RefundQueued(uint256 indexed id, address indexed borrower, uint256 amount);
  event RefundClaimed(address indexed borrower, uint256 amount);
  event YieldClaimed(address indexed lp, uint256 amount);
  event ExcessSwept(address indexed asset, address indexed to, uint256 amount);
  event ProtocolFeesSwept(address indexed asset, address indexed to, uint256 amount);
  /// @notice Emitted when protocol fees accrue on a close. Indexers track
  ///         lifetime totals by summing the `amount`s. `accProtocolFee[asset]`
  ///         only reflects the unswept balance; this event captures the
  ///         monotonic gross.
  event ProtocolFeeAccrued(address indexed asset, uint256 amount);

  /*//////////////////////////////////////////////////////////////
                              MODIFIERS
  //////////////////////////////////////////////////////////////*/

  /// @dev See `libraries/helpers/Errors.sol` for the cross-contract error catalog.
  modifier onlyOwner() {
    if (msg.sender != factory.owner()) revert Errors.NotOwner();
    _;
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(
    IOracle oracle_,
    IERC20 collateralAsset_,
    IERC20 debtAsset_,
    ISettlementPoolFactory factory_,
    uint256 buffer_,
    uint256 floor_,
    uint256 window_,
    uint256 minPositionSize_,
    uint256 minDepositSize_
  ) {
    if (address(oracle_) == address(0)) revert Errors.ZeroAddress();
    if (address(collateralAsset_) == address(0)) revert Errors.ZeroAddress();
    if (address(debtAsset_) == address(0)) revert Errors.ZeroAddress();
    if (address(factory_) == address(0)) revert Errors.ZeroAddress();
    if (address(collateralAsset_) == address(debtAsset_)) revert Errors.InvalidPair();
    if (buffer_ == 0 || buffer_ >= MathUtils.RAY) revert Errors.InvalidParams();
    if (floor_ >= buffer_) revert Errors.InvalidParams();
    if (window_ == 0) revert Errors.InvalidParams();
    if (minPositionSize_ == 0) revert Errors.InvalidParams();
    if (minDepositSize_ == 0) revert Errors.InvalidParams();

    oracle = oracle_;
    collateralAsset = collateralAsset_;
    debtAsset = debtAsset_;
    factory = factory_;
    buffer = buffer_;
    floor = floor_;
    window = window_;
    minPositionSize = minPositionSize_;
    minDepositSize = minDepositSize_;
  }

  /*//////////////////////////////////////////////////////////////
                              VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @notice Compatibility helper for callers that need the debt asset address.
  function asset() public view returns (address) {
    return address(debtAsset);
  }

  /// @dev Donation-immune: uses internal accounting, ignores raw balanceOf.
  function totalAssets() public view returns (uint256) {
    return totalDebtAssetAtRest + totalDebtAssetDeployed;
  }

  function cohortInfo(uint256 cohortId)
    external
    view
    returns (
      uint256 idleDebt,
      uint256 deployedDebt,
      uint256 unitSupply,
      uint256 activePositions,
      uint256 accYieldPerUnit,
      bool isSealed
    )
  {
    Cohort storage c = cohorts[cohortId];
    return (c.idleDebt, c.deployedDebt, c.unitSupply, c.activePositions, c.accYieldPerUnit, c.isSealed);
  }

  function balanceOf(address user, uint256 cohortId) public view returns (uint256) {
    return userCohorts[user][cohortId].units;
  }

  function maxRedeem(address user, uint256 cohortId) public view returns (uint256) {
    Cohort storage c = cohorts[cohortId];
    if (c.activePositions != 0) return 0;
    return userCohorts[user][cohortId].units;
  }

  function maxWithdraw(address user, uint256 cohortId) public view returns (uint256) {
    Cohort storage c = cohorts[cohortId];
    uint256 units = maxRedeem(user, cohortId);
    if (units == 0 || c.unitSupply == 0) return 0;
    if (units == c.unitSupply) return c.idleDebt;
    return Math.mulDiv(c.idleDebt, units, c.unitSupply);
  }

  function claimableYield(address user, uint256 cohortId) public view returns (uint256) {
    UserCohort storage u = userCohorts[user][cohortId];
    Cohort storage c = cohorts[cohortId];
    uint256 totalEarned = Math.mulDiv(u.units, c.accYieldPerUnit, ACC_PRECISION);
    uint256 accrued = totalEarned > u.yieldDebt ? totalEarned - u.yieldDebt : 0;
    return u.pendingYield + accrued;
  }

  function positionFundingSliceCount(uint256 positionId) external view returns (uint256) {
    return positionFundingSlices[positionId].length;
  }

  /*//////////////////////////////////////////////////////////////
                              DEPOSITS
  //////////////////////////////////////////////////////////////*/

  function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 cohortId, uint256 units) {
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (assets < minDepositSize) revert Errors.BelowMinSize();

    cohortId = currentCohortId;
    Cohort storage c = cohorts[cohortId];
    if (c.isSealed || c.activePositions != 0) revert Errors.InvalidParams();

    units = assets;
    _harvest(receiver, cohortId);
    c.idleDebt += assets;
    c.unitSupply += units;
    UserCohort storage u = userCohorts[receiver][cohortId];
    u.units += units;
    u.yieldDebt = Math.mulDiv(u.units, c.accYieldPerUnit, ACC_PRECISION);
    totalDebtAssetAtRest += assets;

    debtAsset.safeTransferFrom(msg.sender, address(this), assets);
    emit Deposited(msg.sender, receiver, cohortId, assets, units);
  }

  function redeem(uint256 cohortId, uint256 units, address receiver) external nonReentrant returns (uint256 assets) {
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (units == 0) revert Errors.ZeroAmount();

    Cohort storage c = cohorts[cohortId];
    UserCohort storage u = userCohorts[msg.sender][cohortId];
    if (c.activePositions != 0) revert Errors.InsufficientFreeLiquidity();
    if (units > u.units) revert Errors.InsufficientFreeLiquidity();
    if (c.unitSupply == 0) revert Errors.ZeroAmount();

    _harvest(msg.sender, cohortId);

    assets = units == c.unitSupply ? c.idleDebt : Math.mulDiv(c.idleDebt, units, c.unitSupply);

    u.units -= units;
    c.unitSupply -= units;
    c.idleDebt -= assets;
    totalDebtAssetAtRest -= assets;
    u.yieldDebt = Math.mulDiv(u.units, c.accYieldPerUnit, ACC_PRECISION);

    debtAsset.safeTransfer(receiver, assets);
    emit Redeemed(msg.sender, receiver, cohortId, assets, units);
  }

  /*//////////////////////////////////////////////////////////////
                              OPEN
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Open a position: deposit collateral C, receive debt D at oracle rate.
   * @param D Debt amount in debt-asset atomic units.
   * @return id Position id.
   */
  function open(uint256 D) external nonReentrant returns (uint256 id) {
    (id,,) = _recordOpenPosition(D);
    bool usedCurrent = _fundPositionProRata(id, D);
    _finalizeOpen(id, D, usedCurrent);
  }

  function _recordOpenPosition(uint256 D) internal returns (uint256 id, uint256 C, uint256 rateRay) {
    if (factory.paused()) revert Errors.EnforcedPause();
    if (oracle.paused()) revert Errors.OracleStale();
    if (D < minPositionSize) revert Errors.BelowMinSize();
    if (D > totalDebtAssetAtRest) revert Errors.InsufficientLPCapacity();

    rateRay = oracle.buyRate();
    // C = D * rate * (RAY + buffer) / RAY^2  (two mulDivs, no intermediate overflow)
    uint256 priceTimesD = Math.mulDiv(D, rateRay, MathUtils.RAY);
    C = Math.mulDiv(priceTimesD, MathUtils.RAY + buffer, MathUtils.RAY);
    if (C == 0 || C > type(uint128).max || D > type(uint128).max) {
      revert Errors.InvalidParams();
    }

    id = nextId++;
    positions[id] = PositionTypes.Position({
      borrower: msg.sender,
      openTime: uint96(block.timestamp),
      C: uint128(C),
      D: uint128(D),
      rateAtOpen: rateRay
    });
  }

  function _finalizeOpen(uint256 id, uint256 D, bool usedCurrent) internal {
    PositionTypes.Position memory p = positions[id];

    totalDebtAssetAtRest -= D;
    totalDebtAssetDeployed += D;
    totalCollateralLocked += uint256(p.C);

    collateralAsset.safeTransferFrom(msg.sender, address(this), uint256(p.C));
    debtAsset.safeTransfer(msg.sender, D);

    if (usedCurrent) {
      emit CohortSealed(currentCohortId);
      currentCohortId++;
    }

    emit PositionOpened(id, msg.sender, p.C, uint128(D), p.rateAtOpen, p.openTime);
  }

  function _fundPositionProRata(uint256 id, uint256 amount) internal returns (bool usedCurrent) {
    uint256 cohortCount = currentCohortId + 1;
    uint256[] memory cohortIds = new uint256[](cohortCount);
    uint256[] memory idleDebts = new uint256[](cohortCount);
    uint256[] memory takes = new uint256[](cohortCount);
    uint256 fundableCount;
    uint256 totalAvailable;

    for (uint256 cohortId = 0; cohortId < cohortCount; cohortId++) {
      uint256 idleDebt = cohorts[cohortId].idleDebt;
      if (idleDebt == 0) continue;
      cohortIds[fundableCount] = cohortId;
      idleDebts[fundableCount] = idleDebt;
      fundableCount++;
      totalAvailable += idleDebt;
    }

    if (amount > totalAvailable) revert Errors.InsufficientLPCapacity();

    uint256 allocated;
    for (uint256 i = 0; i < fundableCount; i++) {
      uint256 take = Math.mulDiv(amount, idleDebts[i], totalAvailable);
      takes[i] = take;
      allocated += take;
    }

    uint256 remainder = amount - allocated;
    for (uint256 i = 0; i < fundableCount && remainder > 0; i++) {
      uint256 room = idleDebts[i] - takes[i];
      uint256 extra = room < remainder ? room : remainder;
      takes[i] += extra;
      remainder -= extra;
    }

    if (remainder != 0) revert Errors.ConservationBroken();

    for (uint256 i = 0; i < fundableCount; i++) {
      uint256 take = takes[i];
      if (take == 0) continue;
      if (_takeFundingSliceExact(id, cohortIds[i], take)) {
        usedCurrent = true;
      }
    }
  }

  function _takeFundingSliceExact(uint256 id, uint256 cohortId, uint256 amount) internal returns (bool usedCurrent) {
    Cohort storage c = cohorts[cohortId];
    if (amount == 0 || amount > c.idleDebt) revert Errors.ConservationBroken();

    c.idleDebt -= amount;
    c.deployedDebt += amount;
    c.activePositions += 1;
    if (cohortId == currentCohortId) {
      c.isSealed = true;
      usedCurrent = true;
    }

    positionFundingSlices[id].push(PositionTypes.FundingSlice({cohortId: cohortId, debtAmount: amount}));
  }

  /*//////////////////////////////////////////////////////////////
                              FILL
  //////////////////////////////////////////////////////////////*/

  function fill(uint256 maxDebtIn, uint256 maxPositions)
    external
    nonReentrant
    returns (uint256 positionsFilled, uint256 debtInUsed, uint256 collateralOut)
  {
    if (maxDebtIn == 0 || maxPositions == 0) revert Errors.ZeroAmount();
    if (maxPositions > MAX_BATCH_SIZE) revert Errors.BatchTooLarge();
    if (maxDebtIn < minPositionSize && !_isFinalDustFill(maxDebtIn)) revert Errors.BelowMinSize();

    uint256 remainingDebt = maxDebtIn;
    while (positionsFilled < maxPositions) {
      PositionTypes.Position memory p = positions[nextFillId];
      if (p.borrower == address(0)) break;

      FeeLogic.FillQuote memory q =
        FeeLogic.quoteFill(uint256(p.C), uint256(p.D), block.timestamp - uint256(p.openTime), floor, buffer, window);

      if (q.fillerDebtIn > remainingDebt) {
        FeeLogic.FillQuote memory partialQuote = _scaleFillQuote(q, p, remainingDebt);
        if (partialQuote.fillerDebtIn == 0 || partialQuote.cpPrincipalDebt + partialQuote.lpPrincipalLoss == 0) break;
        _fillPositionPartially(nextFillId, p, partialQuote);
        positionsFilled++;
        debtInUsed += partialQuote.fillerDebtIn;
        collateralOut += partialQuote.fillerCollateralOut;
        remainingDebt = 0;
        break;
      }

      _fillPosition(nextFillId, p, q);
      nextFillId++;
      positionsFilled++;
      debtInUsed += q.fillerDebtIn;
      collateralOut += q.fillerCollateralOut;
      remainingDebt -= q.fillerDebtIn;
    }

    if (positionsFilled == 0) {
      if (positions[nextFillId].borrower == address(0)) revert Errors.NothingToFill();
      revert Errors.FillBudgetTooLow();
    }
  }

  function _isFinalDustFill(uint256 maxDebtIn) internal view returns (bool) {
    PositionTypes.Position memory p = positions[nextFillId];
    if (p.borrower == address(0)) return false;
    FeeLogic.FillQuote memory q =
      FeeLogic.quoteFill(uint256(p.C), uint256(p.D), block.timestamp - uint256(p.openTime), floor, buffer, window);
    return q.fillerDebtIn <= maxDebtIn && positions[nextFillId + 1].borrower == address(0);
  }

  function _scaleFillQuote(FeeLogic.FillQuote memory full, PositionTypes.Position memory p, uint256 debtIn)
    internal
    pure
    returns (FeeLogic.FillQuote memory q)
  {
    if (debtIn == 0 || debtIn >= full.fillerDebtIn) return full;

    q.feeRay = full.feeRay;
    q.fillerDebtIn = debtIn;
    q.cpPrincipalDebt = Math.mulDiv(full.cpPrincipalDebt, debtIn, full.fillerDebtIn);
    q.cpYieldDebtNet = Math.mulDiv(full.cpYieldDebtNet, debtIn, full.fillerDebtIn);
    q.traderRefundDebt = Math.mulDiv(full.traderRefundDebt, debtIn, full.fillerDebtIn);
    q.cpProtocolFeeDebt = Math.mulDiv(full.cpProtocolFeeDebt, debtIn, full.fillerDebtIn);

    uint256 debtPrincipalFilled = Math.mulDiv(uint256(p.D), debtIn, full.fillerDebtIn);
    uint256 collateralFilled = Math.mulDiv(uint256(p.C), debtIn, full.fillerDebtIn);
    if (debtPrincipalFilled == 0 || collateralFilled == 0) {
      q.fillerDebtIn = 0;
      return q;
    }

    uint256 allocated = q.cpPrincipalDebt + q.cpYieldDebtNet + q.traderRefundDebt + q.cpProtocolFeeDebt;
    if (allocated < debtIn) {
      uint256 principalRoom = debtPrincipalFilled - q.cpPrincipalDebt;
      uint256 remainder = debtIn - allocated;
      if (remainder <= principalRoom) {
        q.cpPrincipalDebt += remainder;
      } else {
        q.cpPrincipalDebt = debtPrincipalFilled;
        q.traderRefundDebt += remainder - principalRoom;
      }
    }

    q.lpPrincipalLoss = debtPrincipalFilled - q.cpPrincipalDebt;
    q.fillerProtocolFeeCollateral = Math.mulDiv(full.fillerProtocolFeeCollateral, debtIn, full.fillerDebtIn);
    q.fillerCollateralOut = collateralFilled - q.fillerProtocolFeeCollateral;
  }

  function _fillPosition(uint256 id, PositionTypes.Position memory p, FeeLogic.FillQuote memory q) internal {
    if (p.borrower == address(0)) revert Errors.PositionNotFound();
    uint256 D = uint256(p.D);
    uint256 C = uint256(p.C);
    if (q.fillerDebtIn != q.cpPrincipalDebt + q.cpYieldDebtNet + q.traderRefundDebt + q.cpProtocolFeeDebt) {
      revert Errors.ConservationBroken();
    }
    if (q.fillerCollateralOut + q.fillerProtocolFeeCollateral != C) revert Errors.ConservationBroken();

    // Effects.
    delete positions[id];
    _settlePositionFunding(id, D, D, q.cpPrincipalDebt, q.cpYieldDebtNet);
    delete positionFundingSlices[id];
    totalDebtAssetDeployed -= D;
    totalDebtAssetAtRest += q.cpPrincipalDebt;
    totalCollateralLocked -= C;

    if (q.cpProtocolFeeDebt > 0) {
      accProtocolFee[address(debtAsset)] += q.cpProtocolFeeDebt;
      emit ProtocolFeeAccrued(address(debtAsset), q.cpProtocolFeeDebt);
    }
    if (q.fillerProtocolFeeCollateral > 0) {
      accProtocolFee[address(collateralAsset)] += q.fillerProtocolFeeCollateral;
      emit ProtocolFeeAccrued(address(collateralAsset), q.fillerProtocolFeeCollateral);
    }

    if (q.traderRefundDebt > 0) {
      pendingRefund[p.borrower] += q.traderRefundDebt;
      totalPendingRefund += q.traderRefundDebt;
    }

    // Interactions (CEI).
    debtAsset.safeTransferFrom(msg.sender, address(this), q.fillerDebtIn);
    if (q.fillerCollateralOut > 0) {
      collateralAsset.safeTransfer(msg.sender, q.fillerCollateralOut);
    }
    if (q.traderRefundDebt > 0) {
      _payRefund(id, p.borrower, q.traderRefundDebt);
    }

    emit PositionClosed(
      id,
      msg.sender,
      q.feeRay,
      q.fillerDebtIn,
      q.fillerCollateralOut,
      q.cpYieldDebtNet,
      q.lpPrincipalLoss,
      q.fillerProtocolFeeCollateral,
      q.cpProtocolFeeDebt
    );
  }

  function _fillPositionPartially(uint256 id, PositionTypes.Position memory p, FeeLogic.FillQuote memory q) internal {
    if (p.borrower == address(0)) revert Errors.PositionNotFound();
    uint256 debtPrincipalFilled = q.cpPrincipalDebt + q.lpPrincipalLoss;
    uint256 collateralFilled = q.fillerCollateralOut + q.fillerProtocolFeeCollateral;
    if (debtPrincipalFilled == 0 || debtPrincipalFilled >= uint256(p.D)) revert Errors.FillBudgetTooLow();
    if (collateralFilled == 0 || collateralFilled >= uint256(p.C)) revert Errors.FillBudgetTooLow();
    if (q.fillerDebtIn != q.cpPrincipalDebt + q.cpYieldDebtNet + q.traderRefundDebt + q.cpProtocolFeeDebt) {
      revert Errors.ConservationBroken();
    }

    PositionTypes.Position storage stored = positions[id];
    stored.D = uint128(uint256(stored.D) - debtPrincipalFilled);
    stored.C = uint128(uint256(stored.C) - collateralFilled);
    _settlePositionFunding(id, uint256(p.D), debtPrincipalFilled, q.cpPrincipalDebt, q.cpYieldDebtNet);
    totalDebtAssetDeployed -= debtPrincipalFilled;
    totalDebtAssetAtRest += q.cpPrincipalDebt;
    totalCollateralLocked -= collateralFilled;

    if (q.cpProtocolFeeDebt > 0) {
      accProtocolFee[address(debtAsset)] += q.cpProtocolFeeDebt;
      emit ProtocolFeeAccrued(address(debtAsset), q.cpProtocolFeeDebt);
    }
    if (q.fillerProtocolFeeCollateral > 0) {
      accProtocolFee[address(collateralAsset)] += q.fillerProtocolFeeCollateral;
      emit ProtocolFeeAccrued(address(collateralAsset), q.fillerProtocolFeeCollateral);
    }

    if (q.traderRefundDebt > 0) {
      pendingRefund[p.borrower] += q.traderRefundDebt;
      totalPendingRefund += q.traderRefundDebt;
    }

    debtAsset.safeTransferFrom(msg.sender, address(this), q.fillerDebtIn);
    if (q.fillerCollateralOut > 0) {
      collateralAsset.safeTransfer(msg.sender, q.fillerCollateralOut);
    }
    if (q.traderRefundDebt > 0) {
      _payRefund(id, p.borrower, q.traderRefundDebt);
    }

    emit PositionPartiallyFilled(
      id,
      msg.sender,
      q.feeRay,
      q.fillerDebtIn,
      q.fillerCollateralOut,
      q.cpYieldDebtNet,
      q.lpPrincipalLoss,
      q.fillerProtocolFeeCollateral,
      q.cpProtocolFeeDebt,
      stored.C,
      stored.D
    );
  }

  /// @dev Distributes a fill's debt principal, cohort principal, and LP yield across the
  ///      position's funding slices. Allocates each slice proportionally against the
  ///      *remaining* slice capacity rather than the position's original `D`, so the
  ///      per-slice debt-principal allocation is provably bounded by `slice.debtAmount`
  ///      and floor-rounding residuals can never overflow the last slice (audit
  ///      report-3 M-02).
  function _settlePositionFunding(
    uint256 id,
    uint256 D,
    uint256 debtPrincipalFilled,
    uint256 principalDebtIn,
    uint256 netLpYield
  ) internal {
    PositionTypes.FundingSlice[] storage slices = positionFundingSlices[id];
    uint256 len = slices.length;
    uint256 remainingDebtPrincipal = debtPrincipalFilled;
    uint256 remainingPrincipal = principalDebtIn;
    uint256 remainingYield = netLpYield;
    uint256 remainingSliceDebt = D;

    for (uint256 i = 0; i < len; i++) {
      PositionTypes.FundingSlice storage slice = slices[i];
      uint256 sliceDebtAmount = slice.debtAmount;
      bool last = i == len - 1;

      uint256 sliceDebtPrincipal;
      uint256 slicePrincipal;
      uint256 sliceYield;
      if (sliceDebtAmount == 0) {
        // Slice already drained by a prior partial fill: contribute nothing.
        // remainingSliceDebt / remainingDebtPrincipal are unaffected because
        // there is no capacity to allocate against. Skipping the slice is also
        // necessary to avoid a div-by-zero when every slice past this point is
        // drained.
        sliceDebtPrincipal = 0;
        slicePrincipal = 0;
        sliceYield = 0;
      } else if (last) {
        // Invariant from sequential proportional allocation: at the last
        // non-drained step `remainingSliceDebt == sliceDebtAmount`, so
        // `remainingDebtPrincipal <= sliceDebtAmount` and the slice can absorb
        // the residual without underflow.
        sliceDebtPrincipal = remainingDebtPrincipal;
        slicePrincipal = remainingPrincipal;
        sliceYield = remainingYield;
      } else {
        // sliceDebtAmount > 0 implies remainingSliceDebt >= sliceDebtAmount > 0,
        // so the division is safe.
        sliceDebtPrincipal = Math.mulDiv(remainingDebtPrincipal, sliceDebtAmount, remainingSliceDebt);
        slicePrincipal = Math.mulDiv(remainingPrincipal, sliceDebtAmount, remainingSliceDebt);
        sliceYield = Math.mulDiv(remainingYield, sliceDebtAmount, remainingSliceDebt);
      }
      remainingDebtPrincipal -= sliceDebtPrincipal;
      remainingPrincipal -= slicePrincipal;
      remainingYield -= sliceYield;
      remainingSliceDebt -= sliceDebtAmount;

      Cohort storage c = cohorts[slice.cohortId];
      c.deployedDebt -= sliceDebtPrincipal;
      c.idleDebt += slicePrincipal;
      if (sliceDebtPrincipal == sliceDebtAmount) {
        c.activePositions -= 1;
      }
      slice.debtAmount = sliceDebtAmount - sliceDebtPrincipal;
      if (sliceYield > 0) {
        if (c.unitSupply == 0) revert Errors.ConservationBroken();
        c.accYieldPerUnit += Math.mulDiv(sliceYield, ACC_PRECISION, c.unitSupply);
        totalLpYieldLiability += sliceYield;
      }
    }
  }

  /// @dev pendingRefund was credited above. Try direct debt transfer; on success consume
  ///      the pending bucket. On revert, leave pending and emit RefundQueued.
  function _payRefund(uint256 id, address borrower, uint256 amount) internal {
    try this._safeTransferDebt(borrower, amount) {
      pendingRefund[borrower] -= amount;
      totalPendingRefund -= amount;
      emit RefundPaid(id, borrower, amount);
    } catch {
      emit RefundQueued(id, borrower, amount);
    }
  }

  /// @dev External wrapper so try/catch can isolate refund-transfer failures from
  ///      the rest of close(). msg.sender == address(this) only path.
  function _safeTransferDebt(address to, uint256 amount) external {
    if (msg.sender != address(this)) revert Errors.OnlySelf();
    debtAsset.safeTransfer(to, amount);
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIMS
  //////////////////////////////////////////////////////////////*/

  function claimYield(uint256[] calldata cohortIds) external nonReentrant returns (uint256 amount) {
    uint256 len = cohortIds.length;
    for (uint256 i = 0; i < len; i++) {
      uint256 cohortId = cohortIds[i];
      _harvest(msg.sender, cohortId);
      UserCohort storage u = userCohorts[msg.sender][cohortId];
      uint256 pending = u.pendingYield;
      if (pending == 0) continue;
      u.pendingYield = 0;
      totalPendingYield -= pending;
      totalLpYieldLiability -= pending;
      amount += pending;
    }
    if (amount == 0) revert Errors.ZeroAmount();
    debtAsset.safeTransfer(msg.sender, amount);
    emit YieldClaimed(msg.sender, amount);
  }

  function claimPendingRefund() external nonReentrant returns (uint256 amount) {
    amount = pendingRefund[msg.sender];
    if (amount == 0) revert Errors.ZeroAmount();
    pendingRefund[msg.sender] = 0;
    totalPendingRefund -= amount;
    debtAsset.safeTransfer(msg.sender, amount);
    emit RefundClaimed(msg.sender, amount);
  }

  /// @dev Move (totalEarned - debt) from a cohort accumulator to user's pending bucket.
  function _harvest(address user, uint256 cohortId) internal {
    UserCohort storage u = userCohorts[user][cohortId];
    Cohort storage c = cohorts[cohortId];
    uint256 totalEarned = Math.mulDiv(u.units, c.accYieldPerUnit, ACC_PRECISION);
    if (totalEarned > u.yieldDebt) {
      uint256 delta = totalEarned - u.yieldDebt;
      u.pendingYield += delta;
      totalPendingYield += delta;
    }
    u.yieldDebt = totalEarned;
  }

  /*//////////////////////////////////////////////////////////////
                              ADMIN
  //////////////////////////////////////////////////////////////*/

  /// @notice Sweep accumulated protocol fees of an asset to a recipient.
  function claimProtocolFees(address asset_, address to) external nonReentrant onlyOwner returns (uint256 amount) {
    if (to == address(0)) revert Errors.ZeroAddress();
    amount = accProtocolFee[asset_];
    if (amount == 0) revert Errors.ZeroAmount();
    accProtocolFee[asset_] = 0;
    IERC20(asset_).safeTransfer(to, amount);
    emit ProtocolFeesSwept(asset_, to, amount);
  }

  /**
   * @notice Sweep tokens that exceed the pool's internal accounting for that asset.
   *         Bounded to provably-unaccounted funds.
   *
   *         Debt asset accounted = totalDebtAssetAtRest + totalPendingRefund +
   *                                totalLpYieldLiability + accProtocolFee[debt].
   *         (totalDebtAssetDeployed is held by borrowers, NOT the pool.)
   *
   *         Collateral accounted = totalCollateralLocked + accProtocolFee[collateral].
   *
   *         Other assets accounted = 0; full balance is sweepable.
   */
  function sweepExcess(address asset_, address to) external nonReentrant onlyOwner returns (uint256 excess) {
    if (to == address(0)) revert Errors.ZeroAddress();
    uint256 bal = IERC20(asset_).balanceOf(address(this));
    uint256 accounted;
    if (asset_ == address(debtAsset)) {
      accounted = totalDebtAssetAtRest + totalPendingRefund + totalLpYieldLiability + accProtocolFee[asset_];
    } else if (asset_ == address(collateralAsset)) {
      accounted = totalCollateralLocked + accProtocolFee[asset_];
    } else {
      accounted = 0;
    }
    if (bal <= accounted) revert Errors.ZeroAmount();
    excess = bal - accounted;
    IERC20(asset_).safeTransfer(to, excess);
    emit ExcessSwept(asset_, to, excess);
  }
}
