// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {ILagoonVaultBase} from "../../interfaces/lagoon/ILagoonVaultBase.sol";
import {Strategy} from "../Strategy.sol";

/// @title LagoonBase
/// @notice Shared logic for Vesper Lagoon strategies. Concrete contracts (`LagoonV05`,
///         `LagoonV06`) bind this base to a specific Lagoon release line by implementing
///         the four hooks declared below.
/// @dev    Lifecycle: keeper calls `requestDeposit` / `requestRedeem`; the curator settles
///         off-chain; keeper sweeps via `processAllClaimable` (or one side). Same-epoch
///         escape via `cancelDeposit` / `cancelRedeem` (V06 only); post-Closed drain via
///         `closeOutPosition`.
/// @dev    Trust model: safe takes asset custody at settle and consumes a guardrails-checked
///         NAV. Exit-with-custody dominates NAV games; aggregate slippage floors on sweep
///         entrypoints catch honest failures.
/// @dev    Sync/async asymmetry: deposits auto-route here (sync is fee-equivalent to async on
///         both versions). Redeems are async-default; sync redeem pays a haircut on v0.6.0 and
///         doesn't exist on v0.5.x
/// @dev    Invariants:
///          1. `_withdrawHere` never queues a new redeem; only sweeps claimables.
///          2. `tvl()` counts idle + pending/claimable on both sides.
///          3. `instantLiquidity()` = idle + sweepable claimable redeem; Closed-state drain
///             is excluded (keeper-only via `closeOutPosition`).
///          4. `processAllClaimable` is strict; `tryProcessAllClaimable` swallows per-side
///             reverts and emits `VaultActionSkipped`.
///          5. `_rebalance` never reverts on vault-side state — `reportEarning` always lands.
///          6. `_rebalance` auto-queues a redeem when `excessDebt > 0` post-`reportEarning`,
///             else auto-deposits idle. Branches are mutually exclusive.
///          7. Closed-state residual drain is keeper-driven via `closeOutPosition` — Lagoon
///             doesn't expose a `state()` getter, so the strategy can't auto-detect.
///          8. Sync/async deposit modes are temporally exclusive on every Lagoon release.
abstract contract LagoonBase is Strategy {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AssetMismatch(address expected, address vaultAsset);
    error InvalidVault();
    error LossExceedsCap(uint256 loss, uint256 cap);
    error MaxLossBpsTooHigh(uint16 actual);
    error NoOutstandingRequest();
    error SlippageExceeded(uint256 expected, uint256 actual);
    error UnsupportedVaultVersion(string actual);
    error ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositCanceled(uint256 indexed requestId, uint256 assetsReturned);
    event DepositClaimed(uint256 indexed requestId, uint256 assetsClaimed, uint256 sharesMinted);
    event DepositRequested(uint256 indexed requestId, uint256 assets);
    event DepositSynced(uint256 assets, uint256 sharesMinted);
    /// @dev Auto-cleanup of an id whose shares were claimed by the safe via
    ///      `claimSharesOnBehalf`, leaving an orphan in our set.
    event ExternalClaimReconciled(uint256 indexed requestId, bool isDeposit);
    /// @dev Governor-driven explicit loss recognition via `reportLoss`. Distinct from the
    ///      keeper-side capped loss that flows through `_rebalance`.
    event LossReported(uint256 loss);
    event MaxLossBpsUpdated(uint16 previous, uint16 current);
    /// @dev Closed-state sync drain via `closeOutPosition`; no epoch / requestId is involved.
    event PositionClosed(uint256 sharesBurned, uint256 assetsReceived);
    event RedeemClaimed(uint256 indexed requestId, uint256 sharesClaimed, uint256 assetsReceived);
    event RedeemRequested(uint256 indexed requestId, uint256 shares);
    /// @dev Emitted when a best-effort vault call is swallowed.
    event VaultActionSkipped(bytes4 indexed selector, bytes reason);

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Asset snapshot excluding idle (read directly from `collateralToken.balanceOf`).
    /// @dev Pending values gross; claimable values net of the per-batch frozen entry/exit fee
    ///      on v0.6.0 (which exposes the rate); on v0.5.x claimable is reported gross because
    ///      v0.5.x has no entry/exit fees at all.
    struct AsyncBalances {
        uint256 pendingDeposit;
        uint256 claimableDeposit;
        uint256 assetsInVault;
        uint256 pendingRedeem;
        uint256 claimableRedeem;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:vesper.storage.Strategy.Lagoon
    /// @dev Lagoon enforces "≤1 outstanding request per controller per side" via
    ///      `OnlyOneRequestAllowed` (ERC7540Lib) + auto-claim of any settled claimable on
    ///      every `_requestDeposit`/`_requestRedeem`. The strategy mirrors the invariant
    ///      with a single id slot per side. `0` is the no-outstanding-id sentinel — real
    ///      Lagoon ids start at 1 (deposit) / 2 (redeem) and increment by 2 per settle.
    /// @dev `_maxLossBps` is appended; layout is a strict superset of the prior
    ///      `{_depositRequestId, _redeemRequestId}` struct. Existing proxies that upgrade
    ///      to this impl read `_maxLossBps == 0`, which is the safe default (bot cannot
    ///      realize any loss until governor opts in via `setMaxLossBps`).
    struct LagoonStorage {
        uint256 _depositRequestId;
        uint256 _redeemRequestId;
        uint16 _maxLossBps;
    }

    bytes32 private constant LAGOON_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.Lagoon")) - 1)) & ~bytes32(uint256(0xff));

    uint256 internal constant MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyKeeperOrSelf() {
        if (msg.sender != address(this) && !EnumerableSet.contains(_getStrategyStorage()._keepers, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param pool_ Vesper pool address.
    /// @param swapper_ Vesper swapper address.
    /// @param vault_ Lagoon ERC-7540 vault address. MUST satisfy `vault.asset() == pool.token()`.
    /// @param name_ Strategy name.
    function initialize(address pool_, address swapper_, address vault_, string memory name_) external initializer {
        if (vault_ == address(0)) revert InvalidVault();

        __Strategy_init(pool_, swapper_, vault_, name_);

        ILagoonVaultBase _vault = ILagoonVaultBase(vault_);
        address _vaultAsset = _vault.asset();
        address _collateral = address(collateralToken());
        if (_vaultAsset != _collateral) revert AssetMismatch(_collateral, _vaultAsset);
        if (_vault.safe() == address(0)) revert InvalidVault();

        _postInitVaultChecks(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL/PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function balances() external view returns (AsyncBalances memory) {
        return _readBalances();
    }

    /// @notice The currently-claimable deposit request and its asset amount, or `(0, 0)` if
    ///         nothing is claimable. Off-chain keepers simulate `processAllClaimable(0, 0)`
    ///         to compute slippage floors.
    function claimableDeposit() external view returns (uint256 _id, uint256 _assets) {
        _id = _getLagoonStorage()._depositRequestId;
        if (_id == 0) return (0, 0);
        _assets = vault().claimableDepositRequest(_id, address(this));
        if (_assets == 0) _id = 0;
    }

    /// @notice Redeem-side mirror of `claimableDeposit`. Returned shares are gross claimable
    ///         (the vault applies exit fee at `redeem` time on v0.6.0; v0.5.x has none).
    function claimableRedeem() external view returns (uint256 _id, uint256 _shares) {
        _id = _getLagoonStorage()._redeemRequestId;
        if (_id == 0) return (0, 0);
        _shares = vault().claimableRedeemRequest(_id, address(this));
        if (_shares == 0) _id = 0;
    }

    /// @notice The currently-outstanding deposit request id, or `0` if none.
    function depositRequestId() external view returns (uint256) {
        return _getLagoonStorage()._depositRequestId;
    }

    /// @notice Idle + sweepable claimable redeem (net of exit fee). Closed-state drain is
    ///         keeper-only via `closeOutPosition` and excluded to avoid over-promising.
    function instantLiquidity() external view virtual override returns (uint256) {
        uint256 _idle = collateralToken().balanceOf(address(this));
        if (vault().paused()) return _idle;
        return _idle + _readBalances().claimableRedeem;
    }

    /// @notice True when async `requestDeposit` is callable — i.e. no sync window is open.
    ///         Sync deposits and async `requestDeposit` are temporally exclusive on every
    ///         Lagoon release.
    function isAsyncDepositEnabled() external view returns (bool) {
        return !vault().isTotalAssetsValid();
    }

    function isVaultPaused() external view returns (bool) {
        return vault().paused();
    }

    /// @notice Maximum fraction of `pool.totalDebtOf(strategy)` the keeper-driven
    ///         `_rebalance` may realize as loss in a single call. `0` blocks all
    ///         keeper-side loss reporting; `10_000` removes the cap. Governor-tunable
    ///         via `setMaxLossBps`. Defaults to `0` post-init.
    function maxLossBps() external view returns (uint16) {
        return _getLagoonStorage()._maxLossBps;
    }

    /// @notice The currently-outstanding redeem request id, or `0` if none.
    function redeemRequestId() external view returns (uint256) {
        return _getLagoonStorage()._redeemRequestId;
    }

    /// @notice Total assets owned: idle + every bucket from `_readBalances`.
    function tvl() public view virtual override returns (uint256) {
        AsyncBalances memory _balance = _readBalances();
        return
            collateralToken().balanceOf(address(this)) +
            _balance.pendingDeposit +
            _balance.claimableDeposit +
            _balance.assetsInVault +
            _balance.pendingRedeem +
            _balance.claimableRedeem;
    }

    function vault() public view returns (ILagoonVaultBase) {
        return ILagoonVaultBase(receiptToken());
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Approve all required tokens.
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        collateralToken().forceApprove(receiptToken(), amount_);
    }

    function _getLagoonStorage() internal pure returns (LagoonStorage storage $) {
        bytes32 _location = LAGOON_STORAGE_LOCATION;
        assembly {
            $.slot := _location
        }
    }

    /// @dev Lagoon's `_deposit` ignores the passed id and operates on `lastDepositRequestId`.
    function _processClaimableDeposits() internal returns (uint256 _sharesClaimed) {
        LagoonStorage storage $ = _getLagoonStorage();
        uint256 _id = $._depositRequestId;
        if (_id == 0) return 0;
        ILagoonVaultBase _vault = vault();
        uint256 _claimable = _vault.claimableDepositRequest(_id, address(this));
        if (_claimable > 0) {
            $._depositRequestId = 0;
            uint256 _sharesBefore = _vault.balanceOf(address(this));
            _vault.deposit(_claimable, address(this), address(this));
            _sharesClaimed = _vault.balanceOf(address(this)) - _sharesBefore;
            emit DepositClaimed(_id, _claimable, _sharesClaimed);
        } else if (_vault.pendingDepositRequest(_id, address(this)) == 0) {
            $._depositRequestId = 0;
            emit ExternalClaimReconciled(_id, true);
        }
    }

    function _processClaimableRedeems() internal returns (uint256 _assetsClaimed) {
        LagoonStorage storage $ = _getLagoonStorage();
        uint256 _id = $._redeemRequestId;
        if (_id == 0) return 0;
        ILagoonVaultBase _vault = vault();
        uint256 _claimable = _vault.claimableRedeemRequest(_id, address(this));
        if (_claimable > 0) {
            $._redeemRequestId = 0;
            IERC20 _collateral = collateralToken();
            uint256 _idleBefore = _collateral.balanceOf(address(this));
            _vault.redeem(_claimable, address(this), address(this));
            _assetsClaimed = _collateral.balanceOf(address(this)) - _idleBefore;
            emit RedeemClaimed(_id, _claimable, _assetsClaimed);
        } else if (_vault.pendingRedeemRequest(_id, address(this)) == 0) {
            $._redeemRequestId = 0;
            emit ExternalClaimReconciled(_id, false);
        }
    }

    /// @dev Pending values are gross (rate not yet locked); claimable values are net using
    ///      the per-batch frozen fee rate captured at settle (v0.6.0); v0.5.x returns 0
    ///      for both fee hooks because no entry/exit fees exist.
    function _readBalances() internal view returns (AsyncBalances memory _balance) {
        ILagoonVaultBase _vault = vault();
        LagoonStorage storage $ = _getLagoonStorage();

        uint256 _depositId = $._depositRequestId;
        if (_depositId != 0) {
            _balance.pendingDeposit = _vault.pendingDepositRequest(_depositId, address(this));
            uint256 _claimable = _vault.claimableDepositRequest(_depositId, address(this));
            if (_claimable > 0) {
                uint16 _entryRate = _entryFeeBpsForId(_vault, _depositId);
                _balance.claimableDeposit = (_claimable * (MAX_BPS - _entryRate)) / MAX_BPS;
            }
        }

        uint256 _redeemId = $._redeemRequestId;
        if (_redeemId != 0) {
            _balance.pendingRedeem = _vault.convertToAssets(_vault.pendingRedeemRequest(_redeemId, address(this)));
            uint256 _claimableShares = _vault.claimableRedeemRequest(_redeemId, address(this));
            if (_claimableShares > 0) {
                uint16 _exitRate = _exitFeeBpsForId(_vault, _redeemId);
                uint256 _grossAssets = _vault.convertToAssets(_claimableShares, _redeemId);
                _balance.claimableRedeem = (_grossAssets * (MAX_BPS - _exitRate)) / MAX_BPS;
            }
        }

        _balance.assetsInVault = _vault.convertToAssets(_vault.balanceOf(address(this)));
    }

    /// @inheritdoc Strategy
    /// @dev Vault-side calls are best-effort so `reportEarning` always works.
    /// @dev Two safety gates on the keeper path:
    ///       (1) Freeze mode — when the vault is paused (curator migration / emergency),
    ///           the strategy cannot claim, queue, or cancel anything vault-side and
    ///           `convertToAssets` may have collapsed to zero. Reporting that as loss
    ///           would lock in impairment that may still be recoverable. So we skip
    ///           profit/loss entirely and only flush idle for `_payback`.
    ///       (2) Loss cap — when not frozen, a `_loss > maxLossBps × debt` reverts with
    ///           `LossExceedsCap`. This is a hard safety rail: the keeper bot must NOT
    ///           silently bleed in large losses while a curator-driven migration is in
    ///           flight. Governor calls `reportLoss` to recognize impairment beyond
    ///           the cap on its own schedule.
    function _rebalance() internal virtual override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        ILagoonVaultBase _vault = vault();
        IVesperPool _pool = pool();
        IERC20 _collateral = collateralToken();
        LagoonStorage storage $ = _getLagoonStorage();

        if (_vault.paused()) {
            uint256 _idleNow = _collateral.balanceOf(address(this));
            _payback = Math.min(_idleNow, _pool.excessDebt(address(this)));
            if (_payback > 0) _pool.reportEarning(0, 0, _payback);
            return (0, 0, _payback);
        }

        this.tryProcessAllClaimable();

        uint256 _totalDebt = _pool.totalDebtOf(address(this));
        uint256 _totalAssets = tvl();
        uint256 _excessDebt = _pool.excessDebt(address(this));

        if (_totalAssets > _totalDebt) {
            _profit = _totalAssets - _totalDebt;
        } else if (_totalDebt > _totalAssets) {
            _loss = _totalDebt - _totalAssets;
            uint256 _maxLoss = (_totalDebt * $._maxLossBps) / MAX_BPS;
            if (_loss > _maxLoss) revert LossExceedsCap(_loss, _maxLoss);
        }

        // Budget-aware profit/payback sizing. The pool's `reportEarning` netts the strategy's
        // `(profit + payback)` against its `creditLine` and only requires idle for the residual
        // (see `VaultLogic.reportEarning`). Profit reportable without idle when `creditLine`
        // covers it. `_unrecognizedProfit` carries any remainder into the redeem queue below.
        uint256 _unrecognizedProfit;
        {
            uint256 _budget = _collateral.balanceOf(address(this)) + _pool.creditLimit(address(this));
            _payback = Math.min(_excessDebt, _budget);
            uint256 _reportable = Math.min(_profit, _budget - _payback);
            _unrecognizedProfit = _profit - _reportable;
            _profit = _reportable;
        }

        _pool.reportEarning(_profit, _loss, _payback);

        // Async-aware sizing in share-space: subtract in-flight pending redeems so we only
        // request the residual. `_shortfall` folds in any unrecognized profit so the next
        // rebalance (post-settle) can finish reporting what `creditLine` couldn't cover.
        uint256 _shortfall = _pool.excessDebt(address(this)) + _unrecognizedProfit;
        uint256 _sharesNeeded = _shortfall == 0 ? 0 : _vault.convertToShares(_shortfall);
        uint256 _redeemId = $._redeemRequestId;
        uint256 _pendingShares = _redeemId == 0 ? 0 : _vault.pendingRedeemRequest(_redeemId, address(this));
        if (_sharesNeeded > _pendingShares) {
            uint256 _sharesToRedeem = Math.min(_sharesNeeded - _pendingShares, _vault.balanceOf(address(this)));
            uint256 _claimableShares = _redeemId == 0 ? 0 : _vault.claimableRedeemRequest(_redeemId, address(this));
            if (_sharesToRedeem > 0 && _pendingShares == 0 && _claimableShares == 0) {
                try _vault.requestRedeem(_sharesToRedeem, address(this), address(this)) returns (uint256 _id) {
                    _trackRedeem(_id, _sharesToRedeem);
                } catch (bytes memory _reason) {
                    emit VaultActionSkipped(_vault.requestRedeem.selector, _reason);
                }
            }
        } else {
            _tryExecuteDeposit(_collateral.balanceOf(address(this)));
        }
    }

    function _trackDeposit(uint256 id_, uint256 assets_) internal {
        _getLagoonStorage()._depositRequestId = id_;
        emit DepositRequested(id_, assets_);
    }

    function _trackRedeem(uint256 id_, uint256 shares_) internal {
        _getLagoonStorage()._redeemRequestId = id_;
        emit RedeemRequested(id_, shares_);
    }

    /// @dev Best-effort variant of `_executeDeposit` for `_rebalance`. Swallows vault-side
    ///      reverts via `VaultActionSkipped` so `reportEarning` always lands.
    function _tryExecuteDeposit(uint256 assets_) internal {
        if (assets_ == 0) return;
        ILagoonVaultBase _vault = vault();
        if (_canSyncDeposit(_vault)) {
            uint256 _sharesBefore = _vault.balanceOf(address(this));
            try _vault.syncDeposit(assets_, address(this), address(0)) {
                emit DepositSynced(assets_, _vault.balanceOf(address(this)) - _sharesBefore);
            } catch (bytes memory _reason) {
                emit VaultActionSkipped(_vault.syncDeposit.selector, _reason);
            }
            return;
        }
        if (_vault.claimableDepositRequest(0, address(this)) != 0) return;
        try _vault.requestDeposit(assets_, address(this), address(this)) returns (uint256 _id) {
            _trackDeposit(_id, assets_);
        } catch (bytes memory _reason) {
            emit VaultActionSkipped(_vault.requestDeposit.selector, _reason);
        }
    }

    /// @inheritdoc Strategy
    /// @dev Sweep claimable redeems; `Strategy.withdraw` delivers from idle. Never queues a
    ///      new redeem (keeper-driven). `amount_` is intentionally unused.
    function _withdrawHere(uint256 /* amount_ */) internal virtual override {
        _processClaimableRedeems();
    }

    /*//////////////////////////////////////////////////////////////
                              VIRTUAL HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @notice Off-chain helper for monitors: true if the strategy address is on the curator's
    ///         whitelist. v0.5.x calls `isWhitelisted`; v0.6.0 calls `isAllowed`.
    function isStrategyAllowedInVault() external view virtual returns (bool);

    /// @dev True when Lagoon's `syncDeposit` is callable for the given vault.
    function _canSyncDeposit(ILagoonVaultBase vault_) internal view virtual returns (bool);

    /// @dev Concretes return the entry-fee BPS frozen at the settle of `requestId_`. v0.5.x
    ///      has no entry fee; the V05 concrete returns 0.
    function _entryFeeBpsForId(ILagoonVaultBase vault_, uint256 requestId_) internal view virtual returns (uint16);

    /// @dev Concretes return the exit-fee BPS frozen at the settle of `requestId_`. v0.5.x
    ///      has no exit fee; the V05 concrete returns 0.
    function _exitFeeBpsForId(ILagoonVaultBase vault_, uint256 requestId_) internal view virtual returns (uint16);

    /// @dev Concretes assert the supported `version()` string(s). Reverts on rejection.
    function _postInitVaultChecks(ILagoonVaultBase vault_) internal view virtual;

    /*//////////////////////////////////////////////////////////////
                        GOVERNOR/KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cancel the outstanding async deposit request and pull the assets back from the
    ///         pendingSilo. Only callable while the request is still in its same epoch — once
    ///         the curator settles, Lagoon reverts with `RequestNotCancelable(id)`.
    /// @param  minReturned_ slippage floor on the returned amount; pass `0` to skip.
    /// @return _assetsReturned collateral delivered back to the strategy.
    function cancelDeposit(uint256 minReturned_) external onlyKeeper returns (uint256 _assetsReturned) {
        LagoonStorage storage $ = _getLagoonStorage();
        uint256 _id = $._depositRequestId;
        if (_id == 0) revert NoOutstandingRequest();
        IERC20 _collateral = collateralToken();
        uint256 _idleBefore = _collateral.balanceOf(address(this));
        $._depositRequestId = 0;
        vault().cancelRequestDeposit();
        _assetsReturned = _collateral.balanceOf(address(this)) - _idleBefore;
        if (_assetsReturned < minReturned_) revert SlippageExceeded(minReturned_, _assetsReturned);
        emit DepositCanceled(_id, _assetsReturned);
    }

    /// @notice One-shot redeem of residual shares after the vault has transitioned to `Closed`.
    ///         Sweeps any settled claimable first, then calls `vault.redeem(balance, ...)` —
    ///         Lagoon's Closed-state branch handles the sync drain.
    /// @dev    No `isClosed` pre-check because real Lagoon doesn't expose `state()`. Outside
    ///         the Closed state — or while a claimable redeem is still queued — Lagoon's
    ///         `redeem` falls through `_redeem` and reverts with `RequestIdNotClaimable`,
    ///         which self-protects against misuse.
    /// @param  minAssetsClaimed_ aggregate floor over sweep + residual drain; pass `0` to skip.
    function closeOutPosition(uint256 minAssetsClaimed_) external onlyKeeper returns (uint256 _assetsClaimed) {
        _processClaimableDeposits();
        IERC20 _collateral = collateralToken();
        uint256 _idleBefore = _collateral.balanceOf(address(this));
        _processClaimableRedeems();
        ILagoonVaultBase _vault = vault();
        uint256 _residual = _vault.balanceOf(address(this));
        if (_residual > 0) {
            uint256 _drained = _vault.redeem(_residual, address(this), address(this));
            emit PositionClosed(_residual, _drained);
        }
        _assetsClaimed = _collateral.balanceOf(address(this)) - _idleBefore;
        if (_assetsClaimed < minAssetsClaimed_) revert SlippageExceeded(minAssetsClaimed_, _assetsClaimed);
    }

    /// @notice Sweep both sides with aggregate slippage floors. Reverts if total shares
    ///         minted on the deposit side < `minSharesClaimed_` OR total assets received on the
    ///         redeem side < `minAssetsClaimed_`. Pass `0` for either to skip the corresponding
    ///         floor. Sweep is strict — any per-claim revert aborts the whole call.
    function processAllClaimable(
        uint256 minSharesClaimed_,
        uint256 minAssetsClaimed_
    ) external onlyKeeper returns (uint256 _sharesClaimed, uint256 _assetsClaimed) {
        _sharesClaimed = _processClaimableDeposits();
        if (_sharesClaimed < minSharesClaimed_) revert SlippageExceeded(minSharesClaimed_, _sharesClaimed);
        _assetsClaimed = _processClaimableRedeems();
        if (_assetsClaimed < minAssetsClaimed_) revert SlippageExceeded(minAssetsClaimed_, _assetsClaimed);
    }

    function processClaimableDeposits(
        uint256 minSharesClaimed_
    ) external onlyKeeperOrSelf returns (uint256 _sharesClaimed) {
        _sharesClaimed = _processClaimableDeposits();
        if (_sharesClaimed < minSharesClaimed_) revert SlippageExceeded(minSharesClaimed_, _sharesClaimed);
    }

    function processClaimableRedeems(
        uint256 minAssetsClaimed_
    ) external onlyKeeperOrSelf returns (uint256 _assetsClaimed) {
        _assetsClaimed = _processClaimableRedeems();
        if (_assetsClaimed < minAssetsClaimed_) revert SlippageExceeded(minAssetsClaimed_, _assetsClaimed);
    }

    /// @notice Deposit collateral. Pre-sweeps any settled claimable, then routes sync if
    ///         the gate is open, async otherwise. Reverts propagate so typed errors surface.
    /// @param  assets_ collateral amount; must be ≤ idle balance.
    /// @return _requestId vault-assigned id for the async path; `0` if the sync path was taken
    ///         (caller distinguishes via `DepositSynced` vs `DepositRequested`).
    function requestDeposit(uint256 assets_) external onlyKeeper returns (uint256 _requestId) {
        if (assets_ == 0) revert ZeroAmount();
        _processClaimableDeposits();
        ILagoonVaultBase _vault = vault();
        if (_canSyncDeposit(_vault)) {
            uint256 _sharesBefore = _vault.balanceOf(address(this));
            _vault.syncDeposit(assets_, address(this), address(0));
            emit DepositSynced(assets_, _vault.balanceOf(address(this)) - _sharesBefore);
            return 0;
        }
        _requestId = _vault.requestDeposit(assets_, address(this), address(this));
        _trackDeposit(_requestId, assets_);
    }

    /// @notice Queue an async redeem. Mirrors `requestDeposit`'s pre-sweep posture.
    function requestRedeem(uint256 shares_) external onlyKeeper returns (uint256 _requestId) {
        if (shares_ == 0) revert ZeroAmount();
        _processClaimableRedeems();
        _requestId = vault().requestRedeem(shares_, address(this), address(this));
        _trackRedeem(_requestId, shares_);
    }

    /// @notice Governor-only explicit loss recognition. Escape hatch for impairment that
    ///         exceeds the keeper-side cap (`maxLossBps`) — e.g. confirmed curator
    ///         migration, vault exploit, permanent share-price collapse.
    /// @dev    Intentionally NOT gated on `vault.paused()`. Governor is trusted to time
    ///         the call (typically: defer until the curator-driven migration has settled
    ///         and the final impairment is known).
    /// @param  loss_ collateral-denominated loss to book against the pool.
    function reportLoss(uint256 loss_) external onlyGovernor {
        pool().reportEarning(0, loss_, 0);
        emit LossReported(loss_);
    }

    /// @notice Update the per-rebalance keeper-side loss cap. `0` blocks all keeper-side
    ///         loss reporting (all impairment must flow through `reportLoss`); `10_000`
    ///         removes the cap and restores the pre-patch behavior.
    /// @param  maxLossBps_ basis points, ≤ `MAX_BPS` (10_000).
    function setMaxLossBps(uint16 maxLossBps_) external onlyGovernor {
        if (maxLossBps_ > MAX_BPS) revert MaxLossBpsTooHigh(maxLossBps_);
        LagoonStorage storage $ = _getLagoonStorage();
        emit MaxLossBpsUpdated($._maxLossBps, maxLossBps_);
        $._maxLossBps = maxLossBps_;
    }

    /// @notice Best-effort combined sweep — per-side reverts emit `VaultActionSkipped`.
    function tryProcessAllClaimable()
        external
        onlyKeeperOrSelf
        returns (uint256 _sharesClaimed, uint256 _assetsClaimed)
    {
        try this.processClaimableDeposits(0) returns (uint256 _shares) {
            _sharesClaimed = _shares;
        } catch (bytes memory _reason) {
            emit VaultActionSkipped(this.processClaimableDeposits.selector, _reason);
        }
        try this.processClaimableRedeems(0) returns (uint256 _assets) {
            _assetsClaimed = _assets;
        } catch (bytes memory _reason) {
            emit VaultActionSkipped(this.processClaimableRedeems.selector, _reason);
        }
    }
}
