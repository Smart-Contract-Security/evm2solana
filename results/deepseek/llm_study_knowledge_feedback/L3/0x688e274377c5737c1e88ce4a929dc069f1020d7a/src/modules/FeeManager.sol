// SPDX-License-Identifier: MIT

// Solana builtins
import { AccountInfo } from 'solana';

// --- CoreAccess (inlined) ---
contract CoreAccess {
    address public admin;
    mapping(address => bool) private _roles;
    bool private _coreAccessInitialized;

    event RoleGranted(address indexed account, bytes32 role);
    event RoleRevoked(address indexed account, bytes32 role);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        require(tx.accounts.dataAccount.key == admin, "CoreAccess: caller is not admin");
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(_roles[tx.accounts.dataAccount.key] || tx.accounts.dataAccount.key == admin, "CoreAccess: missing role");
        _;
    }

    constructor(address admin_) {
        _initializeCoreAccess(admin_);
    }

    function _initializeCoreAccess(address admin_) internal {
        require(!_coreAccessInitialized, "CoreAccess: initialized");
        require(admin_ != address(0), "CoreAccess: zero admin");
        _coreAccessInitialized = true;
        admin = admin_;
        emit AdminTransferred(address(0), admin_);
    }

    function grantRole(address account, bytes32 role) external onlyAdmin {
        _roles[account] = true;
        emit RoleGranted(account, role);
    }

    function revokeRole(address account, bytes32 role) external onlyAdmin {
        _roles[account] = false;
        emit RoleRevoked(account, role);
    }

    function hasRole(address account, bytes32 role) external view returns (bool) {
        return _roles[account] || account == admin;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "CoreAccess: zero admin");
        address previousAdmin = admin;
        admin = newAdmin;
        emit AdminTransferred(previousAdmin, newAdmin);
    }
}

// --- IFeeManager (inlined) ---
interface IFeeManager {
    function setFeeConfig(
        uint64 annualBps,
        uint64 performanceBps,
        uint64 hurdleBps_,
        uint64 totalAssetsValue,
        uint64 effectiveSupply
    ) external returns (uint64 managementFeeShares);

    function setPerformanceSettleInterval(uint64 interval) external;
    function startAccrual() external;
    function accrueManagementFee(uint64 totalAssetsValue, uint64 effectiveSupply) external returns (uint64 shares);
    function claimManagementFee() external returns (uint64 shares);
    function claimPerformanceFee() external returns (uint64 shares);
    function claimAllFees() external returns (uint64 shares);
    function previewPerformanceFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        view
        returns (uint64 currentSharePrice, uint64 threshold, uint64 feeShares);
    function settlePerformanceFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        returns (uint64 shares, uint64 newHighWaterMark);
    function effectiveTotalSupply(uint64 totalSupply) external view returns (uint64);
    function uncollectedFeeInShares() external view returns (uint64);
}

// --- IShareToken (inlined) ---
interface IShareToken {
    function totalSupply() external view returns (uint64);
    function mint(address to, uint64 amount) external;
}

// --- FixedPoint (inlined) ---
library FixedPoint {
    uint64 public constant BPS = 10000;
}

// --- Roles (inlined) ---
library Roles {
    bytes32 public constant FEE_CONTROLLER = keccak256("FEE_CONTROLLER");
    bytes32 public constant CURATOR = keccak256("CURATOR");
}

// --- FeeManager ---
@program_id("FeeManager111111111111111111111111111111111")
contract FeeManager is CoreAccess {
    uint64 public constant INITIAL_SHARE_PRICE = 1e18;
    address public shareToken;
    uint64 public annualManagementFeeBps;
    uint64 public performanceFeeBps;
    uint64 public hurdleBps;
    uint64 public highWaterMark;
    uint64 public lastPerformanceSettleTimestamp;
    uint64 public performanceSettleInterval;
    uint64 public unclaimedManagementFeeShares;
    uint64 public claimedManagementFeeShares;
    uint64 public unclaimedPerformanceFeeShares;
    uint64 public claimedPerformanceFeeShares;
    uint64 public lastAccrualTimestamp;
    bool private _feeManagerInitialized;

    event AccrualStarted(uint64 indexed timestamp);
    event ManagementFeeAccrued(uint64 indexed fromTimestamp, uint64 indexed toTimestamp, uint64 shares);
    event ManagementFeeClaimed(address indexed recipient, uint64 shares);
    event PerformanceFeeClaimed(address indexed recipient, uint64 shares);
    event PerformanceFeeSettled(
        uint64 shares,
        uint64 currentSharePrice,
        uint64 threshold,
        uint64 newHighWaterMark
    );
    event FeeConfigSet(uint64 annualManagementFeeBps, uint64 performanceFeeBps, uint64 hurdleBps);
    event PerformanceSettleIntervalSet(uint64 interval);

    @payer(payer)
    @space(1024)
    @seed("FeeManager")
    constructor(
        address admin,
        address shareToken_,
        uint64 annualManagementFeeBps_,
        uint64 performanceFeeBps_,
        uint64 hurdleBps_,
        uint64 highWaterMark_
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
        uint64 annualManagementFeeBps_,
        uint64 performanceFeeBps_,
        uint64 hurdleBps_,
        uint64 highWaterMark_
    ) external {
        _initializeCoreAccess(admin);
        _initializeFeeManager(
            shareToken_, annualManagementFeeBps_, performanceFeeBps_, hurdleBps_, highWaterMark_
        );
    }

    function _initializeFeeManager(
        address shareToken_,
        uint64 annualManagementFeeBps_,
        uint64 performanceFeeBps_,
        uint64 hurdleBps_,
        uint64 highWaterMark_
    ) internal {
        require(!_feeManagerInitialized, "FeeManager: initialized");
        require(shareToken_ != address(0), "FeeManager: zero address");
        _feeManagerInitialized = true;
        shareToken = shareToken_;
        annualManagementFeeBps = annualManagementFeeBps_;
        performanceFeeBps = performanceFeeBps_;
        hurdleBps = hurdleBps_;
        highWaterMark = highWaterMark_;
    }

    function setFeeConfig(
        uint64 annualBps,
        uint64 performanceBps,
        uint64 hurdleBps_,
        uint64 totalAssetsValue,
        uint64 effectiveSupply
    ) external onlyAdmin returns (uint64 managementFeeShares) {
        require(annualBps <= 2000 && performanceBps <= 5000, "FeeManager: fee too high");
        require(hurdleBps_ <= FixedPoint.BPS, "FeeManager: hurdle too high");
        if (effectiveSupply > 0) {
            managementFeeShares = _accrueManagementFee(totalAssetsValue, effectiveSupply);
        }
        annualManagementFeeBps = annualBps;
        performanceFeeBps = performanceBps;
        hurdleBps = hurdleBps_;
        emit FeeConfigSet(annualBps, performanceBps, hurdleBps_);
    }

    function setPerformanceSettleInterval(uint64 interval) external onlyAdmin {
        performanceSettleInterval = interval;
        emit PerformanceSettleIntervalSet(interval);
    }

    function startAccrual() external onlyRole(Roles.FEE_CONTROLLER) {
        if (lastAccrualTimestamp == 0 && _shareTokenTotalSupply() > 0) {
            lastAccrualTimestamp = uint64(block.timestamp);
            emit AccrualStarted(uint64(block.timestamp));
        }
    }

    function accrueManagementFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        onlyRole(Roles.FEE_CONTROLLER)
        returns (uint64 shares)
    {
        shares = _accrueManagementFee(totalAssetsValue, effectiveSupply);
    }

    function _accrueManagementFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        internal
        returns (uint64 shares)
    {
        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = uint64(block.timestamp);
            emit AccrualStarted(uint64(block.timestamp));
            return 0;
        }
        uint64 fromTimestamp = lastAccrualTimestamp;
        uint64 elapsed = uint64(block.timestamp) - fromTimestamp;
        lastAccrualTimestamp = uint64(block.timestamp);

        if (elapsed == 0 || totalAssetsValue == 0 || effectiveSupply == 0 || annualManagementFeeBps == 0) {
            emit ManagementFeeAccrued(fromTimestamp, uint64(block.timestamp), 0);
            return 0;
        }
        uint64 feeAssets = totalAssetsValue * annualManagementFeeBps * elapsed / FixedPoint.BPS / 365 days;
        shares = _feeSharesFromAssets(feeAssets, totalAssetsValue, effectiveSupply);
        unclaimedManagementFeeShares += shares;
        emit ManagementFeeAccrued(fromTimestamp, uint64(block.timestamp), shares);
    }

    function claimManagementFee() external onlyRole(Roles.CURATOR) returns (uint64 shares) {
        shares = unclaimedManagementFeeShares;
        unclaimedManagementFeeShares = 0;
        claimedManagementFeeShares += shares;
        if (shares > 0) _shareTokenMint(tx.accounts.dataAccount.key, shares);
        emit ManagementFeeClaimed(tx.accounts.dataAccount.key, shares);
    }

    function claimPerformanceFee() external onlyRole(Roles.CURATOR) returns (uint64 shares) {
        shares = unclaimedPerformanceFeeShares;
        unclaimedPerformanceFeeShares = 0;
        claimedPerformanceFeeShares += shares;
        if (shares > 0) _shareTokenMint(tx.accounts.dataAccount.key, shares);
        emit PerformanceFeeClaimed(tx.accounts.dataAccount.key, shares);
    }

    function claimAllFees() external onlyRole(Roles.CURATOR) returns (uint64 shares) {
        shares = unclaimedManagementFeeShares + unclaimedPerformanceFeeShares;
        if (unclaimedManagementFeeShares > 0) {
            claimedManagementFeeShares += unclaimedManagementFeeShares;
            emit ManagementFeeClaimed(tx.accounts.dataAccount.key, unclaimedManagementFeeShares);
            unclaimedManagementFeeShares = 0;
        }
        if (unclaimedPerformanceFeeShares > 0) {
            claimedPerformanceFeeShares += unclaimedPerformanceFeeShares;
            emit PerformanceFeeClaimed(tx.accounts.dataAccount.key, unclaimedPerformanceFeeShares);
            unclaimedPerformanceFeeShares = 0;
        }
        if (shares > 0) _shareTokenMint(tx.accounts.dataAccount.key, shares);
    }

    function previewPerformanceFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        view
        returns (uint64 currentSharePrice, uint64 threshold, uint64 feeShares)
    {
        if (totalAssetsValue == 0 || effectiveSupply == 0 || performanceFeeBps == 0) {
            return (0, _performanceThreshold(), 0);
        }
        currentSharePrice = _sharePrice(totalAssetsValue, effectiveSupply);
        threshold = _performanceThreshold();
        if (currentSharePrice <= threshold) return (currentSharePrice, threshold, 0);

        uint64 excessPerShare = currentSharePrice - threshold;
        uint64 totalExcessAssets = excessPerShare * effectiveSupply / 1e18;
        uint64 feeAssets = totalExcessAssets * performanceFeeBps / FixedPoint.BPS;
        feeShares = _feeSharesFromAssets(feeAssets, totalAssetsValue, effectiveSupply);
    }

    function settlePerformanceFee(uint64 totalAssetsValue, uint64 effectiveSupply)
        external
        onlyRole(Roles.FEE_CONTROLLER)
        returns (uint64 shares, uint64 newHighWaterMark)
    {
        if (lastPerformanceSettleTimestamp != 0 && performanceSettleInterval > 0) {
            require(
                uint64(block.timestamp) >= lastPerformanceSettleTimestamp + performanceSettleInterval,
                "FeeManager: performance too soon"
            );
        }
        (uint64 currentSharePrice, uint64 threshold, uint64 feeShares) =
            previewPerformanceFee(totalAssetsValue, effectiveSupply);
        shares = feeShares;
        unclaimedPerformanceFeeShares += shares;

        if (shares > 0) {
            uint64 postFeeSharePrice = _sharePrice(totalAssetsValue, effectiveSupply + shares);
            if (postFeeSharePrice > highWaterMark) {
                highWaterMark = postFeeSharePrice;
            }
            lastPerformanceSettleTimestamp = uint64(block.timestamp);
        }
        newHighWaterMark = highWaterMark;

        emit PerformanceFeeSettled(shares, currentSharePrice, threshold, newHighWaterMark);
    }

    function effectiveTotalSupply(uint64 totalSupply) external view returns (uint64) {
        return totalSupply + uncollectedFeeInShares();
    }

    function uncollectedFeeInShares() public view returns (uint64) {
        return unclaimedManagementFeeShares + unclaimedPerformanceFeeShares;
    }

    function _performanceThreshold() internal view returns (uint64 threshold) {
        uint64 hurdleSharePrice = INITIAL_SHARE_PRICE * (FixedPoint.BPS + hurdleBps) / FixedPoint.BPS;
        threshold = highWaterMark > hurdleSharePrice ? highWaterMark : hurdleSharePrice;
    }

    function _sharePrice(uint64 totalAssetsValue, uint64 effectiveSupply) internal pure returns (uint64) {
        return totalAssetsValue * 1e18 / effectiveSupply;
    }

    function _feeSharesFromAssets(uint64 feeAssets, uint64 totalAssetsValue, uint64 effectiveSupply)
        internal
        pure
        returns (uint64)
    {
        if (feeAssets == 0) return 0;
        require(feeAssets < totalAssetsValue, "FeeManager: fee exceeds assets");
        return feeAssets * effectiveSupply / (totalAssetsValue - feeAssets);
    }

    function _shareTokenTotalSupply() internal view returns (uint64) {
        (bool success, bytes memory data) = shareToken.call{accounts: []}(abi.encodeWithSignature("totalSupply()"));
        require(success, "FeeManager: totalSupply call failed");
        return abi.decode(data, (uint64));
    }

    function _shareTokenMint(address to, uint64 amount) internal {
        (bool success, ) = shareToken.call{accounts: []}(abi.encodeWithSignature("mint(address,uint64)", to, amount));
        require(success, "FeeManager: mint call failed");
    }
}