// SPDX-License-Identifier: MIT

// Solana port: CoreAccess and Types are inlined; IRebalanceManager interface removed.
// Solang does not support imports of local files in the same way; we inline the needed types and base logic.

// Inlined Types (from ../interfaces/Types.sol)
struct RebalanceBuy {
    address tokenIn;
    address tokenOut;
    uint64 amountIn;
    uint64 minAmountOut;
}

enum RebalanceTrigger {
    Active,
    PassivePeriodic,
    PassiveRiskEvent
}

struct OndoTarget {
    address token;
    uint16 bps;
}

// Inlined CoreAccess base logic (simplified for Solana)
// Solana: no msg.sender, use tx.accounts.dataAccount.key for authorization checks.
// We store admin as an address and provide onlyAdmin modifier equivalent.

contract RebalanceManager {
    address public admin;
    address public coreVault;
    address public usdc;
    uint64 public rebalanceNonce;
    uint64 public minPassiveRebalanceInterval;
    uint64 public lastPassiveRebalanceAt;
    bytes32 public activeRebalanceId;
    mapping(bytes32 => address[]) private _rebalanceExpectedBuyTokens;
    mapping(bytes32 => uint64[]) private _rebalanceExpectedMinAmounts;
    mapping(bytes32 => RebalanceTrigger) public rebalanceTrigger;
    mapping(bytes32 => uint8) public rebalanceRiskLevel;
    mapping(bytes32 => bytes32) public rebalanceReasonHash;
    mapping(bytes32 => bool) public settledGroup;
    mapping(bytes32 => OndoTarget[]) private _pendingOndoTargets;
    bool private _rebalanceManagerInitialized;

    // Modifier equivalent: check that the caller (data account) is the admin
    modifier onlyAdmin() {
        require(tx.accounts.dataAccount.key == admin, "Not admin");
        _;
    }

    modifier onlyCoreVault() {
        _onlyCoreVault();
        _;
    }

    // Constructor: Solana requires @payer, @space, @seed for contract deployment.
    // We assume deployment is handled externally; constructor logic moved to initialize.
    // For simplicity, we provide an initialize function that sets admin and usdc.
    // The original constructor called _initializeRebalanceManager if admin != address(0).
    // We'll just use initialize as the primary entry point.
    constructor() {
        // Solana constructors cannot take arguments easily without annotations.
        // We leave empty and rely on initialize.
    }

    function initialize(address admin_, address usdc_) external {
        require(!_rebalanceManagerInitialized, "Already initialized");
        require(admin_ != address(0), "Invalid admin");
        require(usdc_ != address(0), "Invalid USDC");
        admin = admin_;
        usdc = usdc_;
        _rebalanceManagerInitialized = true;
    }

    function setCoreVault(address coreVault_) external onlyAdmin {
        require(coreVault_ != address(0), "Invalid coreVault");
        coreVault = coreVault_;
    }

    function setPassiveRebalanceInterval(uint64 interval) external onlyAdmin {
        minPassiveRebalanceInterval = interval;
    }

    function prepareActiveRebalance(
        uint64 sellCount,
        uint64 buyCount,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint64[] calldata targetWeights
    ) external onlyCoreVault returns (bytes32 rbId) {
        require(activeRebalanceId == bytes32(0), "Active rebalance exists");
        require(sellCount > 0 && buyCount > 0, "Invalid counts");
        rbId = _newRebalanceId(sellCount, buyCount, RebalanceTrigger.Active);
        rebalanceTrigger[rbId] = RebalanceTrigger.Active;
        _saveExpectedBuys(rbId, buys);
        _validateTargets(targetTokens, targetWeights);
        activeRebalanceId = rbId;
    }

    function preparePassiveRebalance(
        uint64 sellCount,
        uint64 buyCount,
        RebalanceTrigger trigger,
        uint8 riskLevel,
        bytes32 reasonHash,
        RebalanceBuy[] calldata buys,
        address[] calldata targetTokens,
        uint64[] calldata targetWeights
    ) external onlyCoreVault returns (bytes32 rbId) {
        require(activeRebalanceId == bytes32(0), "Active rebalance exists");
        _validatePassive(targetTokens.length, targetWeights.length, trigger);
        rbId = _newRebalanceId(sellCount, buyCount, trigger);
        lastPassiveRebalanceAt = uint64(block.timestamp);
        rebalanceTrigger[rbId] = trigger;
        rebalanceRiskLevel[rbId] = riskLevel;
        rebalanceReasonHash[rbId] = reasonHash;
        _validateTargets(targetTokens, targetWeights);
        _saveExpectedBuys(rbId, buys);
        activeRebalanceId = rbId;
    }

    function validateRebalanceFilled(bytes32 rbId, address[] calldata tokens, uint64[] calldata amounts)
        external
        view
    {
        _validateRebalanceFilled(rbId, tokens, amounts);
    }

    function _validateRebalanceFilled(bytes32 rbId, address[] calldata tokens, uint64[] calldata amounts)
        internal
        view
    {
        address[] storage expectedTokens = _rebalanceExpectedBuyTokens[rbId];
        uint64[] storage expectedAmounts = _rebalanceExpectedMinAmounts[rbId];
        for (uint64 i = 0; i < expectedTokens.length; ++i) {
            uint64 actualAmount = 0;
            for (uint64 j = 0; j < tokens.length; ++j) {
                if (tokens[j] == expectedTokens[i]) {
                    actualAmount += amounts[j];
                }
            }
            require(actualAmount >= expectedAmounts[i], "Insufficient fill");
        }
    }

    function _settleRebalanceInternal(bytes32 rbId) internal {
        _clearExpectedBuys(rbId);
        activeRebalanceId = bytes32(0);
    }

    function _settleRebalanceFailureInternal(bytes32 rbId) internal {
        _clearExpectedBuys(rbId);
        activeRebalanceId = bytes32(0);
    }

    function settleRebalanceComplete(
        bytes32 rbId,
        address[] calldata tokens,
        uint64[] calldata amounts
    ) external onlyCoreVault {
        if (settledGroup[rbId]) return;
        require(rbId == activeRebalanceId, "Not active rebalance");
        require(tokens.length == amounts.length, "Length mismatch");
        _validateRebalanceFilled(rbId, tokens, amounts);
        settledGroup[rbId] = true;
        _settleRebalanceInternal(rbId);
    }

    function settleRebalanceFailed(bytes32 rbId) external onlyCoreVault {
        if (settledGroup[rbId]) return;
        require(rbId == activeRebalanceId, "Not active rebalance");
        settledGroup[rbId] = true;
        _settleRebalanceFailureInternal(rbId);
    }

    function isSettled(bytes32 rbId) external view returns (bool) {
        return settledGroup[rbId];
    }

    function savePendingOndoTargets(
        bytes32 rbId,
        address[] calldata targetTokens,
        uint64[] calldata targetWeights
    ) external onlyCoreVault {
        require(targetTokens.length == targetWeights.length, "Length mismatch");
        delete _pendingOndoTargets[rbId];
        uint64 total = 0;
        for (uint64 i = 0; i < targetTokens.length; ++i) {
            require(targetTokens[i] != address(0), "Zero token");
            require(targetWeights[i] <= type(uint16).max, "Weight overflow");
            for (uint64 j = 0; j < i; ++j) {
                require(targetTokens[i] != targetTokens[j], "Duplicate token");
            }
            total += targetWeights[i];
            _pendingOndoTargets[rbId].push(OndoTarget({token: targetTokens[i], bps: uint16(targetWeights[i])}));
        }
        require(total == 10_000, "Total not 100%");
    }

    function getPendingOndoTargets(bytes32 rbId) external view returns (OndoTarget[] memory) {
        return _pendingOndoTargets[rbId];
    }

    function clearPendingOndoTargets(bytes32 rbId) external onlyCoreVault {
        _clearPendingOndoTargets(rbId);
    }

    function _clearPendingOndoTargets(bytes32 rbId) internal {
        delete _pendingOndoTargets[rbId];
    }

    function _validatePassive(uint64 targetTokenLength, uint64 targetWeightLength, RebalanceTrigger trigger)
        internal
        view
    {
        require(
            trigger == RebalanceTrigger.PassivePeriodic || trigger == RebalanceTrigger.PassiveRiskEvent,
            "Invalid trigger"
        );
        require(targetTokenLength == targetWeightLength, "Length mismatch");
        if (trigger == RebalanceTrigger.PassivePeriodic && minPassiveRebalanceInterval > 0) {
            require(
                uint64(block.timestamp) >= lastPassiveRebalanceAt + minPassiveRebalanceInterval,
                "Interval not met"
            );
        }
    }

    function _newRebalanceId(uint64 sellCount, uint64 buyCount, RebalanceTrigger trigger) internal returns (bytes32) {
        rebalanceNonce += 1;
        return _rebalanceHash(coreVault, uint64(0), rebalanceNonce, sellCount, buyCount, trigger);
    }

    function _onlyCoreVault() internal view {
        require(tx.accounts.dataAccount.key == coreVault, "Not coreVault");
    }

    function _rebalanceHash(
        address vault,
        uint64 chainId,
        uint64 nonce_,
        uint64 sellCount,
        uint64 buyCount,
        RebalanceTrigger trigger
    ) internal pure returns (bytes32 result) {
        bytes memory data = abi.encodePacked(vault, chainId, uint64(0xe0), nonce_, sellCount, buyCount, trigger, uint64(2), uint64(0x5242));
        result = keccak256(data);
    }

    function _validateTargets(address[] calldata targetTokens, uint64[] calldata targetWeights) internal pure {
        require(targetTokens.length == targetWeights.length, "Length mismatch");
        uint64 total = 0;
        for (uint64 i = 0; i < targetTokens.length; ++i) {
            require(targetTokens[i] != address(0), "Zero token");
            for (uint64 j = 0; j < i; ++j) {
                require(targetTokens[i] != targetTokens[j], "Duplicate token");
            }
            total += targetWeights[i];
        }
        require(total == 10_000, "Total not 100%");
    }

    function _saveExpectedBuys(bytes32 rbId, RebalanceBuy[] calldata buys) internal {
        for (uint64 i = 0; i < buys.length; ++i) {
            require(buys[i].tokenIn != address(0), "Zero tokenIn");
            require(buys[i].tokenOut != address(0), "Zero tokenOut");
            require(buys[i].tokenIn == usdc, "Not USDC");
            require(buys[i].amountIn > 0, "Zero amount");
            _rebalanceExpectedBuyTokens[rbId].push(buys[i].tokenOut);
            _rebalanceExpectedMinAmounts[rbId].push(buys[i].minAmountOut);
        }
    }

    function _clearExpectedBuys(bytes32 rbId) internal {
        delete _rebalanceExpectedBuyTokens[rbId];
        delete _rebalanceExpectedMinAmounts[rbId];
    }
}