// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IBoardwalkToken} from "../interfaces/IBoardwalkToken.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {IVestingStream} from "../interfaces/IVestingStream.sol";
import {ILPStaking} from "../interfaces/ILPStaking.sol";

/// @title LaunchFactory
/// @notice Singleton that deploys per-launch clones, burns BMX from issuers, and owns global config.
contract LaunchFactory {
    using SafeERC20 for IERC20;

    enum LaunchPath {
        EXPRESS,
        ADVANCED
    }

    struct LaunchConfig {
        string name;
        string ticker;
        string category;
        string description;
        LaunchPath path;
        uint256 presalePercent;
        address[] vestingRecipients;
        uint256[] vestingPercents;
        string[] vestingLabels;
        address referrer;
        address[] issuerFeeRecipients;
        uint256[] issuerFeeSplits;
        string[] issuerFeeLabels;
    }

    struct LaunchInfo {
        address token;
        address feeDistributor;
        address presaleManager;
        address vestingStream;
        address lpStaking;
        address issuer;
        LaunchPath path;
        uint32 createdAt;
    }

    struct FeeBpsDefaults {
        uint256 issuer;
        uint256 boardwalk;
        uint256 incentive;
        uint256 referrer;
        uint256 total;
    }

    uint256 private constant MAX_BMX_BURN = 200e18;
    uint256 private constant MAX_FEE_RECIPIENTS = 4;
    uint256 private constant MAX_VESTING_RECIPIENTS = 5;
    uint256 private constant MIN_ADVANCED_DURATION = 2 days;
    uint256 private constant MAX_ADVANCED_DURATION = 14 days;

    uint256 private constant PRESALE_RANGE_FLOOR = 500;
    uint256 private constant PRESALE_RANGE_CEILING = 5000;
    uint256 private constant PRESALE_STEP = 500;

    uint256 private constant MIN_ISSUER_BPS = 10;
    uint256 private constant MAX_ISSUER_BPS = 80;
    uint256 private constant MIN_BOARDWALK_BPS = 10;
    uint256 private constant MAX_BOARDWALK_BPS = 50;
    uint256 private constant MAX_INCENTIVE_BPS = 50;
    uint256 private constant MAX_REFERRER_BPS = 10;
    uint256 private constant MAX_INTEGRATOR_BPS = 50;

    uint256 private constant MIN_ANTI_WHALE_TAX_BPS = 500;
    uint256 private constant MAX_ANTI_WHALE_TAX_BPS = 4000;
    uint256 private constant MIN_ANTI_WHALE_DURATION = 5 minutes;
    uint256 private constant MAX_ANTI_WHALE_DURATION = 90 minutes;

    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant MAX_DISCOUNT_BPS = 10000;

    address public constant DEAD_ADDRESS = address(0);

    bytes32 public constant ACTION_SET_BMX_BURN = keccak256("SET_BMX_BURN");
    bytes32 public constant ACTION_SET_GRADUATION_EXPRESS = keccak256("SET_GRADUATION_EXPRESS");
    bytes32 public constant ACTION_SET_GRADUATION_ADVANCED = keccak256("SET_GRADUATION_ADVANCED");
    bytes32 public constant ACTION_SET_EXPRESS_DURATION = keccak256("SET_EXPRESS_DURATION");
    bytes32 public constant ACTION_SET_ADVANCED_DURATION = keccak256("SET_ADVANCED_DURATION");
    bytes32 public constant ACTION_SET_FEE_DEFAULTS = keccak256("SET_FEE_DEFAULTS");
    bytes32 public constant ACTION_SET_PRESALE_RANGE = keccak256("SET_PRESALE_RANGE");
    bytes32 public constant ACTION_SET_FEE_COLLECTOR = keccak256("SET_FEE_COLLECTOR");
    bytes32 public constant ACTION_SET_MEMBER_LAUNCH_DISCOUNT = keccak256("SET_MEMBER_LAUNCH_DISCOUNT");
    bytes32 public constant ACTION_SET_ANTI_WHALE = keccak256("SET_ANTI_WHALE");
    bytes32 public constant ACTION_SET_NFT_COLLECTION = keccak256("SET_NFT_COLLECTION");

    address public immutable TOKEN_IMPL;
    address public immutable FEE_DISTRIBUTOR_IMPL;
    address public immutable PRESALE_IMPL;
    address public immutable VESTING_IMPL;
    address public immutable LP_STAKING_IMPL;
    address public immutable BMX;
    address public immutable RAISE_TOKEN;
    address public immutable BOARDWALK_ROUTER;
    address public immutable BOARDWALK_DEX_FACTORY;
    address public immutable BOARDWALK_LP_MANAGER;
    address public immutable INTEGRATOR_COLLECTOR;
    uint256 public immutable INTEGRATOR_BPS;

    address public boardwalkFeeCollector;

    uint256 public bmxBurnAmount;

    uint256 public expressDuration;
    uint256 public advancedDuration;

    uint256 public minPresalePercent = 2500;
    uint256 public maxPresalePercent = 5000;

    uint256 public graduationExpress;
    uint256 public graduationAdvanced;

    uint256 public memberLaunchDiscountBps;

    uint256 public antiWhaleTaxBps;
    uint256 public antiWhaleDuration;

    FeeBpsDefaults private _feeBpsDefaults;

    mapping(address => LaunchInfo) public launches;
    address[] public allLaunches;

    address private _owner;
    address private _nftCollection;

    event LaunchCreated(
        address indexed token,
        address indexed issuer,
        string name,
        string ticker,
        string category,
        string description,
        LaunchPath path,
        string[] issuerFeeLabels,
        string[] vestingLabels
    );
    event BmxBurnAmountChanged(uint256 oldAmount, uint256 newAmount);
    event GraduationThresholdChanged(LaunchPath path, uint256 oldThreshold, uint256 newThreshold);
    event PresaleDurationChanged(LaunchPath path, uint256 oldDuration, uint256 newDuration);
    event FeeDefaultsChanged(uint256 issuer, uint256 boardwalk, uint256 incentive, uint256 referrer);
    event PresaleRangeChanged(uint256 oldMin, uint256 oldMax, uint256 newMin, uint256 newMax);
    event FeeCollectorChanged(address oldCollector, address newCollector);
    event MemberLaunchDiscountChanged(uint256 oldDiscount, uint256 newDiscount);
    event AntiWhaleConfigChanged(uint256 oldTaxBps, uint256 oldDuration, uint256 newTaxBps, uint256 newDuration);

    struct DeployParams {
        address tokenImpl;
        address feeDistributorImpl;
        address presaleImpl;
        address vestingImpl;
        address lpStakingImpl;
        address bmx;
        address raiseToken;
        address boardwalkRouter;
        address boardwalkDexFactory;
        address boardwalkLpManager;
        address boardwalkFeeCollector;
        address integratorCollector;
        uint256 integratorBps;
        uint256 bmxBurnAmount;
        uint256 graduationExpress;
        uint256 graduationAdvanced;
        uint256 expressDuration;
        uint256 advancedDuration;
        uint256 antiWhaleTaxBps;
        uint256 antiWhaleDuration;
        FeeBpsDefaults feeBps;
        address nftCollection;
        uint256 memberLaunchDiscountBps;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    constructor(
        address _ownerAddr,
        DeployParams memory p
    ) {
        _owner = _ownerAddr;
        TOKEN_IMPL = p.tokenImpl;
        FEE_DISTRIBUTOR_IMPL = p.feeDistributorImpl;
        PRESALE_IMPL = p.presaleImpl;
        VESTING_IMPL = p.vestingImpl;
        LP_STAKING_IMPL = p.lpStakingImpl;
        BMX = p.bmx;
        RAISE_TOKEN = p.raiseToken;
        BOARDWALK_ROUTER = p.boardwalkRouter;
        BOARDWALK_DEX_FACTORY = p.boardwalkDexFactory;
        BOARDWALK_LP_MANAGER = p.boardwalkLpManager;
        boardwalkFeeCollector = p.boardwalkFeeCollector;
        if (p.bmxBurnAmount > MAX_BMX_BURN) revert("BmxBurnOutOfRange");
        bmxBurnAmount = p.bmxBurnAmount;
        if (p.graduationExpress == 0 || p.graduationAdvanced == 0) revert("ZeroGraduation");
        graduationExpress = p.graduationExpress;
        graduationAdvanced = p.graduationAdvanced;
        if (p.expressDuration == 0) revert("InvalidDuration");
        if (p.advancedDuration < MIN_ADVANCED_DURATION || p.advancedDuration > MAX_ADVANCED_DURATION) {
            revert("InvalidDuration");
        }
        expressDuration = p.expressDuration;
        advancedDuration = p.advancedDuration;

        if (p.integratorBps > MAX_INTEGRATOR_BPS) revert("InvalidFeeDefaults");
        if ((p.integratorBps > 0) != (p.integratorCollector != address(0))) revert("IntegratorCollectorMismatch");
        INTEGRATOR_BPS = p.integratorBps;
        INTEGRATOR_COLLECTOR = p.integratorCollector;

        _validateFeeDefaults(p.feeBps);
        _feeBpsDefaults = p.feeBps;

        _validateAntiWhale(p.antiWhaleTaxBps, p.antiWhaleDuration);
        antiWhaleTaxBps = p.antiWhaleTaxBps;
        antiWhaleDuration = p.antiWhaleDuration;

        _validateDistinctRoles(p.integratorCollector, p.boardwalkFeeCollector, p.boardwalkLpManager);

        if (p.memberLaunchDiscountBps > MAX_DISCOUNT_BPS) revert("MemberDiscountOutOfRange");
        memberLaunchDiscountBps = p.memberLaunchDiscountBps;
        _setNftCollection(p.nftCollection);
    }

    /// @notice Returns the current fee BPS defaults applied to future launches.
    function currentFeeBps()
        external
        view
        returns (
            uint256 issuer,
            uint256 boardwalk,
            uint256 incentive,
            uint256 referrer,
            uint256 integratorBps,
            uint256 total
        )
    {
        FeeBpsDefaults memory d = _feeBpsDefaults;
        return (d.issuer, d.boardwalk, d.incentive, d.referrer, INTEGRATOR_BPS, d.total);
    }

    function launchCount() external view returns (uint256) {
        return allLaunches.length;
    }

    function isLaunchToken(
        address token
    ) external view returns (bool) {
        return launches[token].token != address(0);
    }

    /// @notice Deploys and initializes a new launch. Burns BMX from the caller (minus any NFT discount).
    function createLaunch(
        LaunchConfig calldata config
    ) external returns (address tokenAddr) {
        _validateConfig(config);

        uint256 effectiveBurn = _effectiveCost(bmxBurnAmount, memberLaunchDiscountBps, msg.sender);
        if (effectiveBurn > 0) {
            IERC20(BMX).safeTransferFrom(msg.sender, DEAD_ADDRESS, effectiveBurn);
        }

        tokenAddr = Clones.clone(TOKEN_IMPL);
        address feeDistributorAddr = Clones.clone(FEE_DISTRIBUTOR_IMPL);
        address presaleAddr = Clones.clone(PRESALE_IMPL);
        address lpStakingAddr = Clones.clone(LP_STAKING_IMPL);

        address vestingAddr;
        if (config.vestingRecipients.length > 0) {
            vestingAddr = Clones.clone(VESTING_IMPL);
        }

        // LPStaking and VestingStream are initialized later by PresaleManager during seedLiquidity().
        ILPStaking(lpStakingAddr).setInitializer(presaleAddr);
        if (vestingAddr != address(0)) {
            IVestingStream(vestingAddr).setInitializer(presaleAddr, msg.sender);
        }

        FeeBpsDefaults memory feeBps = _feeBpsDefaults;

        IBoardwalkToken(tokenAddr)
            .initialize(
                config.name,
                config.ticker,
                feeBps.total,
                antiWhaleTaxBps,
                antiWhaleDuration,
                feeDistributorAddr,
                presaleAddr,
                _buildExemptList(presaleAddr, lpStakingAddr, vestingAddr)
            );

        // Referrer share is carved out of boardwalk; only applied when a referrer is set.
        uint256 effectiveReferrerBps = config.referrer != address(0) ? feeBps.referrer : 0;
        uint256 effectiveBoardwalkBps = feeBps.boardwalk - effectiveReferrerBps;

        IFeeDistributor(feeDistributorAddr)
            .initialize(
                IFeeDistributor.InitParams({
                    token: tokenAddr,
                    lpStaking: lpStakingAddr,
                    feeCollector: boardwalkFeeCollector,
                    integratorCollector: INTEGRATOR_COLLECTOR,
                    router: BOARDWALK_ROUTER,
                    raiseToken: RAISE_TOKEN,
                    issuerRecipients: config.issuerFeeRecipients,
                    issuerSplits: config.issuerFeeSplits,
                    referrer: config.referrer,
                    issuerBps: feeBps.issuer,
                    boardwalkBps: effectiveBoardwalkBps,
                    lpIncentiveBps: feeBps.incentive,
                    referrerBps: effectiveReferrerBps,
                    integratorBps: INTEGRATOR_BPS
                })
            );

        uint256 presaleDuration;
        uint256 presalePercent;
        uint256 graduationThreshold;
        bool hasDelay;

        if (config.path == LaunchPath.EXPRESS) {
            presaleDuration = expressDuration;
            presalePercent = 5000;
            graduationThreshold = graduationExpress;
            hasDelay = false;
        } else {
            presaleDuration = advancedDuration;
            presalePercent = config.presalePercent;
            graduationThreshold = graduationAdvanced;
            hasDelay = true;
        }

        // IPresaleManager interface removed; use low-level call or inline the initialization.
        // Since IPresaleManager is not available, we assume the presale contract has an initialize function.
        // We use a low-level call to avoid the missing interface.
        (bool success, ) = presaleAddr.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address,uint256,uint256,uint256,bool)",
                tokenAddr,
                feeDistributorAddr,
                vestingAddr,
                lpStakingAddr,
                BOARDWALK_ROUTER,
                RAISE_TOKEN,
                BOARDWALK_DEX_FACTORY,
                presaleDuration,
                presalePercent,
                graduationThreshold,
                hasDelay
            )
        );
        require(success, "Presale init failed");

        if (config.vestingRecipients.length > 0) {
            _setVestingConfig(config, presaleAddr, presalePercent);
        }

        LaunchInfo memory info = LaunchInfo({
            token: tokenAddr,
            feeDistributor: feeDistributorAddr,
            presaleManager: presaleAddr,
            vestingStream: vestingAddr,
            lpStaking: lpStakingAddr,
            issuer: msg.sender,
            path: config.path,
            createdAt: SafeCast.toUint32(block.timestamp)
        });

        launches[tokenAddr] = info;
        allLaunches.push(tokenAddr);

        emit LaunchCreated(
            tokenAddr,
            msg.sender,
            config.name,
            config.ticker,
            config.category,
            config.description,
            config.path,
            config.issuerFeeLabels,
            config.vestingLabels
        );
    }

    /// @dev Splits issuer vesting tokens across recipients using BPS math. Must match
    ///      the allocation computed by PresaleManager.seedLiquidity() for the same presalePercent.
    function _setVestingConfig(
        LaunchConfig calldata config,
        address presaleAddr,
        uint256 presalePercent
    ) internal {
        (,,, uint256 issuerVestingTokens) = _computeAllocation(10_000_000_000e18, presalePercent);
        uint256[] memory vestingAmounts = _splitByBps(issuerVestingTokens, config.vestingPercents);
        // IPresaleManager interface removed; use low-level call
        (bool success, ) = presaleAddr.call(
            abi.encodeWithSignature(
                "setVestingConfig(address[],uint256[])",
                config.vestingRecipients,
                vestingAmounts
            )
        );
        require(success, "setVestingConfig failed");
    }

    /// @dev Per-clone exempt set. FeeDistributor itself is added by `BoardwalkToken.initialize`.
    function _buildExemptList(
        address presaleAddr,
        address lpStakingAddr,
        address vestingAddr
    ) internal view returns (address[] memory exemptAddresses) {
        bool hasIntegrator = INTEGRATOR_BPS > 0;

        uint256 count = 4;
        if (vestingAddr != address(0)) count++;
        if (hasIntegrator) count++;

        exemptAddresses = new address[](count);
        exemptAddresses[0] = presaleAddr;
        exemptAddresses[1] = lpStakingAddr;
        exemptAddresses[2] = BOARDWALK_LP_MANAGER;
        exemptAddresses[3] = boardwalkFeeCollector;
        uint256 idx = 4;
        if (vestingAddr != address(0)) exemptAddresses[idx++] = vestingAddr;
        if (hasIntegrator) exemptAddresses[idx++] = INTEGRATOR_COLLECTOR;
    }

    function _validateConfig(
        LaunchConfig calldata config
    ) internal view {
        if (
            config.issuerFeeRecipients.length != config.issuerFeeSplits.length
                || config.issuerFeeRecipients.length != config.issuerFeeLabels.length
        ) revert("ArrayLengthMismatch");
        if (
            config.vestingRecipients.length != config.vestingPercents.length
                || config.vestingRecipients.length != config.vestingLabels.length
        ) revert("ArrayLengthMismatch");

        uint256 feeRecipientCount = config.issuerFeeRecipients.length;
        if (feeRecipientCount == 0 || feeRecipientCount > MAX_FEE_RECIPIENTS) {
            revert("TooManyRecipients");
        }

        uint256 feeSplitSum;
        for (uint256 i = 0; i < feeRecipientCount;) {
            if (config.issuerFeeRecipients[i] == address(0)) revert("ZeroAddress");
            feeSplitSum += config.issuerFeeSplits[i];
            unchecked {
                ++i;
            }
        }
        if (feeSplitSum != BPS_DENOMINATOR) revert("InvalidSplitsSum");

        if (config.path == LaunchPath.EXPRESS) {
            if (config.referrer != address(0)) revert("ReferrerNotAllowedOnExpressPath");
            if (config.vestingRecipients.length > 0) revert("VestingNotAllowedOnExpressPath");
            if (feeRecipientCount != 1) revert("ExpressRequiresOneFeeRecipient");
        } else {
            uint256 pp = config.presalePercent;
            if (pp < minPresalePercent || pp > maxPresalePercent) {
                revert("InvalidPresalePercent");
            }
            if (pp % PRESALE_STEP != 0) revert("PresalePercentNotDivisibleBy5");

            // Advanced with <50% presale must define vesting; otherwise the issuer bucket isn't minted.
            if (pp < 5000 && config.vestingRecipients.length == 0) {
                revert("IssuerVestingRecipientsRequired");
            }
            if (pp == 5000 && config.vestingRecipients.length > 0) {
                revert("VestingNotAllowedAtFullPresale");
            }

            if (config.vestingRecipients.length > MAX_VESTING_RECIPIENTS) {
                revert("TooManyRecipients");
            }
            if (config.vestingRecipients.length > 0) {
                uint256 vestingSum;
                for (uint256 i = 0; i < config.vestingPercents.length;) {
                    vestingSum += config.vestingPercents[i];
                    unchecked {
                        ++i;
                    }
                }
                if (vestingSum != BPS_DENOMINATOR) revert("InvalidSplitsSum");
            }
        }
    }

    function _authAdmin(
        bytes32
    ) internal view {
        _checkOwner();
    }

    function executeSetBmxBurn(
        uint256 _amount
    ) external {
        _execute(ACTION_SET_BMX_BURN, keccak256(abi.encode(_amount)));
        if (_amount > MAX_BMX_BURN) revert("BmxBurnOutOfRange");
        emit BmxBurnAmountChanged(bmxBurnAmount, _amount);
        bmxBurnAmount = _amount;
    }

    function executeSetGraduation(
        LaunchPath path,
        uint256 _threshold
    ) external {
        bytes32 action = path == LaunchPath.EXPRESS ? ACTION_SET_GRADUATION_EXPRESS : ACTION_SET_GRADUATION_ADVANCED;
        _execute(action, keccak256(abi.encode(_threshold)));
        if (_threshold == 0) revert("ZeroGraduation");
        if (path == LaunchPath.EXPRESS) {
            emit GraduationThresholdChanged(LaunchPath.EXPRESS, graduationExpress, _threshold);
            graduationExpress = _threshold;
        } else {
            emit GraduationThresholdChanged(LaunchPath.ADVANCED, graduationAdvanced, _threshold);
            graduationAdvanced = _threshold;
        }
    }

    function executeSetDuration(
        LaunchPath path,
        uint256 _duration
    ) external {
        bytes32 action = path == LaunchPath.EXPRESS ? ACTION_SET_EXPRESS_DURATION : ACTION_SET_ADVANCED_DURATION;
        _execute(action, keccak256(abi.encode(_duration)));
        if (path == LaunchPath.EXPRESS) {
            if (_duration == 0) revert("InvalidDuration");
            emit PresaleDurationChanged(LaunchPath.EXPRESS, expressDuration, _duration);
            expressDuration = _duration;
        } else {
            if (_duration < MIN_ADVANCED_DURATION || _duration > MAX_ADVANCED_DURATION) revert("InvalidDuration");
            emit PresaleDurationChanged(LaunchPath.ADVANCED, advancedDuration, _duration);
            advancedDuration = _duration;
        }
    }

    function executeSetFeeDefaults(
        FeeBpsDefaults calldata _feeBps
    ) external {
        _execute(ACTION_SET_FEE_DEFAULTS, keccak256(abi.encode(_feeBps)));
        _validateFeeDefaults(_feeBps);
        _feeBpsDefaults = _feeBps;
        emit FeeDefaultsChanged(_feeBps.issuer, _feeBps.boardwalk, _feeBps.incentive, _feeBps.referrer);
    }

    function executeSetPresaleRange(
        uint256 _min,
        uint256 _max
    ) external {
        _execute(ACTION_SET_PRESALE_RANGE, keccak256(abi.encode(_min, _max)));
        _validatePresaleRange(_min, _max);
        emit PresaleRangeChanged(minPresalePercent, maxPresalePercent, _min, _max);
        minPresalePercent = _min;
        maxPresalePercent = _max;
    }

    function executeSetFeeCollector(
        address _collector
    ) external {
        _execute(ACTION_SET_FEE_COLLECTOR, keccak256(abi.encode(_collector)));
        if (_collector == address(0)) revert("ZeroAddress");
        if (_collector == INTEGRATOR_COLLECTOR || _collector == BOARDWALK_LP_MANAGER) {
            revert("DuplicateRoleAddress");
        }
        emit FeeCollectorChanged(boardwalkFeeCollector, _collector);
        boardwalkFeeCollector = _collector;
    }

    function executeSetNftCollection(
        address _nft
    ) external {
        _execute(ACTION_SET_NFT_COLLECTION, keccak256(abi.encode(_nft)));
        _setNftCollection(_nft);
    }

    function executeSetMemberLaunchDiscount(
        uint256 _bps
    ) external {
        _execute(ACTION_SET_MEMBER_LAUNCH_DISCOUNT, keccak256(abi.encode(_bps)));
        if (_bps > MAX_DISCOUNT_BPS) revert("MemberDiscountOutOfRange");
        emit MemberLaunchDiscountChanged(memberLaunchDiscountBps, _bps);
        memberLaunchDiscountBps = _bps;
    }

    function executeSetAntiWhale(
        uint256 _taxBps,
        uint256 _duration
    ) external {
        _execute(ACTION_SET_ANTI_WHALE, keccak256(abi.encode(_taxBps, _duration)));
        _validateAntiWhale(_taxBps, _duration);
        emit AntiWhaleConfigChanged(antiWhaleTaxBps, antiWhaleDuration, _taxBps, _duration);
        antiWhaleTaxBps = _taxBps;
        antiWhaleDuration = _duration;
    }

    /// @dev Total must equal issuer + boardwalk + incentive + integrator.
    ///      Referrer is carved from boardwalk.
    function _validateFeeDefaults(
        FeeBpsDefaults memory d
    ) internal view {
        if (d.total != d.issuer + d.boardwalk + d.incentive + INTEGRATOR_BPS) revert("InvalidFeeDefaults");
        if (d.issuer < MIN_ISSUER_BPS || d.issuer > MAX_ISSUER_BPS) revert("InvalidFeeDefaults");
        if (d.boardwalk < MIN_BOARDWALK_BPS || d.boardwalk > MAX_BOARDWALK_BPS) revert("InvalidFeeDefaults");
        if (d.incentive > MAX_INCENTIVE_BPS) revert("InvalidFeeDefaults");
        if (d.referrer > MAX_REFERRER_BPS) revert("InvalidFeeDefaults");
        if (d.referrer > d.boardwalk) revert("InvalidFeeDefaults");
    }

    function _validateAntiWhale(
        uint256 taxBps,
        uint256 duration
    ) internal pure {
        if (taxBps < MIN_ANTI_WHALE_TAX_BPS || taxBps > MAX_ANTI_WHALE_TAX_BPS) revert("InvalidAntiWhaleConfig");
        if (duration < MIN_ANTI_WHALE_DURATION || duration > MAX_ANTI_WHALE_DURATION) revert("InvalidAntiWhaleConfig");
    }

    function _validateDistinctRoles(
        address integratorCollectorAddr,
        address feeCollectorAddr,
        address lpManagerAddr
    ) internal pure {
        if (integratorCollectorAddr != address(0)) {
            if (integratorCollectorAddr == feeCollectorAddr || integratorCollectorAddr == lpManagerAddr) {
                revert("DuplicateRoleAddress");
            }
        }
        if (feeCollectorAddr == lpManagerAddr) revert("DuplicateRoleAddress");
    }

    function _validatePresaleRange(
        uint256 _min,
        uint256 _max
    ) internal pure {
        if (
            _min < PRESALE_RANGE_FLOOR || _max > PRESALE_RANGE_CEILING || _min > _max || _min % PRESALE_STEP != 0
                || _max % PRESALE_STEP != 0
        ) {
            revert("InvalidPresaleRange");
        }
    }

    function _checkOwner() internal view {
        require(msg.sender == _owner, "Not owner");
    }

    function _execute(bytes32 action, bytes32 hash) internal {
        // Placeholder for timelock logic; in original contract this was inherited from Timelocked.
        // For Solana port, we simply require the caller to be the owner.
        _checkOwner();
    }

    function _effectiveCost(uint256 baseAmount, uint256 discountBps, address user) internal view returns (uint256) {
        if (_nftCollection != address(0) && _isHolder(user)) {
            return baseAmount - (baseAmount * discountBps) / BPS_DENOMINATOR;
        }
        return baseAmount;
    }

    function _isHolder(address user) internal view returns (bool) {
        // Placeholder for NFT membership check; in original contract this was inherited from MembershipDiscount.
        // For Solana port, we assume no discount unless overridden.
        return false;
    }

    function _setNftCollection(address nft) internal {
        _nftCollection = nft;
    }

    function _computeAllocation(uint256 totalSupply, uint256 presalePercent) internal pure returns (uint256, uint256, uint256, uint256) {
        uint256 presaleTokens = (totalSupply * presalePercent) / BPS_DENOMINATOR;
        uint256 liquidityTokens = (totalSupply * (BPS_DENOMINATOR - presalePercent)) / BPS_DENOMINATOR;
        uint256 issuerVestingTokens = liquidityTokens / 2;
        uint256 lpTokens = liquidityTokens - issuerVestingTokens;
        return (presaleTokens, lpTokens, issuerVestingTokens, issuerVestingTokens);
    }

    function _splitByBps(uint256 total, uint256[] memory bps) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](bps.length);
        for (uint256 i = 0; i < bps.length; i++) {
            amounts[i] = (total * bps[i]) / BPS_DENOMINATOR;
        }
    }
}