// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {HPT} from "./HPT.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/// @notice USDC-denominated trading vault with HPT shares, demand-driven
/// settlement, share-locked withdrawals, and per-user cost-basis performance
/// fees. See REFACTOR_PLAN.md for the design and the resolved decisions
/// driving the math here.
///
/// Settlement flow:
///   - requestDeposit escrows USDC (no oracle call, no share mint).
///   - requestWithdraw escrows HPT and snapshots cost basis (no oracle call).
///   - settle(tokens, prices) is called by the bot when there is eligible
///     work. It pushes fresh oracle prices, prices open withdrawals (snapping
///     assetsOut/fee), then mints shares for pending deposits.
///   - claimWithdraw pays the snapshotted assetsOut. No oracle read at claim.
contract Vault is AccessControl, Pausable, ReentrancyGuard, IVault {
    using SafeERC20 for IERC20;
    using Address for address;

    // ── Roles ────────────────────────────────────────────────────────────
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant BOT_ROLE = keccak256("BOT_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // ── Constants ────────────────────────────────────────────────────────
    uint256 public constant MAX_FEE_BPS = 2_000; // 20 %
    uint256 public constant BPS = 10_000;
    uint256 public constant SHARE_SCALE = 1e18;

    // ── Immutables / wiring ──────────────────────────────────────────────
    IERC20 public immutable assetToken; // USDC
    uint8 public immutable assetDecimals;
    HPT public immutable shareToken;

    IOracle public oracleContract;

    // ── Rebalance target whitelist ───────────────────────────────────────
    mapping(address => bool) public targetAllowed;

    // ── Fee config ───────────────────────────────────────────────────────
    uint256 public performanceFee; // bps, ≤ MAX_FEE_BPS
    address public feeRecipient;
    // Flat USDC fee deducted from every settled deposit and withdrawal to
    // reimburse the bot for settle() gas. 0 = disabled. Set by manager
    // to match current gas_price * settle_gas_estimate * eth_price_usdc.
    uint256 public settlementFeeAssets;

    // ── Settlement config ────────────────────────────────────────────────
    uint256 public minDepositAssets;
    uint256 public maxSettlementBatchSize;

    // ── Tracked tokens (NAV universe) ────────────────────────────────────
    address[] private _tokenSet;
    mapping(address => bool) public isTracked;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => uint256) private _tokenIndex; // 1-based, 0 = absent

    // ── Per-user live cost basis value (USDC base units) ─────────────────
    mapping(address => uint256) public costBasisValue;

    // ── Withdraw queue ───────────────────────────────────────────────────
    WithdrawRequest[] private _queue;
    mapping(address => uint256[]) private _userRequests;
    // pendingWithdrawShares == shareToken.balanceOf(vault). Decrements on
    // settle/cancel. Settled withdrawals are economically finalized: shares
    // are burned and a fixed USDC liability is tracked until claim.
    uint256 public pendingWithdrawShares;
    // pendingSettlementWithdrawShares == Σ shares of Open requests.
    // Decrements on settle (Open→Settled) and cancel (Open→Cancelled).
    uint256 public pendingSettlementWithdrawShares;
    uint256 public settledWithdrawalLiabilityTotal;
    uint256 private _nextWithdrawToSettle;

    // ── Deposit queue ────────────────────────────────────────────────────
    DepositRequest[] private _depositQueue;
    mapping(address => uint256[]) private _userDeposits;
    // pendingDepositTotal == Σ assets of Pending requests. Subtracted from
    // totalAssets() so escrowed deposit USDC doesn't lift NAV before mint.
    uint256 public pendingDepositTotal;
    uint256 private _nextDepositToSettle;

    // ──────────────────────────────────────────────────────────────────────

    constructor(
        IERC20 _asset,
        IOracle _oracle,
        address admin,
        address manager,
        address bot,
        address guardian,
        address _feeRecipient,
        uint256 _performanceFee,
        uint256 _minDepositAssets,
        uint256 _maxSettlementBatchSize
    ) {
        if (_performanceFee > MAX_FEE_BPS) revert InvalidFee();
        if (_maxSettlementBatchSize == 0) revert InvalidBatchSize();

        assetToken = _asset;
        assetDecimals = IERC20Metadata(address(_asset)).decimals();
        oracleContract = _oracle;
        performanceFee = _performanceFee;
        feeRecipient = _feeRecipient;
        minDepositAssets = _minDepositAssets;
        maxSettlementBatchSize = _maxSettlementBatchSize;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(BOT_ROLE, bot);
        _grantRole(GUARDIAN_ROLE, guardian);

        shareToken = new HPT(address(this));

        emit OracleSet(address(_oracle));
        emit PerformanceFeeSet(_performanceFee);
        emit MinDepositAssetsSet(_minDepositAssets);
        emit MaxSettlementBatchSizeSet(_maxSettlementBatchSize);
    }

    // ── Interface impls ──────────────────────────────────────────────────
    function asset() external view returns (address) {
        return address(assetToken);
    }

    function shares() external view returns (address) {
        return address(shareToken);
    }

    function oracle() external view returns (address) {
        return address(oracleContract);
    }

    // ── NAV ──────────────────────────────────────────────────────────────

    /// @notice USDC-denominated NAV. Excludes pendingDepositTotal because that
    /// USDC is still escrowed and not part of the settled assets — see
    /// REFACTOR_PLAN §1.2.
    function totalAssets() public view returns (uint256) {
        uint256 usdcBal = assetToken.balanceOf(address(this));
        uint256 reserved = pendingDepositTotal + settledWithdrawalLiabilityTotal;
        uint256 sum = usdcBal > reserved ? usdcBal - reserved : 0;
        uint256 len = _tokenSet.length;
        for (uint256 i = 0; i < len; i++) {
            address t = _tokenSet[i];
            if (t == address(assetToken)) continue; // priced 1:1, already counted
            uint256 bal = IERC20(t).balanceOf(address(this));
            if (bal == 0) continue;
            uint256 price = oracleContract.getPrice(t);
            sum += (bal * price) / (10 ** uint256(tokenDecimals[t]));
        }
        return sum;
    }

    function pricePerShare() public view returns (uint256) {
        uint256 sup = shareToken.totalSupply();
        if (sup == 0) return 10 ** uint256(assetDecimals); // seed pps = 1.0
        return (totalAssets() * SHARE_SCALE) / sup;
    }

    function costBasisPerShare(address user) public view returns (uint256) {
        uint256 bal = shareToken.balanceOf(user);
        if (bal == 0) return 0;
        return (costBasisValue[user] * SHARE_SCALE) / bal;
    }

    // ── Deposit (queue) ──────────────────────────────────────────────────

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return (assets * SHARE_SCALE) / pricePerShare();
    }

    function requestDeposit(uint256 assets)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 depositId)
    {
        depositId = _requestDepositFor(assets, msg.sender, msg.sender);
    }

    /// @notice Deposit on behalf of `recipient`. USDC is pulled from msg.sender;
    /// shares are minted to `recipient` after settle. Used by VaultMigrator-style
    /// flows to atomically redirect a claim into a new deposit.
    function requestDepositFor(uint256 assets, address recipient)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 depositId)
    {
        depositId = _requestDepositFor(assets, msg.sender, recipient);
    }

    function _requestDepositFor(uint256 assets, address payer, address recipient)
        internal
        returns (uint256 depositId)
    {
        if (assets == 0) revert ZeroAmount();
        if (assets < minDepositAssets) revert DepositTooSmall();

        depositId = _depositQueue.length;
        _depositQueue.push(DepositRequest({
            owner: recipient,
            assets: assets,
            status: DepositStatus.Pending
        }));
        _userDeposits[recipient].push(depositId);
        pendingDepositTotal += assets;

        assetToken.safeTransferFrom(payer, address(this), assets);

        emit DepositRequested(depositId, recipient, assets);
    }

    function cancelDepositRequest(uint256 depositId) external nonReentrant {
        DepositRequest storage d = _depositQueue[depositId];
        if (d.owner != msg.sender) revert NotRequestOwner();
        if (d.status != DepositStatus.Pending) revert RequestNotOpen();

        d.status = DepositStatus.Cancelled;
        pendingDepositTotal -= d.assets;
        assetToken.safeTransfer(msg.sender, d.assets);

        emit DepositCancelled(depositId, msg.sender, d.assets);
    }

    /// @notice Admin sweep: cancel up to `maxCount` pending deposits and return
    /// USDC to each depositor. Used during vault migration / emergency shutdown
    /// so users don't need to find and cancel their own deposit IDs.
    function cancelPendingDeposits(uint256 maxCount)
        external
        onlyRole(MANAGER_ROLE)
        nonReentrant
        returns (uint256 cancelled)
    {
        uint256 dLen = _depositQueue.length;
        for (uint256 i = 0; i < dLen && cancelled < maxCount; i++) {
            DepositRequest storage d = _depositQueue[i];
            if (d.status != DepositStatus.Pending) continue;
            d.status = DepositStatus.Cancelled;
            pendingDepositTotal -= d.assets;
            assetToken.safeTransfer(d.owner, d.assets);
            emit DepositCancelled(i, d.owner, d.assets);
            cancelled++;
        }
    }

    // ── Withdraw queue ───────────────────────────────────────────────────

    /// @notice Estimated (assetsBeforeFee, fee) at the current pps. Not
    /// binding — the realized amount is fixed during settle() using the
    /// settle-time oracle prices. UI must surface this with a caution.
    function previewWithdraw(uint256 sharesIn, address owner)
        public
        view
        returns (uint256 estimatedAssets, uint256 estimatedFee)
    {
        uint256 pps = pricePerShare();
        estimatedAssets = (sharesIn * pps) / SHARE_SCALE;
        uint256 bal = shareToken.balanceOf(owner);
        uint256 originalCost = bal == 0 ? 0 : (costBasisValue[owner] * sharesIn) / bal;
        uint256 gain = estimatedAssets > originalCost ? estimatedAssets - originalCost : 0;
        estimatedFee = (gain * performanceFee) / BPS + settlementFeeAssets;
        if (estimatedFee > estimatedAssets) estimatedFee = estimatedAssets;
    }

    function requestWithdraw(uint256 sharesIn)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        if (sharesIn == 0) revert ZeroAmount();

        uint256 ownerBal = shareToken.balanceOf(msg.sender);
        if (sharesIn > ownerBal) revert InsufficientShares();
        uint256 basisValue = (costBasisValue[msg.sender] * sharesIn) / ownerBal;
        costBasisValue[msg.sender] -= basisValue;

        // claimableAt stays maxed out until settle() prices the request.
        uint64 requestedAt = uint64(block.timestamp);
        uint64 claimableAt = type(uint64).max;

        requestId = _queue.length;
        _queue.push(
            WithdrawRequest({
                owner: msg.sender,
                shares: sharesIn,
                costBasisValueSnapshot: basisValue,
                requestedAt: requestedAt,
                claimableAt: claimableAt,
                status: WithdrawStatus.Open,
                assetsOut: 0,
                fee: 0
            })
        );
        _userRequests[msg.sender].push(requestId);
        pendingWithdrawShares += sharesIn;
        pendingSettlementWithdrawShares += sharesIn;

        IERC20(address(shareToken)).safeTransferFrom(msg.sender, address(this), sharesIn);

        emit WithdrawRequested(requestId, msg.sender, sharesIn, claimableAt);
    }

    /// @notice Claim a settled withdrawal. Pays the snapshotted assetsOut/fee
    /// from settle() — no oracle read at claim time.
    function claimWithdraw(uint256 requestId) external nonReentrant {
        _claimWithdrawTo(requestId, msg.sender);
    }

    /// @notice Same as claimWithdraw but sends net USDC to `recipient` instead
    /// of the request owner. Useful for routing funds directly into another
    /// contract (e.g. claimAndDeposit). Only callable by the request owner.
    function claimWithdrawTo(uint256 requestId, address recipient) external nonReentrant {
        _claimWithdrawTo(requestId, recipient);
    }

    /// @notice Atomically claim a settled withdrawal and open a deposit on
    /// `newVault` in a single transaction. The caller (request owner) gets a
    /// pending deposit in the new vault; shares are minted after new vault's
    /// next settle().
    function claimAndDeposit(uint256 requestId, IVault newVault)
        external
        nonReentrant
        returns (uint256 depositId)
    {
        WithdrawRequest storage r = _queue[requestId];
        if (r.owner != msg.sender) revert NotRequestOwner();
        if (r.status != WithdrawStatus.Settled) revert RequestNotOpen();
        if (block.timestamp < r.claimableAt) revert WithdrawNotReady();

        uint256 sharesAmt = r.shares;
        uint256 net = r.assetsOut;
        uint256 fee = r.fee;

        uint256 raw = assetToken.balanceOf(address(this));
        uint256 available = raw > pendingDepositTotal ? raw - pendingDepositTotal : 0;
        if (available < net + fee) revert InsufficientLiquidity();

        r.status = WithdrawStatus.Claimed;
        settledWithdrawalLiabilityTotal -= net + fee;

        if (fee > 0) assetToken.safeTransfer(feeRecipient, fee);

        // Approve new vault exactly once for the claimed amount, then deposit.
        assetToken.approve(address(newVault), net);
        depositId = newVault.requestDepositFor(net, msg.sender);
        assetToken.approve(address(newVault), 0);

        emit WithdrawClaimed(requestId, r.owner, sharesAmt, net, fee);
    }

    function _claimWithdrawTo(uint256 requestId, address recipient) internal {
        WithdrawRequest storage r = _queue[requestId];
        if (r.owner != msg.sender) revert NotRequestOwner();
        if (r.status != WithdrawStatus.Settled) revert RequestNotOpen();
        if (block.timestamp < r.claimableAt) revert WithdrawNotReady();

        uint256 sharesAmt = r.shares;
        uint256 net = r.assetsOut;
        uint256 fee = r.fee;

        // Exclude pending-deposit USDC: those funds belong to depositors
        // until settle() mints their shares. Using raw balanceOf would let
        // withdrawers drain queued deposits.
        uint256 raw = assetToken.balanceOf(address(this));
        uint256 available = raw > pendingDepositTotal ? raw - pendingDepositTotal : 0;
        if (available < net + fee) revert InsufficientLiquidity();

        r.status = WithdrawStatus.Claimed;
        settledWithdrawalLiabilityTotal -= net + fee;

        if (fee > 0) assetToken.safeTransfer(feeRecipient, fee);
        assetToken.safeTransfer(recipient, net);

        emit WithdrawClaimed(requestId, r.owner, sharesAmt, net, fee);
    }

    function cancelWithdraw(uint256 requestId) external nonReentrant {
        WithdrawRequest storage r = _queue[requestId];
        if (r.owner != msg.sender) revert NotRequestOwner();
        if (r.status != WithdrawStatus.Open) revert RequestNotOpen();

        uint256 sharesAmt = r.shares;

        r.status = WithdrawStatus.Cancelled;
        pendingWithdrawShares -= sharesAmt;
        pendingSettlementWithdrawShares -= sharesAmt;
        costBasisValue[r.owner] += r.costBasisValueSnapshot;

        IERC20(address(shareToken)).safeTransfer(r.owner, sharesAmt);

        emit WithdrawCancelled(requestId, r.owner, sharesAmt);
    }

    // ── Settlement ───────────────────────────────────────────────────────

    /// @notice Push fresh oracle prices, price open withdrawals, then mint
    /// shares for pending deposits. Bounded by maxSettlementBatchSize so a
    /// single call has predictable gas. See REFACTOR_PLAN §1.5.
    function settle(address[] calldata tokens, uint128[] calldata prices)
        external
        nonReentrant
        whenNotPaused
        onlyRole(BOT_ROLE)
    {
        oracleContract.setPrice(tokens, prices);

        // pps is fixed at the top of settle(). Minting against this pps is
        // mathematically a no-op for pps itself (T/S is preserved by the
        // mint), so both queues see the same price.
        uint256 pps = pricePerShare();

        // Settlement fee snapshot: read once, apply uniformly to every item
        // this call processes. Bot sets this to cover gas cost per request.
        uint256 settleFeePer = settlementFeeAssets;
        uint256 totalSettlementFees = 0;

        // Step 1: price open withdrawals.
        uint256 qLen = _queue.length;
        uint256 wScanned = 0;
        uint256 wProcessed = 0;
        for (uint256 i = _nextWithdrawToSettle; i < qLen && wScanned < maxSettlementBatchSize; i++) {
            WithdrawRequest storage r = _queue[i];
            wScanned++;
            if (r.status != WithdrawStatus.Open) {
                _nextWithdrawToSettle = i + 1;
                continue;
            }
            _nextWithdrawToSettle = i + 1;

            uint256 grossAssets = (r.shares * pps) / SHARE_SCALE;
            uint256 gain = grossAssets > r.costBasisValueSnapshot
                ? grossAssets - r.costBasisValueSnapshot
                : 0;
            uint256 perfFee = (gain * performanceFee) / BPS;
            // Cap settlement fee so assetsOut >= 0 (edge case: tiny position).
            uint256 settleFee = settleFeePer > grossAssets - perfFee
                ? grossAssets - perfFee
                : settleFeePer;
            r.assetsOut = grossAssets - perfFee - settleFee;
            r.fee = perfFee;
            r.claimableAt = uint64(block.timestamp);
            r.status = WithdrawStatus.Settled;
            pendingSettlementWithdrawShares -= r.shares;
            pendingWithdrawShares -= r.shares;
            // Only perfFee deferred to claim; settleFee transferred at end of settle().
            settledWithdrawalLiabilityTotal += r.assetsOut + r.fee;
            totalSettlementFees += settleFee;
            shareToken.burn(address(this), r.shares);
            emit WithdrawalSettled(i, r.owner, r.shares, r.assetsOut, r.fee);
            wProcessed++;
        }

        // Step 2: mint shares for pending deposits at the same pps.
        uint256 dLen = _depositQueue.length;
        uint256 dScanned = 0;
        uint256 dSettled = 0;
        uint256 dRefunded = 0;
        for (uint256 i = _nextDepositToSettle; i < dLen && dScanned < maxSettlementBatchSize; i++) {
            DepositRequest storage d = _depositQueue[i];
            _nextDepositToSettle = i + 1;
            dScanned++;
            if (d.status != DepositStatus.Pending) continue; // terminal (Cancelled)

            // If deposit is too small to cover the settlement fee, auto-refund
            // in full (no fee charged) rather than silently wiping the deposit.
            if (d.assets <= settleFeePer) {
                d.status = DepositStatus.Cancelled;
                pendingDepositTotal -= d.assets;
                assetToken.safeTransfer(d.owner, d.assets);
                emit DepositAutoRefunded(i, d.owner, d.assets);
                dRefunded++;
                continue;
            }
            uint256 netAssets = d.assets - settleFeePer;

            uint256 sharesOut = (netAssets * SHARE_SCALE) / pps;
            if (sharesOut == 0) {
                // pps rose enough between requestDeposit (passed minDepositAssets)
                // and now that netAssets buys zero shares. Auto-refund in full.
                d.status = DepositStatus.Cancelled;
                pendingDepositTotal -= d.assets;
                assetToken.safeTransfer(d.owner, d.assets);
                emit DepositAutoRefunded(i, d.owner, d.assets);
                dRefunded++;
                continue;
            }
            d.status = DepositStatus.Settled;
            pendingDepositTotal -= d.assets;
            costBasisValue[d.owner] += netAssets;
            totalSettlementFees += settleFeePer;
            shareToken.mint(d.owner, sharesOut);
            emit DepositSettled(i, d.owner, netAssets, sharesOut);
            dSettled++;
        }

        if (totalSettlementFees > 0) {
            assetToken.safeTransfer(feeRecipient, totalSettlementFees);
        }

        emit Settled(tokens.length, dSettled, dRefunded, wProcessed);
    }

    /// @notice True iff settle() would make at least one unit of progress
    /// right now. Engine must gate _maybe_settle() on this rather than the
    /// raw counters to avoid burning oracle-push gas on a no-op settle when
    /// the queue only contains young withdrawals.
    function hasSettleReadyWork() external view returns (bool) {
        // Deposit queue: any Pending request at or after the cursor counts.
        uint256 dLen = _depositQueue.length;
        for (uint256 i = _nextDepositToSettle; i < dLen; i++) {
            if (_depositQueue[i].status == DepositStatus.Pending) return true;
        }
        // Withdrawal queue: any Open request at or after the cursor counts.
        uint256 qLen = _queue.length;
        for (uint256 i = _nextWithdrawToSettle; i < qLen; i++) {
            if (_queue[i].status == WithdrawStatus.Open) return true;
        }
        return false;
    }

    // ── Share transfer hook (from HPT._update) ──────────────────────────

    function onShareTransfer(address from, address to, uint256 value) external {
        if (msg.sender != address(shareToken)) revert OnlyHPT();
        if (from == address(this) || to == address(this)) return;
        if (value == 0) return;

        uint256 fromBalBefore = shareToken.balanceOf(from) + value;
        uint256 movedBasisValue = (costBasisValue[from] * value) / fromBalBefore;

        costBasisValue[from] -= movedBasisValue;
        costBasisValue[to] += movedBasisValue;
    }

    // ── Rebalance ────────────────────────────────────────────────────────

    function rebalance(address[] calldata targets, bytes[] calldata calldatas)
        external
        nonReentrant
        whenNotPaused
        onlyRole(BOT_ROLE)
    {
        require(targets.length == calldatas.length, "len");
        uint256 navBefore = totalAssets();

        for (uint256 i = 0; i < targets.length; i++) {
            if (!targetAllowed[targets[i]]) revert TargetNotAllowed(targets[i]);
            targets[i].functionCall(calldatas[i]);
        }

        uint256 navAfter = totalAssets();

        emit Rebalanced(targets.length, navBefore, navAfter);
    }

    function setTargetAllowed(address target, bool allowed) external onlyRole(MANAGER_ROLE) {
        targetAllowed[target] = allowed;
        emit TargetAllowed(target, allowed);
    }

    // ── Tracked tokens ──────────────────────────────────────────────────

    function addTrackedToken(address token) external onlyRole(MANAGER_ROLE) {
        if (isTracked[token]) revert AlreadyTracked();
        if (token != address(assetToken)) oracleContract.getPrice(token);

        isTracked[token] = true;
        tokenDecimals[token] = IERC20Metadata(token).decimals();
        _tokenSet.push(token);
        _tokenIndex[token] = _tokenSet.length;
        emit TrackedTokenAdded(token);
    }

    function removeTrackedToken(address token) external onlyRole(MANAGER_ROLE) {
        if (!isTracked[token]) revert NotTracked();
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal != 0) revert TrackedTokenHasBalance(token, bal);

        uint256 idx = _tokenIndex[token] - 1;
        uint256 last = _tokenSet.length - 1;
        if (idx != last) {
            address moved = _tokenSet[last];
            _tokenSet[idx] = moved;
            _tokenIndex[moved] = idx + 1;
        }
        _tokenSet.pop();
        delete _tokenIndex[token];
        delete isTracked[token];
        delete tokenDecimals[token];
        emit TrackedTokenRemoved(token);
    }

    function trackedTokens() external view returns (address[] memory) {
        return _tokenSet;
    }

    // ── Approvals for swap path (manager-only, one-time per token) ──────

    function approveERC20(IERC20 token, address spender, uint256 amount) external onlyRole(MANAGER_ROLE) {
        token.forceApprove(spender, amount);
    }

    function approvePermit2(
        address permit2,
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external onlyRole(MANAGER_ROLE) {
        (bool ok,) = permit2.call(abi.encodeWithSelector(0x87517c45, token, spender, amount, expiration));
        require(ok, "permit2 approve failed");
    }

    // ── Admin setters ───────────────────────────────────────────────────

    function setOracle(IOracle _oracle) external onlyRole(MANAGER_ROLE) {
        oracleContract = _oracle;
        emit OracleSet(address(_oracle));
    }

    function setPerformanceFee(uint256 feeBps) external onlyRole(MANAGER_ROLE) {
        if (feeBps > MAX_FEE_BPS) revert InvalidFee();
        performanceFee = feeBps;
        emit PerformanceFeeSet(feeBps);
    }

    function setFeeRecipient(address recipient) external onlyRole(MANAGER_ROLE) {
        feeRecipient = recipient;
    }

    function setMinDepositAssets(uint256 amount) external onlyRole(MANAGER_ROLE) {
        minDepositAssets = amount;
        emit MinDepositAssetsSet(amount);
    }

    function setSettlementFee(uint256 fee) external onlyRole(MANAGER_ROLE) {
        settlementFeeAssets = fee;
        emit SettlementFeeSet(fee);
    }

    function setMaxSettlementBatchSize(uint256 size) external onlyRole(MANAGER_ROLE) {
        if (size == 0) revert InvalidBatchSize();
        maxSettlementBatchSize = size;
        emit MaxSettlementBatchSizeSet(size);
    }

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    // ── Views ───────────────────────────────────────────────────────────

    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory) {
        return _queue[requestId];
    }

    function userRequestIds(address user) external view returns (uint256[] memory) {
        return _userRequests[user];
    }

    function queueLength() external view returns (uint256) {
        return _queue.length;
    }

    function getDepositRequest(uint256 depositId) external view returns (DepositRequest memory) {
        return _depositQueue[depositId];
    }

    function userDepositIds(address user) external view returns (uint256[] memory) {
        return _userDeposits[user];
    }

    function depositQueueLength() external view returns (uint256) {
        return _depositQueue.length;
    }
}
