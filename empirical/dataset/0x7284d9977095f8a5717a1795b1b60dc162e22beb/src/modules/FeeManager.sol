// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CoreAccess } from "../base/CoreAccess.sol";
import { IFeeManager } from "../interfaces/IFeeManager.sol";
import { IShareToken } from "../interfaces/IShareToken.sol";
import { FixedPoint } from "../libraries/FixedPoint.sol";
import { Roles } from "../libraries/Roles.sol";

/// @title FeeManager
/// @notice Management fee/dividend fee module; currently implements lazy loading of management fees based on time difference and clears the accounts when crystallization occurs.
contract FeeManager is CoreAccess, IFeeManager {
    uint256 public constant INITIAL_SHARE_PRICE = 1e18;
    IShareToken public shareToken;
    uint256 public annualManagementFeeBps;
    uint256 public performanceFeeBps;
    uint256 public hurdleBps;
    uint256 public highWaterMark;
    uint256 public lastPerformanceSettleTimestamp;
    uint256 public performanceSettleInterval;
    uint256 public unclaimedManagementFeeShares;
    uint256 public claimedManagementFeeShares;
    uint256 public unclaimedPerformanceFeeShares;
    uint256 public claimedPerformanceFeeShares;
    uint256 public lastAccrualTimestamp;
    bool private _feeManagerInitialized;

    event AccrualStarted(uint256 indexed timestamp);
    event ManagementFeeAccrued(uint256 indexed fromTimestamp, uint256 indexed toTimestamp, uint256 shares);
    event ManagementFeeClaimed(address indexed recipient, uint256 shares);
    event PerformanceFeeClaimed(address indexed recipient, uint256 shares);
    event PerformanceFeeSettled(
        uint256 shares,
        uint256 currentSharePrice,
        uint256 threshold,
        uint256 newHighWaterMark
    );
    event FeeConfigSet(uint256 annualManagementFeeBps, uint256 performanceFeeBps, uint256 hurdleBps);
    event PerformanceSettleIntervalSet(uint256 interval);

    constructor(
        address admin,
        address shareToken_,
        uint256 annualManagementFeeBps_,
        uint256 performanceFeeBps_,
        uint256 hurdleBps_,
        uint256 highWaterMark_
    ) CoreAccess(admin) {
        if (admin != address(0)) {
            _initializeFeeManager(
                shareToken_, annualManagementFeeBps_, performanceFeeBps_, hurdleBps_, highWaterMark_
            );
        }
    }

    function initialize(
        address admin,
        address shareToken_,
        uint256 annualManagementFeeBps_,
        uint256 performanceFeeBps_,
        uint256 hurdleBps_,
        uint256 highWaterMark_
    ) external {
        _initializeCoreAccess(admin);
        _initializeFeeManager(
            shareToken_, annualManagementFeeBps_, performanceFeeBps_, hurdleBps_, highWaterMark_
        );
    }

    function _initializeFeeManager(
        address shareToken_,
        uint256 annualManagementFeeBps_,
        uint256 performanceFeeBps_,
        uint256 hurdleBps_,
        uint256 highWaterMark_
    ) internal {
        require(!_feeManagerInitialized, "FeeManager: initialized");
        require(shareToken_ != address(0), "FeeManager: zero address");
        _feeManagerInitialized = true;
        shareToken = IShareToken(shareToken_);
        annualManagementFeeBps = annualManagementFeeBps_;
        performanceFeeBps = performanceFeeBps_;
        hurdleBps = hurdleBps_;
        highWaterMark = highWaterMark_;
    }

    function setFeeConfig(uint256 annualBps, uint256 performanceBps, uint256 hurdleBps_) external onlyAdmin {
        require(annualBps <= 2000 && performanceBps <= 5000, "FeeManager: fee too high");
        require(hurdleBps_ <= FixedPoint.BPS, "FeeManager: hurdle too high");
        annualManagementFeeBps = annualBps;
        performanceFeeBps = performanceBps;
        hurdleBps = hurdleBps_;
        emit FeeConfigSet(annualBps, performanceBps, hurdleBps_);
    }

    function setPerformanceSettleInterval(uint256 interval) external onlyAdmin {
        performanceSettleInterval = interval;
        emit PerformanceSettleIntervalSet(interval);
    }

    function startAccrual() external onlyRole(Roles.FEE_CONTROLLER) {
        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = block.timestamp;
            emit AccrualStarted(block.timestamp);
        }
    }

    function accrueManagementFee(uint256 totalAssetsValue, uint256 effectiveSupply)
        public
        onlyRole(Roles.FEE_CONTROLLER)
        returns (uint256 shares)
    {
        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = block.timestamp;
            emit AccrualStarted(block.timestamp);
            return 0;
        }
        uint256 fromTimestamp = lastAccrualTimestamp;
        uint256 elapsed = block.timestamp - fromTimestamp;
        lastAccrualTimestamp = block.timestamp;

        if (elapsed == 0 || totalAssetsValue == 0 || effectiveSupply == 0 || annualManagementFeeBps == 0) {
            emit ManagementFeeAccrued(fromTimestamp, block.timestamp, 0);
            return 0;
        }
        // Management fees are calculated as "Total Assets Value × Annualized Fee Rate × Elapsed Time as a Percentage of the Annual Total".
        // Example: totalAssetsValue = 10,000,000 USDC, Annualized Management Fee = 95 bps = 0.95%, elapsed = 1 day,
        // feeAssets = 10,000,000 * 0.95% * 1 / 365, representing the asset value for which management fees should be collected in 1 day.
        uint256 feeAssets = totalAssetsValue * annualManagementFeeBps * elapsed / FixedPoint.BPS / 365 days;
        shares = _feeSharesFromAssets(feeAssets, totalAssetsValue, effectiveSupply);
        unclaimedManagementFeeShares += shares;
        emit ManagementFeeAccrued(fromTimestamp, block.timestamp, shares);
    }

    function claimManagementFee() public onlyRole(Roles.CURATOR) returns (uint256 shares) {
        shares = unclaimedManagementFeeShares;
        unclaimedManagementFeeShares = 0;
        claimedManagementFeeShares += shares;
        if (shares > 0) shareToken.mint(msg.sender, shares);
        emit ManagementFeeClaimed(msg.sender, shares);
    }

    function claimPerformanceFee() public onlyRole(Roles.CURATOR) returns (uint256 shares) {
        shares = unclaimedPerformanceFeeShares;
        unclaimedPerformanceFeeShares = 0;
        claimedPerformanceFeeShares += shares;
        if (shares > 0) shareToken.mint(msg.sender, shares);
        emit PerformanceFeeClaimed(msg.sender, shares);
    }

    function claimAllFees() external onlyRole(Roles.CURATOR) returns (uint256 shares) {
        shares = unclaimedManagementFeeShares + unclaimedPerformanceFeeShares;
        if (unclaimedManagementFeeShares > 0) {
            claimedManagementFeeShares += unclaimedManagementFeeShares;
            emit ManagementFeeClaimed(msg.sender, unclaimedManagementFeeShares);
            unclaimedManagementFeeShares = 0;
        }
        if (unclaimedPerformanceFeeShares > 0) {
            claimedPerformanceFeeShares += unclaimedPerformanceFeeShares;
            emit PerformanceFeeClaimed(msg.sender, unclaimedPerformanceFeeShares);
            unclaimedPerformanceFeeShares = 0;
        }
        if (shares > 0) shareToken.mint(msg.sender, shares);
    }

    function previewPerformanceFee(uint256 totalAssetsValue, uint256 effectiveSupply)
        public
        view
        returns (uint256 currentSharePrice, uint256 threshold, uint256 feeShares)
    {
        if (totalAssetsValue == 0 || effectiveSupply == 0 || performanceFeeBps == 0) {
            return (0, _performanceThreshold(), 0);
        }
        currentSharePrice = _sharePrice(totalAssetsValue, effectiveSupply);
        threshold = _performanceThreshold();
        if (currentSharePrice <= threshold) return (currentSharePrice, threshold, 0);

        uint256 excessPerShare = currentSharePrice - threshold;
        uint256 totalExcessAssets = excessPerShare * effectiveSupply / 1e18;
        uint256 feeAssets = totalExcessAssets * performanceFeeBps / FixedPoint.BPS;
        feeShares = _feeSharesFromAssets(feeAssets, totalAssetsValue, effectiveSupply);
    }

    function settlePerformanceFee(uint256 totalAssetsValue, uint256 effectiveSupply)
        external
        onlyRole(Roles.FEE_CONTROLLER)
        returns (uint256 shares, uint256 newHighWaterMark)
    {
        if (lastPerformanceSettleTimestamp != 0 && performanceSettleInterval > 0) {
            require(
                block.timestamp >= lastPerformanceSettleTimestamp + performanceSettleInterval,
                "FeeManager: performance too soon"
            );
        }
        (uint256 currentSharePrice, uint256 threshold, uint256 feeShares) =
            previewPerformanceFee(totalAssetsValue, effectiveSupply);
        shares = feeShares;
        unclaimedPerformanceFeeShares += shares;

        if (currentSharePrice > highWaterMark) {
            highWaterMark = currentSharePrice;
        }
        newHighWaterMark = highWaterMark;

        if (shares > 0) {
            lastPerformanceSettleTimestamp = block.timestamp;
        }

        emit PerformanceFeeSettled(shares, currentSharePrice, threshold, newHighWaterMark);
    }

    function effectiveTotalSupply(uint256 totalSupply) external view returns (uint256) {
        return totalSupply + uncollectedFeeInShares();
    }

    function uncollectedFeeInShares() public view returns (uint256) {
        return unclaimedManagementFeeShares + unclaimedPerformanceFeeShares;
    }

    /// @dev max(highWaterMark, initialSharePrice × (1 + hurdleBps))。
    function _performanceThreshold() internal view returns (uint256 threshold) {
        uint256 hurdleSharePrice = INITIAL_SHARE_PRICE * (FixedPoint.BPS + hurdleBps) / FixedPoint.BPS;
        threshold = highWaterMark > hurdleSharePrice ? highWaterMark : hurdleSharePrice;
    }

    function _sharePrice(uint256 totalAssetsValue, uint256 effectiveSupply) internal pure returns (uint256) {
        return totalAssetsValue * 1e18 / effectiveSupply;
    }

    function _feeSharesFromAssets(uint256 feeAssets, uint256 totalAssetsValue, uint256 effectiveSupply)
        internal
        pure
        returns (uint256)
    {
        if (feeAssets == 0) return 0;
        require(feeAssets < totalAssetsValue, "FeeManager: fee exceeds assets");
        return feeAssets * effectiveSupply / (totalAssetsValue - feeAssets);
    }
}
