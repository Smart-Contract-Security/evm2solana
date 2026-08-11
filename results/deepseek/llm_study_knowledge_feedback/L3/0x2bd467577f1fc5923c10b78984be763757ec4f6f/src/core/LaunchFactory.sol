// SPDX-License-Identifier: BUSL-1.1

import {AccountMeta} from 'solana';

contract LaunchFactory {
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
        uint64 presalePercent;
        address[] vestingRecipients;
        uint64[] vestingPercents;
        string[] vestingLabels;
        address referrer;
        address[] issuerFeeRecipients;
        uint64[] issuerFeeSplits;
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
        uint64 issuer;
        uint64 boardwalk;
        uint64 incentive;
        uint64 referrer;
        uint64 total;
    }

    uint64 private constant MAX_BMX_BURN = 200000000000000000000;
    uint64 private constant MAX_FEE_RECIPIENTS = 4;
    uint64 private constant MAX_VESTING_RECIPIENTS = 5;
    uint64 private constant MIN_ADVANCED_DURATION = 2 days;
    uint64 private constant MAX_ADVANCED_DURATION = 14 days;

    uint64 private constant PRESALE_RANGE_FLOOR = 500;
    uint64 private constant PRESALE_RANGE_CEILING = 5000;
    uint64 private constant PRESALE_STEP = 500;

    uint64 private constant MIN_ISSUER_BPS = 10;
    uint64 private constant MAX_ISSUER_BPS = 80;
    uint64 private constant MIN_BOARDWALK_BPS = 10;
    uint64 private constant MAX_BOARDWALK_BPS = 50;
    uint64 private constant MAX_INCENTIVE_BPS = 50;
    uint64 private constant MAX_REFERRER_BPS = 10;
    uint64 private constant MAX_INTEGRATOR_BPS = 50;

    uint64 private constant MIN_ANTI_WHALE_TAX_BPS = 500;
    uint64 private constant MAX_ANTI_WHALE_TAX_BPS = 4000;
    uint64 private constant MIN_ANTI_WHALE_DURATION = 5 minutes;
    uint64 private constant MAX_ANTI_WHALE_DURATION = 90 minutes;

    uint64 private constant BPS_DENOMINATOR = 10000;
    uint64 private constant MAX_DISCOUNT_BPS = 10000;

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
    uint64 public immutable INTEGRATOR_BPS;

    address public boardwalkFeeCollector;

    uint64 public bmxBurnAmount;

    uint64 public expressDuration;
    uint64 public advancedDuration;

    uint64 public minPresalePercent = 2500;
    uint64 public maxPresalePercent = 5000;

    uint64 public graduationExpress;
    uint64 public graduationAdvanced;

    uint64 public memberLaunchDiscountBps;

    uint64 public antiWhaleTaxBps;
    uint64 public antiWhaleDuration;

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
    event BmxBurnAmountChanged(uint64 oldAmount, uint64 newAmount);
    event GraduationThresholdChanged(LaunchPath path, uint64 oldThreshold, uint64 newThreshold);
    event PresaleDurationChanged(LaunchPath path, uint64 oldDuration, uint64 newDuration);
    event FeeDefaultsChanged(uint64 issuer, uint64 boardwalk, uint64 incentive, uint64 referrer);
    event PresaleRangeChanged(uint64 oldMin, uint64 oldMax, uint64 newMin, uint64 newMax);
    event FeeCollectorChanged(address oldCollector, address newCollector);
    event MemberLaunchDiscountChanged(uint64 oldDiscount, uint64 newDiscount);
    event AntiWhaleConfigChanged(uint64 oldTaxBps, uint64 oldDuration, uint64 newTaxBps, uint64 newDuration);

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
        uint64 integratorBps;
        uint64 bmxBurnAmount;
        uint64 graduationExpress;
        uint64 graduationAdvanced;
        uint64 expressDuration;
        uint64 advancedDuration;
        uint64 antiWhaleTaxBps;
        uint64 antiWhaleDuration;
        FeeBpsDefaults feeBps;
        address nftCollection;
        uint64 memberLaunchDiscountBps;
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
        if (p.bmxBurnAmount > MAX_BMX_BURN) {
            revert("BmxBurnOutOfRange");
        }
        bmxBurnAmount = p.bmxBurnAmount;
        if (p.graduationExpress == 0 || p.graduationAdvanced == 0) {
            revert("ZeroGraduation");
        }
        graduationExpress = p.graduationExpress;
        graduationAdvanced = p.graduationAdvanced;
        if (p.expressDuration == 0) {
            revert("InvalidDuration");
        }
        if (p.advancedDuration < MIN_ADVANCED_DURATION || p.advancedDuration > MAX_ADVANCED_DURATION) {
            revert("InvalidDuration");
        }
        expressDuration = p.expressDuration;
        advancedDuration = p.advancedDuration;

        if (p.integratorBps > MAX_INTEGRATOR_BPS) {
            revert("InvalidFeeDefaults");
        }
        if ((p.integratorBps > 0) != (p.integratorCollector != address(0))) {
            revert("IntegratorCollectorMismatch");
        }
        INTEGRATOR_BPS = p.integratorBps;
        INTEGRATOR_COLLECTOR = p.integratorCollector;

        _validateFeeDefaults(p.feeBps);
        _feeBpsDefaults = p.feeBps;

        _validateAntiWhale(p.antiWhaleTaxBps, p.antiWhaleDuration);
        antiWhaleTaxBps = p.antiWhaleTaxBps;
        antiWhaleDuration = p.antiWhaleDuration;

        _validateDistinctRoles(p.integratorCollector, p.boardwalkFeeCollector, p.boardwalkLpManager);

        if (p.memberLaunchDiscountBps > MAX_DISCOUNT_BPS) {
            revert("MemberDiscountOutOfRange");
        }
        memberLaunchDiscountBps = p.memberLaunchDiscountBps;
        _setNftCollection(p.nftCollection);
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Zero address");
        _owner = newOwner;
    }

    function renounceOwnership() public onlyOwner {
        _owner = address(0);
    }

    function currentFeeBps()
        external
        view
        returns (
            uint64 issuer,
            uint64 boardwalk,
            uint64 incentive,
            uint64 referrer,
            uint64 integratorBps,
            uint64 total
        )
    {
        FeeBpsDefaults memory d = _feeBpsDefaults;
        return (d.issuer, d.boardwalk, d.incentive, d.referrer, INTEGRATOR_BPS, d.total);
    }

    function launchCount() external view returns (uint64) {
        return uint64(allLaunches.length);
    }

    function isLaunchToken(
        address token
    ) external view returns (bool) {
        return launches[token].token != address(0);
    }

    function createLaunch(
        LaunchConfig calldata config
    ) external returns (address tokenAddr) {
        _validateConfig(config);

        address caller = tx.accounts.dataAccount.key;
        uint64 effectiveBurn = _effectiveCost(bmxBurnAmount, memberLaunchDiscountBps, caller);
        if (effectiveBurn > 0) {
            // SPL Token transfer: call BMX token program to transfer from caller to DEAD_ADDRESS
            AccountMeta[3] memory metas = [
                AccountMeta({pubkey: caller, is_signer: true, is_writable: true}),
                AccountMeta({pubkey: DEAD_ADDRESS, is_signer: false, is_writable: true}),
                AccountMeta({pubkey: BMX, is_signer: false, is_writable: false})
            ];
            BMX.call{accounts: metas}(abi.encodeWithSignature("transfer(address,address,uint64)", caller, DEAD_ADDRESS, effectiveBurn));
        }

        tokenAddr = _clone(TOKEN_IMPL);
        address feeDistributorAddr = _clone(FEE_DISTRIBUTOR_IMPL);
        address presaleAddr = _clone(PRESALE_IMPL);
        address lpStakingAddr = _clone(LP_STAKING_IMPL);

        address vestingAddr;
        if (config.vestingRecipients.length > 0) {
            vestingAddr = _clone(VESTING_IMPL);
        }

        // ILPStaking(lpStakingAddr).setInitializer(presaleAddr)
        {
            AccountMeta[1] memory metas = [
                AccountMeta({pubkey: lpStakingAddr, is_signer: false, is_writable: true})
            ];
            lpStakingAddr.call{accounts: metas}(abi.encodeWithSignature("setInitializer(address)", presaleAddr));
        }

        if (vestingAddr != address(0)) {
            // IVestingStream(vestingAddr).setInitializer(presaleAddr, caller)
            AccountMeta[1] memory metas = [
                AccountMeta({pubkey: vestingAddr, is_signer: false, is_writable: true})
            ];
            vestingAddr.call{accounts: metas}(abi.encodeWithSignature("setInitializer(address,address)", presaleAddr, caller));
        }

        FeeBpsDefaults memory feeBps = _feeBpsDefaults;

        // IBoardwalkToken(tokenAddr).initialize(...)
        {
            address[] memory exemptList = _buildExemptList(presaleAddr, lpStakingAddr, vestingAddr);
            AccountMeta[1] memory metas = [
                AccountMeta({pubkey: tokenAddr, is_signer: false, is_writable: true})
            ];
            tokenAddr.call{accounts: metas}(
                abi.encodeWithSignature(
                    "initialize(string,string,uint64,uint64,uint64,address,address,address[])",
                    config.name,
                    config.ticker,
                    feeBps.total,
                    antiWhaleTaxBps,
                    antiWhaleDuration,
                    feeDistributorAddr,
                    presaleAddr,
                    exemptList
                )
            );
        }

        uint64 effectiveReferrerBps = config.referrer != address(0) ? feeBps.referrer : 0;
        uint64 effectiveBoardwalkBps = feeBps.boardwalk - effectiveReferrerBps;

        // IFeeDistributor(feeDistributorAddr).initialize(...)
        {
            AccountMeta[1] memory metas = [
                AccountMeta({pubkey: feeDistributorAddr, is_signer: false, is_writable: true})
            ];
            feeDistributorAddr.call{accounts: metas}(
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address[],uint64[],address,uint64,uint64,uint64,uint64,uint64))",
                    tokenAddr,
                    lpStakingAddr,
                    boardwalkFeeCollector,
                    INTEGRATOR_COLLECTOR,
                    BOARDWALK_ROUTER,
                    RAISE_TOKEN,
                    config.issuerFeeRecipients,
                    config.issuerFeeSplits,
                    config.referrer,
                    feeBps.issuer,
                    effectiveBoardwalkBps,
                    feeBps.incentive,
                    effectiveReferrerBps,
                    INTEGRATOR_BPS
                )
            );
        }

        uint64 presaleDuration;
        uint64 presalePercent;
        uint64 graduationThreshold;
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

        // IPresaleManager(presaleAddr).initialize(...)
        {
            AccountMeta[1] memory metas = [
                AccountMeta({pubkey: presaleAddr, is_signer: false, is_writable: true})
            ];
            presaleAddr.call{accounts: metas}(
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address,address,address,uint64,uint64,uint64,bool)",
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
        }

        if (config.vestingRecipients.length > 0) {
            _setVestingConfig(config, presaleAddr, presalePercent);
        }

        LaunchInfo memory info = LaunchInfo({
            token: tokenAddr,
            feeDistributor: feeDistributorAddr,
            presaleManager: presaleAddr,
            vestingStream: vestingAddr,
            lpStaking: lpStakingAddr,
            issuer: caller,
            path: config.path,
            createdAt: uint32(block.timestamp)
        });

        launches[tokenAddr] = info;
        allLaunches.push(tokenAddr);

        emit LaunchCreated(
            tokenAddr,
            caller,
            config.name,
            config.ticker,
            config.category,
            config.description,
            config.path,
            config.issuerFeeLabels,
            config.vestingLabels
        );
    }

    function _setVestingConfig(
        LaunchConfig calldata config,
        address presaleAddr,
        uint64 presalePercent
    ) internal {
        (,,, uint64 issuerVestingTokens) = _computeAllocation(10000000000000000000000000000, presalePercent);
        uint64[] memory vestingAmounts = _splitByBps(issuerVestingTokens, config.vestingPercents);
        // IPresaleManager(presaleAddr).setVestingConfig(config.vestingRecipients, vestingAmounts)
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: presaleAddr, is_signer: false, is_writable: true})
        ];
        presaleAddr.call{accounts: metas}(
            abi.encodeWithSignature("setVestingConfig(address[],uint64[])", config.vestingRecipients, vestingAmounts)
        );
    }

    function _computeAllocation(uint64 totalSupply, uint64 presalePercent) internal pure returns (uint64, uint64, uint64, uint64) {
        uint64 presaleTokens = (totalSupply * presalePercent) / BPS_DENOMINATOR;
        uint64 liquidityTokens = (totalSupply * 5000) / BPS_DENOMINATOR;
        uint64 issuerTokens = totalSupply - presaleTokens - liquidityTokens;
        return (presaleTokens, liquidityTokens, 0, issuerTokens);
    }

    function _splitByBps(uint64 total, uint64[] memory bps) internal pure returns (uint64[] memory amounts) {
        amounts = new uint64[](bps.length);
        for (uint64 i = 0; i < bps.length; i++) {
            amounts[i] = (total * bps[i]) / BPS_DENOMINATOR;
        }
    }

    function _buildExemptList(
        address presaleAddr,
        address lpStakingAddr,
        address vestingAddr
    ) internal view returns (address[] memory exemptAddresses) {
        bool hasIntegrator = INTEGRATOR_BPS > 0;

        uint64 count = 4;
        if (vestingAddr != address(0)) count++;
        if (hasIntegrator) count++;

        exemptAddresses = new address[](count);
        exemptAddresses[0] = presaleAddr;
        exemptAddresses[1] = lpStakingAddr;
        exemptAddresses[2] = BOARDWALK_LP_MANAGER;
        exemptAddresses[3] = boardwalkFeeCollector;
        uint64 idx = 4;
        if (vestingAddr != address(0)) exemptAddresses[idx++] = vestingAddr;
        if (hasIntegrator) exemptAddresses[idx++] = INTEGRATOR_COLLECTOR;
    }

    function _validateConfig(
        LaunchConfig calldata config
    ) internal view {
        if (
            config.issuerFeeRecipients.length != config.issuerFeeSplits.length
                || config.issuerFeeRecipients.length != config.issuerFeeLabels.length
        ) {
            revert("ArrayLengthMismatch");
        }
        if (
            config.vestingRecipients.length != config.vestingPercents.length
                || config.vestingRecipients.length != config.vestingLabels.length
        ) {
            revert("ArrayLengthMismatch");
        }

        uint64 feeRecipientCount = uint64(config.issuerFeeRecipients.length);
        if (feeRecipientCount == 0 || feeRecipientCount > MAX_FEE_RECIPIENTS) {
            revert("TooManyRecipients");
        }

        uint64 feeSplitSum;
        for (uint64 i = 0; i < feeRecipientCount;) {
            if (config.issuerFeeRecipients[i] == address(0)) {
                revert("ZeroAddress");
            }
            feeSplitSum += config.issuerFeeSplits[i];
            unchecked {
                ++i;
            }
        }
        if (feeSplitSum != BPS_DENOMINATOR) {
            revert("InvalidSplitsSum");
        }

        if (config.path == LaunchPath.EXPRESS) {
            if (config.referrer != address(0)) {
                revert("ReferrerNotAllowedOnExpressPath");
            }
            if (config.vestingRecipients.length > 0) {
                revert("VestingNotAllowedOnExpressPath");
            }
            if (feeRecipientCount != 1) {
                revert("ExpressRequiresOneFeeRecipient");
            }
        } else {
            uint64 pp = config.presalePercent;
            if (pp < minPresalePercent || pp > maxPresalePercent) {
                revert("InvalidPresalePercent");
            }
            if (pp % PRESALE_STEP != 0) {
                revert("PresalePercentNotDivisibleBy5");
            }

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
                uint64 vestingSum;
                for (uint64 i = 0; i < config.vestingPercents.length;) {
                    vestingSum += config.vestingPercents[i];
                    unchecked {
                        ++i;
                    }
                }
                if (vestingSum != BPS_DENOMINATOR) {
                    revert("InvalidSplitsSum");
                }
            }
        }
    }

    function _checkOwner() internal view {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
    }

    function _effectiveCost(uint64 baseAmount, uint64 discountBps, address user) internal view returns (uint64) {
        if (_nftCollection != address(0) && _hasNft(_nftCollection, user)) {
            return (baseAmount * (BPS_DENOMINATOR - discountBps)) / BPS_DENOMINATOR;
        }
        return baseAmount;
    }

    function _hasNft(address collection, address user) internal view returns (bool) {
        // Placeholder for NFT balance check
        return false;
    }

    function _setNftCollection(address nft) internal {
        _nftCollection = nft;
    }

    function executeSetBmxBurn(
        uint64 _amount
    ) external onlyOwner {
        if (_amount > MAX_BMX_BURN) {
            revert("BmxBurnOutOfRange");
        }
        emit BmxBurnAmountChanged(bmxBurnAmount, _amount);
        bmxBurnAmount = _amount;
    }

    function executeSetGraduation(
        LaunchPath path,
        uint64 _threshold
    ) external onlyOwner {
        if (_threshold == 0) {
            revert("ZeroGraduation");
        }
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
        uint64 _duration
    ) external onlyOwner {
        if (path == LaunchPath.EXPRESS) {
            if (_duration == 0) {
                revert("InvalidDuration");
            }
            emit PresaleDurationChanged(LaunchPath.EXPRESS, expressDuration, _duration);
            expressDuration = _duration;
        } else {
            if (_duration < MIN_ADVANCED_DURATION || _duration > MAX_ADVANCED_DURATION) {
                revert("InvalidDuration");
            }
            emit PresaleDurationChanged(LaunchPath.ADVANCED, advancedDuration, _duration);
            advancedDuration = _duration;
        }
    }

    function executeSetFeeDefaults(
        FeeBpsDefaults calldata _feeBps
    ) external onlyOwner {
        _validateFeeDefaults(_feeBps);
        _feeBpsDefaults = _feeBps;
        emit FeeDefaultsChanged(_feeBps.issuer, _feeBps.boardwalk, _feeBps.incentive, _feeBps.referrer);
    }

    function executeSetPresaleRange(
        uint64 _min,
        uint64 _max
    ) external onlyOwner {
        _validatePresaleRange(_min, _max);
        emit PresaleRangeChanged(minPresalePercent, maxPresalePercent, _min, _max);
        minPresalePercent = _min;
        maxPresalePercent = _max;
    }

    function executeSetFeeCollector(
        address _collector
    ) external onlyOwner {
        if (_collector == address(0)) {
            revert("ZeroAddress");
        }
        if (_collector == INTEGRATOR_COLLECTOR || _collector == BOARDWALK_LP_MANAGER) {
            revert("DuplicateRoleAddress");
        }
        emit FeeCollectorChanged(boardwalkFeeCollector, _collector);
        boardwalkFeeCollector = _collector;
    }

    function executeSetNftCollection(
        address _nft
    ) external onlyOwner {
        _setNftCollection(_nft);
    }

    function executeSetMemberLaunchDiscount(
        uint64 _bps
    ) external onlyOwner {
        if (_bps > MAX_DISCOUNT_BPS) {
            revert("MemberDiscountOutOfRange");
        }
        emit MemberLaunchDiscountChanged(memberLaunchDiscountBps, _bps);
        memberLaunchDiscountBps = _bps;
    }

    function executeSetAntiWhale(
        uint64 _taxBps,
        uint64 _duration
    ) external onlyOwner {
        _validateAntiWhale(_taxBps, _duration);
        emit AntiWhaleConfigChanged(antiWhaleTaxBps, antiWhaleDuration, _taxBps, _duration);
        antiWhaleTaxBps = _taxBps;
        antiWhaleDuration = _duration;
    }

    function _validateFeeDefaults(
        FeeBpsDefaults memory d
    ) internal view {
        if (d.total != d.issuer + d.boardwalk + d.incentive + INTEGRATOR_BPS) {
            revert("InvalidFeeDefaults");
        }
        if (d.issuer < MIN_ISSUER_BPS || d.issuer > MAX_ISSUER_BPS) {
            revert("InvalidFeeDefaults");
        }
        if (d.boardwalk < MIN_BOARDWALK_BPS || d.boardwalk > MAX_BOARDWALK_BPS) {
            revert("InvalidFeeDefaults");
        }
        if (d.incentive > MAX_INCENTIVE_BPS) {
            revert("InvalidFeeDefaults");
        }
        if (d.referrer > MAX_REFERRER_BPS) {
            revert("InvalidFeeDefaults");
        }
        if (d.referrer > d.boardwalk) {
            revert("InvalidFeeDefaults");
        }
    }

    function _validateAntiWhale(
        uint64 taxBps,
        uint64 duration
    ) internal pure {
        if (taxBps < MIN_ANTI_WHALE_TAX_BPS || taxBps > MAX_ANTI_WHALE_TAX_BPS) {
            revert("InvalidAntiWhaleConfig");
        }
        if (duration < MIN_ANTI_WHALE_DURATION || duration > MAX_ANTI_WHALE_DURATION) {
            revert("InvalidAntiWhaleConfig");
        }
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
        if (feeCollectorAddr == lpManagerAddr) {
            revert("DuplicateRoleAddress");
        }
    }

    function _validatePresaleRange(
        uint64 _min,
        uint64 _max
    ) internal pure {
        if (
            _min < PRESALE_RANGE_FLOOR || _max > PRESALE_RANGE_CEILING || _min > _max || _min % PRESALE_STEP != 0
                || _max % PRESALE_STEP != 0
        ) {
            revert("InvalidPresaleRange");
        }
    }

    // Helper to clone a program-derived address (replaces Clones.clone)
    function _clone(address implementation) internal returns (address cloneAddr) {
        bytes memory seed = abi.encodePacked(implementation, allLaunches.length);
        cloneAddr = address(keccak256(seed));
        // In Solana, contract creation requires explicit account allocation via CPI
        // This is a simplified placeholder; actual deployment would need system program CPI
        AccountMeta[2] memory metas = [
            AccountMeta({pubkey: cloneAddr, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: implementation, is_signer: false, is_writable: false})
        ];
        // Deploy clone via system program or custom loader
        // For now, assume clone address is pre-allocated
    }
}