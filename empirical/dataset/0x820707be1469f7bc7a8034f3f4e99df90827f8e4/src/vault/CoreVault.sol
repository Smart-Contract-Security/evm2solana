// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { CoreAccess } from "../base/CoreAccess.sol";
import { IAssetCustodian } from "../interfaces/IAssetCustodian.sol";
import { IBlocklist } from "../interfaces/IBlocklist.sol";
import { IFeeManager } from "../interfaces/IFeeManager.sol";
import { IERC7575 } from "../interfaces/IERC7575.sol";
import { INAVOracle } from "../interfaces/INAVOracle.sol";
import { IRebalanceManager } from "../interfaces/IRebalanceManager.sol";
import { IRequestManager } from "../interfaces/IRequestManager.sol";
import { IShareToken } from "../interfaces/IShareToken.sol";
import { IWhitelist } from "../interfaces/IWhitelist.sol";
import { IVaultSettlement } from "../interfaces/IVaultSettlement.sol";
import {
    BatchHint,
    OndoTarget,
    PassiveRebalanceParams,
    RebalanceBuy,
    RebalanceTrigger,
    SignedPriceBundle,
    Trade
} from "../interfaces/Types.sol";
import { FixedPoint } from "../libraries/FixedPoint.sol";
import { Roles } from "../libraries/Roles.sol";

/// @title CoreVault
contract CoreVault is CoreAccess, Pausable, ReentrancyGuard, IVaultSettlement, IERC7575 {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_STOCK_TOKENS = 20;

    enum VaultStatus {
        Normal,
        Rebalancing,
        Paused,
        Clearing
    }

    IShareToken public shareToken;
    IERC20 public usdc;
    INAVOracle public navOracle;
    IWhitelist public whitelist;
    IBlocklist public blocklist;
    IFeeManager public feeManager;
    IRequestManager public requestManager;
    IRebalanceManager public rebalanceManager;
    IAssetCustodian public ac;
    VaultStatus public vaultStatus;
    uint256 public minRedeemAssets;
    uint16 public defaultSlippageBps;
    uint16 public defaultLossPercentBps;

    uint256 public minDeposit;
    uint256 public maxDepositAmount;
    uint256 public tvlCap;
    uint256 public completedDepositAssets;
    uint256 public pendingDepositAssets;

    uint256 public latestTotalAssetsValue;
    mapping(uint256 => uint256) public totalAssetsByRound;

    address[] public _stockTokens;
    mapping(address => uint256) public targetWeightBps;

    bool public whitelistRequired;

    string public vaultName;
    string public vaultSymbol;

    /// @notice Subscription fee rate, in bps (per ten thousand), for example, 50 = 0.5%.
    uint16 public depositFeeBps;
    address public feeRecipient;

    bool private _coreVaultInitialized;

    event ACSet(address indexed ac);
    event FeeManagerSet(address indexed feeManager);
    event RequestManagerSet(address indexed requestManager);
    event RebalanceManagerSet(address indexed rebalanceManager);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event DepositRequested(
        uint256 indexed reqId, address indexed owner, uint256 assets, uint256 shares, bytes32 groupId
    );
    event RedeemRequested(uint256 indexed reqId, address indexed owner, uint256 shares, bytes32 groupId);
    event DepositFulfilled(uint256 indexed reqId, address indexed owner, uint256 shares, uint256 refundUsdc);
    event RedeemFulfilled(uint256 indexed reqId, address indexed owner, uint256 shares, uint256 usdcReceived);
    event RequestFailed(uint256 indexed reqId, bool deposit, bytes reason);
    event OndoTargetsSet(bytes32 indexed allocationHash);
    event RebalanceRequested(bytes32 indexed rbId, bytes32 indexed groupId);
    event RebalanceFailed(bytes32 indexed rbId, bytes reason);
    event PassiveRebalanceRequested(
        bytes32 indexed rbId,
        bytes32 indexed groupId,
        RebalanceTrigger indexed trigger,
        uint8 riskLevel,
        bytes32 reasonHash
    );
    event RebalanceFulfilled(bytes32 indexed rbId, uint256 totalAssetsAfter);
    event TotalAssetsUpdated(uint256 indexed round, uint256 totalAssetsValue);
    event VaultForcedNormal(address indexed caller);

    modifier onlyAc() {
        _onlyAc();
        _;
    }

    modifier onlyNormalVault() {
        _onlyNormalVault();
        _;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC7575).interfaceId;
    }

    function share() external view returns (address shareTokenAddress) {
        return address(shareToken);
    }

    function asset() external view returns (address assetTokenAddress) {
        return address(usdc);
    }

    constructor(
        address admin,
        string memory vaultName_,
        string memory vaultSymbol_,
        address shareToken_,
        address usdc_,
        address navOracle_,
        address whitelist_,
        address blocklist_
    ) CoreAccess(admin) {
        if (admin != address(0)) {
            _initializeCoreVault(vaultName_, vaultSymbol_, shareToken_, usdc_, navOracle_, whitelist_, blocklist_);
        }
    }

    function initialize(
        address admin,
        string memory vaultName_,
        string memory vaultSymbol_,
        address shareToken_,
        address usdc_,
        address navOracle_,
        address whitelist_,
        address blocklist_
    ) external {
        _initializeCoreAccess(admin);
        _initializeCoreVault(vaultName_, vaultSymbol_, shareToken_, usdc_, navOracle_, whitelist_, blocklist_);
    }

    function _initializeCoreVault(
        string memory vaultName_,
        string memory vaultSymbol_,
        address shareToken_,
        address usdc_,
        address navOracle_,
        address whitelist_,
        address blocklist_
    ) internal {
        require(!_coreVaultInitialized, "CV:INIT");
        require(shareToken_ != address(0) && usdc_ != address(0) && navOracle_ != address(0), "CV:ZA");
        _coreVaultInitialized = true;
        vaultName = vaultName_;
        vaultSymbol = vaultSymbol_;
        shareToken = IShareToken(shareToken_);
        usdc = IERC20(usdc_);
        navOracle = INAVOracle(navOracle_);
        whitelist = IWhitelist(whitelist_);
        blocklist = IBlocklist(blocklist_);
    }

    function setAc(address ac_) external onlyAdmin {
        require(ac_ != address(0), "CV:ZA");
        ac = IAssetCustodian(ac_);
        emit ACSet(ac_);
    }

    function setFeeManager(address feeManager_) external onlyAdmin {
        feeManager = IFeeManager(feeManager_);
        emit FeeManagerSet(feeManager_);
    }

    function setRequestManager(address requestManager_) external onlyAdmin {
        require(requestManager_ != address(0), "CV:ZA");
        requestManager = IRequestManager(requestManager_);
        emit RequestManagerSet(requestManager_);
    }

    function setRebalanceManager(address rebalanceManager_) external onlyAdmin {
        require(rebalanceManager_ != address(0), "CV:ZA");
        rebalanceManager = IRebalanceManager(rebalanceManager_);
        emit RebalanceManagerSet(rebalanceManager_);
    }

    function setRiskParams(uint256 minDeposit_, uint256 maxDeposit_, uint256 tvlCap_, uint256 minRedeemAssets_) external onlyAdmin {
        require(minDeposit_ <= maxDeposit_, "CV:DR");
        minDeposit = minDeposit_;
        maxDepositAmount = maxDeposit_;
        minRedeemAssets = minRedeemAssets_;
        tvlCap = tvlCap_;
    }

    function setDefaultSlippageBps(uint16 slippageBps) external onlyAdmin {
        require(slippageBps <= 2000, "CV:SL");
        defaultSlippageBps = slippageBps;
    }

    function setDefaultLossPercentBps(uint16 lossPercentBps) external onlyAdmin {
        require(lossPercentBps <= 10_000, "CV:LP");
        defaultLossPercentBps = lossPercentBps;
    }

    function setWhitelistRequired(bool required) external onlyAdmin {
        whitelistRequired = required;
    }

    function setFeeParams(uint16 depositFeeBps_, address feeRecipient_) external onlyAdmin {
        require(feeRecipient_ != address(0), "CV:ZA");
        depositFeeBps = depositFeeBps_;
        feeRecipient = feeRecipient_;
    }

    function setOndoTargets(OndoTarget[] calldata targets) external onlyRole(Roles.ONDO_TARGET_MANAGER) {
        _validateOndoTargets(targets);
        for (uint256 i; i < _stockTokens.length; ++i) {
            targetWeightBps[_stockTokens[i]] = 0;
        }
        delete _stockTokens;
        for (uint256 i; i < targets.length; ++i) {
            _stockTokens.push(targets[i].token);
            targetWeightBps[targets[i].token] = targets[i].bps;
        }
        emit OndoTargetsSet(_ondoAllocationHash());
    }

    function pause() external onlyRole(Roles.PAUSE_ROLE) {
        if (vaultStatus != VaultStatus.Clearing) vaultStatus = VaultStatus.Paused;
        _pause();
    }

    function unpause() external onlyRole(Roles.PAUSE_ROLE) {
        _unpause();
        if (address(rebalanceManager) != address(0) && rebalanceManager.activeRebalanceId() != bytes32(0)) {
            vaultStatus = VaultStatus.Rebalancing;
        } else if (vaultStatus == VaultStatus.Paused) {
            vaultStatus = VaultStatus.Normal;
        }
    }

    function forceNormal() external onlyAdmin {
        if (paused()) _unpause();
        vaultStatus = VaultStatus.Normal;
        emit VaultForcedNormal(msg.sender);
    }

    /// @notice User initiates USDC purchase.
    /// @dev Process: Verify price bundle signature -> Calculate expected Share -> Retrieve user's USDC -> Transfer to AC -> AC calls Proxy.
    /// @param assets Quantity of USDC purchased, 6-digit precision.
    /// @param owner Source of funds and final Share recipient.
    /// @param priceBundle Price bundle signed by the trusted signer.
    /// @param minSharesOut Minimum acceptable shares for slippage protection.
    /// @return reqId ID of this asynchronous request.
    /// @return feeAmount USDC subscription fee charged for this request.
    function requestDeposit(
        uint256 assets,
        address owner,
        SignedPriceBundle calldata priceBundle,
        uint256 minSharesOut
    )
        external
        whenNotPaused
        onlyNormalVault
        nonReentrant
        returns (uint256 reqId, uint256 feeAmount)
    {
        uint64 round = navOracle.ingest(priceBundle);
        _updateTotalAssetsForRound(round);
        _accrueManagementFeeIfConfigured();
        return _requestDeposit(assets, owner, round, minSharesOut);
    }

    /// @notice User initiates a share redemption.
    // @dev Process: Verify price bundle signature -> Lock user Share -> Transfer underlying assets to AC
    // according to share -> AC calls Proxy Sell.
    // @param shares Share token amount to redeem, 18-digit precision.
    // @param owner Source of Shares and final USDC recipient.
    // @param priceBundle Price bundle signed by the trusted signer.
    // @return reqId ID of this asynchronous request.
    function requestRedeem(uint256 shares, address owner, SignedPriceBundle calldata priceBundle)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 reqId)
    {
        require(vaultStatus == VaultStatus.Normal || vaultStatus == VaultStatus.Clearing, "CV:NN");
        uint64 round = navOracle.ingest(priceBundle);
        _updateTotalAssetsForRound(round);
        _accrueManagementFeeIfConfigured();
        return _requestRedeem(shares, owner, round);
    }


    /// @notice Curator active rebalancing entry point. Uses the same two-phase sell/buy flow as passive rebalancing.
    function requestRebalance(
        Trade[] calldata sells,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights,
        SignedPriceBundle calldata priceBundle
    )
        external
        onlyRole(Roles.CURATOR)
        whenNotPaused
        onlyNormalVault
        nonReentrant
        returns (bytes32 rbId, bytes32 groupId)
    {
        require(address(rebalanceManager) != address(0), "CV:RB0");
        uint64 round = navOracle.ingest(priceBundle);
        _updateTotalAssetsForRound(round);
        _accrueManagementFeeIfConfigured();
        rbId = rebalanceManager.prepareActiveRebalance(sells.length, buys.length, buys, targetTokens, targetWeights);
        _savePendingOndoTargets(rbId, targetTokens, targetWeights);
        vaultStatus = VaultStatus.Rebalancing;
        groupId = _dispatchPassiveRebalance(rbId, sells, buys, RebalanceTrigger.Active);
        require(groupId != bytes32(0), "CV:ZB");
        emit RebalanceRequested(rbId, groupId);
    }

    /// @notice Monitor Service Passive portfolio rebalancing entry point.
    function requestPassiveRebalance(PassiveRebalanceParams calldata params)
        external
        onlyRole(Roles.MONITOR)
        whenNotPaused
        onlyNormalVault
        nonReentrant
        returns (bytes32 rbId, bytes32 groupId)
    {
        require(address(rebalanceManager) != address(0), "CV:RB0");
        uint64 round = navOracle.ingest(params.priceBundle);
        _updateTotalAssetsForRound(round);
        _accrueManagementFeeIfConfigured();
        rbId = rebalanceManager.preparePassiveRebalance(
            params.sells.length,
            params.buys.length,
            params.trigger,
            params.riskLevel,
            params.reasonHash,
            params.buys,
            params.targetTokens,
            params.targetWeights
        );
        _savePendingOndoTargets(rbId, params.targetTokens, params.targetWeights);
        vaultStatus = VaultStatus.Rebalancing;
        // Distribute and adjust stacks to reduce the stack depth of individual functions.
        groupId = _dispatchPassiveRebalance(rbId, params.sells, params.buys, params.trigger);
        require(groupId != bytes32(0), "CV:ZB");
        emit PassiveRebalanceRequested(rbId, groupId, params.trigger, params.riskLevel, params.reasonHash);
    }

    /// --------------------------------- Settlement Entry Points (Called by AC) -----------------------------------
    function settleDeposit(
        bytes32 groupId,
        uint256 reqId,
        address[] calldata etfTokens,
        uint256[] calldata amounts,
        uint256 refundUsdc,
        uint256 navRound
    ) external onlyAc nonReentrant {
        require(etfTokens.length == amounts.length, "CV:LEN");
        _validateSettlementNavRound(navRound);
        IRequestManager.DepositSettlement memory result =
            requestManager.settleDeposit(groupId, reqId, refundUsdc);
        pendingDepositAssets -= result.spent + result.refund;
        completedDepositAssets += result.spent;
        if (result.shares > 0) {
            shareToken.mint(result.owner, result.shares);
            if (address(feeManager) != address(0)) feeManager.startAccrual();
            emit DepositFulfilled(reqId, result.owner, result.shares, 0);
        }
    }

    function settleRedeem(bytes32 groupId, uint256 reqId, uint256 usdcReceived, uint256 navRound)
        external
        onlyAc
        nonReentrant
    {
        _validateSettlementNavRound(navRound);
        IRequestManager.RedeemSettlement memory result =
            requestManager.settleRedeem(groupId, reqId, usdcReceived);
        if (result.fulfilledShares > 0) {
            shareToken.burn(address(this), result.fulfilledShares);
        }
        if (result.payout > 0) {
            usdc.safeTransfer(result.owner, result.payout);
        }
        emit RedeemFulfilled(reqId, result.owner, result.fulfilledShares, result.payout);
    }

    function settleRebalance(bytes32 rbId, address[] calldata tokens, uint256[] calldata amounts)
        external
        onlyAc
        nonReentrant
    {
        require(tokens.length == amounts.length, "CV:LEN");
        uint256 round = navOracle.latestRound();
        uint256 totalAssetsAfter = _updateTotalAssetsForRound(round);
        rebalanceManager.settleRebalanceComplete(rbId, tokens, amounts);
        _applyPendingOndoTargets(rbId);
        vaultStatus = paused()
            ? VaultStatus.Paused
            : rebalanceManager.rebalanceRiskLevel(rbId) == 3 ? VaultStatus.Clearing : VaultStatus.Normal;
        emit RebalanceFulfilled(rbId, totalAssetsAfter);
    }

    function settleRebalanceFailure(bytes32 rbId, bytes calldata reason) external onlyAc nonReentrant {
        vaultStatus = paused() ? VaultStatus.Paused : VaultStatus.Normal;
        rebalanceManager.settleRebalanceFailed(rbId);
        _clearPendingOndoTargets(rbId);
        emit RebalanceFailed(rbId, reason);
    }

    function settleFailure(bytes32 groupId, uint256 reqId, uint256 returnedUsdc, bytes calldata reason)
        external
        onlyAc
        nonReentrant
    {
        IRequestManager.RequestData memory request = requestManager.getRequest(reqId);
        IRequestManager.FailureSettlement memory result =
            requestManager.settleRequestFailure(groupId, reqId, returnedUsdc);
        if (result.isDeposit) {
            pendingDepositAssets -= request.assets;
            if (result.refund > 0) usdc.safeTransfer(result.owner, result.refund);
            emit RequestFailed(reqId, true, reason);
        } else {
            IERC20(address(shareToken)).safeTransfer(result.owner, result.shares);
            emit RequestFailed(reqId, false, reason);
        }
    }

    /// ---------------------------Fee Calculate---------------------------------

    /// @notice Settle dividend fees with the latest signed price package
    function settlePerformanceFee(SignedPriceBundle calldata priceBundle)
        external
        onlyRole(Roles.OPERATOR)
        nonReentrant
        returns (uint256)
    {
        require(vaultStatus == VaultStatus.Normal, "CV:NN");
        uint64 round = navOracle.ingest(priceBundle);
        _updateTotalAssetsForRound(round);
        _accrueManagementFeeIfConfigured();
        if (address(feeManager) == address(0)) return 0;
        uint256 totalAssetsValue = _totalAssetsForRound(round);
        (uint256 shares,) = feeManager.settlePerformanceFee(totalAssetsValue, effectiveTotalSupply());
        return shares;
    }

    /// @dev Lazy loading supplements management fees
    function _accrueManagementFeeIfConfigured() internal returns (uint256 shares) {
        if (address(feeManager) == address(0)) return 0;
        uint256 supply = effectiveTotalSupply();
        if (supply == 0) return 0;
        shares = feeManager.accrueManagementFee(totalAssets(), supply);
    }

    ///  ---------------------------Public Function---------------------------------

    function getTargetAllocation() public view returns (address[] memory tokens, uint256[] memory weights) {
        tokens = new address[](_stockTokens.length);
        weights = new uint256[](_stockTokens.length);
        for (uint256 i; i < _stockTokens.length; ++i) {
            tokens[i] = _stockTokens[i];
            weights[i] = targetWeightBps[_stockTokens[i]];
        }
    }

    function totalAssets() public view returns (uint256) {
        return latestTotalAssetsValue;
    }

    /// @notice Recomputes and returns the net asset value per share (NAV) from a signed price bundle without updating state.
    // @dev NAV = totalAssetsValue / effectiveTotalSupply. The initial NAV is 1e18 (i.e., 1 USDC/share).
    function navPerShare(SignedPriceBundle calldata priceBundle) public view returns (uint256) {
        uint256 totalAssetsValue = navOracle.recomputeTotalAssetsFromBundle(address(this), address(usdc), priceBundle);
        uint256 supply = effectiveTotalSupply() - requestManager.escrowedShares();
        if (supply == 0) return 1e18;
        return totalAssetsValue * 1e18 / supply;
    }

    function totalSupply() public view returns (uint256) {
        return IERC20(address(shareToken)).totalSupply();
    }

    /// @notice Returns the effective total share used for valuation, which is the actual total supply plus the share of uncrystallized costs.
    function effectiveTotalSupply() public view returns (uint256) {
        if (address(feeManager) == address(0)) return totalSupply();
        return feeManager.effectiveTotalSupply(totalSupply());
    }

    function convertToShares(uint256 assets, SignedPriceBundle calldata priceBundle) external view returns (uint256) {
        return _previewDeposit(
            FixedPoint.usdcToWad(assets),
            navOracle.recomputeTotalAssetsFromBundle(address(this), address(usdc), priceBundle),
            effectiveTotalSupply() - requestManager.escrowedShares()
        );
    }

    function previewDepositWithFee(uint256 assets, SignedPriceBundle calldata priceBundle)
        external
        view
        returns (uint256 shares, uint256 feeAmount)
    {
        feeAmount = assets * depositFeeBps / 10_000;
        uint256 netAssets = assets - feeAmount;
        shares = _previewDeposit(
            FixedPoint.usdcToWad(netAssets),
            navOracle.recomputeTotalAssetsFromBundle(address(this), address(usdc), priceBundle),
            effectiveTotalSupply() - requestManager.escrowedShares()
        );
    }

    function convertToAssets(uint256 shares, SignedPriceBundle calldata priceBundle) external view returns (uint256) {
        uint256 supply = effectiveTotalSupply() - requestManager.escrowedShares();
        if (supply == 0) return 0;
        return FixedPoint.wadToUsdc(
            shares * navOracle.recomputeTotalAssetsFromBundle(address(this), address(usdc), priceBundle) / supply
        );
    }

    ///  ---------------------------Private Function---------------------------------

    function _requestDeposit(uint256 assets, address owner, uint64 round, uint256 minSharesOut)
        internal
        returns (uint256 reqId, uint256 feeAmount)
    {
        require(address(ac) != address(0), "CV:AC0");
        require(address(requestManager) != address(0), "CV:RM0");
        require(assets >= minDeposit && assets <= maxDepositAmount, "CV:DB");
        _checkAccount(owner);
        require(msg.sender == owner, "CV:OP");
        // Deposit Fee
        feeAmount = assets * depositFeeBps / 10_000;
        uint256 netAssets = assets - feeAmount;
        require(totalAssets() + FixedPoint.usdcToWad(pendingDepositAssets + netAssets) <= tvlCap, "CV:CAP");
        if (feeAmount > 0 && feeRecipient != address(0)) {
            usdc.safeTransferFrom(owner, feeRecipient, feeAmount);
        }
        usdc.safeTransferFrom(owner, address(ac), netAssets);
        pendingDepositAssets += netAssets;
        // execution
        uint256 totalAssetsValue = _totalAssetsForRound(round);
        uint256 supply = effectiveTotalSupply() - requestManager.escrowedShares();
        uint256 shares = _previewDeposit(FixedPoint.usdcToWad(netAssets), totalAssetsValue, supply);
        require(shares >= minSharesOut, "CV:MS");
        reqId = requestManager.createDepositRequest(owner, netAssets, shares, round, totalAssetsValue, supply);
        bytes32 expectedGroupId = ac.previewNextGroupId();
        requestManager.setGroupId(reqId, expectedGroupId);
        bytes32 groupId = ac.executeDeposit(reqId, netAssets, _defaultBatchHint());
        require(groupId == expectedGroupId, "CV:GB");
        emit Deposit(msg.sender, owner, assets, shares);
        emit DepositRequested(reqId, owner, netAssets, shares, groupId);
    }

    function _requestRedeem(uint256 shares, address owner, uint64 round)
        internal
        returns (uint256 reqId)
    {
        require(address(ac) != address(0), "CV:AC0");
        require(address(requestManager) != address(0), "CV:RM0");
        require(shares > 0, "CV:ZS");
        _checkAccount(owner);
        require(msg.sender == owner, "CV:OP");
        uint256 totalAssetsValue = _totalAssetsForRound(round);
        uint256 availableSupply = effectiveTotalSupply() - requestManager.escrowedShares();
        require(totalAssetsValue > 0 && availableSupply > 0, "CV:ZR");
        require(shares <= availableSupply, "CV:RS");
        uint256 expectedAssets = shares * totalAssetsValue / availableSupply;
        require(minRedeemAssets == 0 || expectedAssets >= FixedPoint.usdcToWad(minRedeemAssets), "CV:BRA");
        reqId = requestManager.createRedeemRequest(owner, shares, round, totalAssetsValue, availableSupply, expectedAssets);
        bytes32 expectedGroupId = ac.previewNextGroupId();
        requestManager.setGroupId(reqId, expectedGroupId);
        IERC20(address(shareToken)).safeTransferFrom(owner, address(this), shares);
        bytes32 groupId = _dispatchRedeem(reqId, shares, availableSupply);
        require(groupId == expectedGroupId, "CV:GB");
        emit Withdraw(msg.sender, owner, owner, 0, shares);
        emit RedeemRequested(reqId, owner, shares, groupId);
    }

    function _dispatchRedeem(uint256 reqId, uint256 shares, uint256 supply)
        internal
        returns (bytes32 groupId)
    {
        (address[] memory tokens, uint256[] memory amounts) = _transferRedeemBasketToAc(shares, supply);
        groupId = ac.executeRedeem(reqId, tokens, amounts, _defaultBatchHint());
    }

    function _dispatchPassiveRebalance(
        bytes32 rbId,
        Trade[] calldata sells,
        RebalanceBuy[] calldata buys,
        RebalanceTrigger trigger
    ) internal returns (bytes32 groupId) {
        _transferRebalanceSellsToAc(sells);
        groupId = ac.executeRebalance(rbId, sells, buys, trigger, _defaultBatchHint());
    }

    function _transferRebalanceSellsToAc(Trade[] calldata sells) internal {
        for (uint256 i; i < sells.length; ++i) {
            require(sells[i].amountIn > 0, "CV:ZS");
            IERC20(sells[i].tokenIn).safeTransfer(address(ac), sells[i].amountIn);
        }
    }

    function _transferRedeemBasketToAc(uint256 shares, uint256 supply)
        internal
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        uint256 count = _stockTokens.length;
        tokens = new address[](count);
        amounts = new uint256[](count);
        if (supply == 0) return (tokens, amounts);
        for (uint256 i; i < count; ++i) {
            address token = _stockTokens[i];
            tokens[i] = token;
            uint256 bal = IERC20(token).balanceOf(address(this));
            uint256 amt = bal * shares / supply;
            amounts[i] = amt;
            if (amt > 0) IERC20(token).safeTransfer(address(ac), amt);
        }
    }

    function _defaultBatchHint() internal view returns (BatchHint memory) {
        return BatchHint({ maxSlippageBps: defaultSlippageBps, maxLossPercentBps: defaultLossPercentBps });
    }


    function _setOndoTargetsFromPending(bytes32 rbId) internal {
        OndoTarget[] memory pending = rebalanceManager.getPendingOndoTargets(rbId);
        for (uint256 i; i < _stockTokens.length; ++i) {
            targetWeightBps[_stockTokens[i]] = 0;
        }
        delete _stockTokens;
        for (uint256 i; i < pending.length; ++i) {
            _stockTokens.push(pending[i].token);
            targetWeightBps[pending[i].token] = pending[i].bps;
        }
        emit OndoTargetsSet(_ondoAllocationHash());
    }

    function _savePendingOndoTargets(
        bytes32 rbId,
        address[] calldata targetTokens,
        uint256[] calldata targetWeights
    ) internal {
        require(targetTokens.length <= MAX_STOCK_TOKENS, "CV:TL");
        rebalanceManager.savePendingOndoTargets(rbId, targetTokens, targetWeights);
    }

    function _applyPendingOndoTargets(bytes32 rbId) internal {
        _setOndoTargetsFromPending(rbId);
        _clearPendingOndoTargets(rbId);
    }

    function _clearPendingOndoTargets(bytes32 rbId) internal {
        rebalanceManager.clearPendingOndoTargets(rbId);
    }

    function _validateOndoTargets(OndoTarget[] calldata targets) internal pure {
        require(targets.length <= MAX_STOCK_TOKENS, "CV:TL");
        uint256 total;
        for (uint256 i; i < targets.length; ++i) {
            require(targets[i].token != address(0), "CV:ZA");
            for (uint256 j; j < i; ++j) {
                require(targets[i].token != targets[j].token, "CV:DUP");
            }
            total += targets[i].bps;
        }
        require(total == 10_000, "CV:BT");
    }

    function _ondoAllocationHash() internal view returns (bytes32) {
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encode(_stockTokens, _targetWeights()));
    }

    function _onlyAc() internal view {
        require(msg.sender == address(ac), "CV:AC");
    }

    function _onlyNormalVault() internal view {
        require(vaultStatus == VaultStatus.Normal, "CV:NN");
    }

    function _checkAccount(address account) internal view {
        require(account != address(0), "CV:ZA");
        require(!blocklist.isBlocked(account), "CV:BLK");
        if (whitelistRequired) require(whitelist.isWhitelisted(account), "CV:WL");
    }

    function _recomputedTotalAssetsFromOraclePrices() internal view returns (uint256 totalAssetsValue) {
        totalAssetsValue = FixedPoint.usdcToWad(usdc.balanceOf(address(this)));
        uint256 count = _stockTokens.length;
        for (uint256 i; i < count; ++i) {
            address token = _stockTokens[i];
            if (token == address(usdc)) continue;
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) continue;
            uint256 price = navOracle.priceOf(token);
            require(price > 0, "CV:MP");
            totalAssetsValue += balance * price / _assetUnit(token);
        }
    }

    function _targetWeights() internal view returns (uint256[] memory weights) {
        weights = new uint256[](_stockTokens.length);
        for (uint256 i; i < _stockTokens.length; ++i) {
            weights[i] = targetWeightBps[_stockTokens[i]];
        }
    }

    function _validateSettlementNavRound(uint256 navRound) internal view {
        require(navRound != 0 && navRound <= navOracle.latestRound(), "CV:INR");
    }

    function _assetUnit(address token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= 36, "CV:DEC");
        return 10 ** uint256(decimals);
    }

    function _updateTotalAssetsForRound(uint256 round) internal returns (uint256 totalAssetsValue) {
        require(round != 0 && round <= navOracle.latestRound(), "CV:INR");
        totalAssetsValue = _recomputedTotalAssetsFromOraclePrices();
        latestTotalAssetsValue = totalAssetsValue;
        totalAssetsByRound[round] = totalAssetsValue;
        emit TotalAssetsUpdated(round, totalAssetsValue);
    }

    function _totalAssetsForRound(uint256 round) internal view returns (uint256 totalAssetsValue) {
        totalAssetsValue = totalAssetsByRound[round];
        require(totalAssetsValue > 0 || totalSupply() == 0, "CV:ZN");
    }

    /// User's share = Invested Amount / Net Value per Share
    // = Invested Amount / (totalAssetsValue / totalSupply)
    // = Invested Amount * totalSupply / totalAssetsValue
    function _previewDeposit(uint256 assets18, uint256 totalAssetsValue_, uint256 supply) internal pure returns (uint256) {
        if (supply == 0 || totalAssetsValue_ == 0) return assets18;
        return assets18 * supply / totalAssetsValue_;
    }

}
