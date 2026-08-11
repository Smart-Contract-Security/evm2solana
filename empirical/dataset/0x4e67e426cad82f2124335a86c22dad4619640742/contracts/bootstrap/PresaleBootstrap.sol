// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchConstants} from "../libraries/LaunchConstants.sol";
import {IBootstrapHook} from "../interfaces/IBootstrapHook.sol";
import {IBurnableToken} from "../interfaces/IBurnableToken.sol";
import {IWETH9Minimal} from "../interfaces/IWETH9Minimal.sol";

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Forty-two minute, one-shot ETH presale that opens the token/WETH v4 pool.
/// @dev The launch accepts exactly 1 ETH per contribution. Each accepted
/// contribution reserves 13,370 tokens for the contributor and 13,370 tokens
/// for initial pool liquidity. The constructor-selected cap must stay within
/// 10 to 30 contributors: a 10 ETH minimum success threshold and a 30 ETH
/// maximum envelope.
///
/// At minimum success, 10 ETH becomes WETH liquidity beside 133,700 tokens,
/// another 133,700 tokens become claimable, and 534,800 unused launch tokens
/// are burned. At the 30 ETH ceiling, 401,100 tokens become claimable, 401,100
/// tokens pair with 30 WETH, and no launch inventory remains beyond bounded v4
/// liquidity-rounding dust. Caps below 30 contributors keep the same sale/LP
/// price and burn the unused inventory at finalize.
///
/// This contract is the launch boundary, not an administrative control surface.
/// It has no owner, no generic sweep, no rescue path, and no arbitrary liquidity
/// control. Contributor ETH either becomes WETH liquidity during finalize or
/// remains refundable after abort. Forced ETH and direct ERC-20 transfers outside
/// the sale ledger are not recoverable here.
///
/// The perimeter is narrow: one pool, one 42-minute span, one allocation curve.
contract PresaleBootstrap is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for int128;
    using StateLibrary for IPoolManager;

    struct CallbackData {
        IPoolManager.ModifyLiquidityParams params;
        bytes32 operationHash;
        uint256 expectedAmount0;
        uint256 expectedAmount1;
    }

    IPoolManager public immutable manager;
    address public immutable token;
    address public immutable weth;
    address public immutable hook;
    uint160 public immutable expectedSqrtPriceX96;
    PoolId public immutable poolId;
    uint256 public immutable saleStart;
    uint256 public immutable contributionAmount;
    uint256 public immutable maxRaiseWeth;
    uint256 public immutable maxContributors;
    address public immutable launchOperator;

    uint256 public constant OPERATOR_FINALIZE_PERIOD = 30 minutes;
    uint256 public constant OPERATOR_EMERGENCY_ABORT_DELAY = 24 hours;
    uint256 public constant PERMISSIONLESS_EMERGENCY_ABORT_DELAY = 72 hours;

    uint256 public contributorCount;
    bool public finalized;
    bool public aborted;
    bool public readyToFinalize;
    uint256 public readyToFinalizeAt;
    mapping(address contributor => uint256 amount) public contributedEth;
    mapping(address contributor => bool didClaim) public claimed;
    mapping(address contributor => bool hasRefunded) public refunded;

    PoolKey private _expectedKey;
    bool private _entered;
    bool private _unlockInProgress;
    bytes32 private _activeOperationHash;

    event Contributed(address indexed contributor, uint256 ethAmount, uint256 tokenClaimAmount);
    event ReadyToFinalize(uint256 contributorCount);
    event Finalized(
        uint256 contributorCount,
        uint256 claimAllocation,
        uint256 lpTokenAllocation,
        uint256 lpWethAllocation,
        uint256 tokenBurned
    );
    event Aborted(uint256 contributorCount, uint256 refundReserveEth, uint256 tokenBurned);
    event Claimed(address indexed claimant, uint256 tokenAmount);
    event Refunded(address indexed refundee, uint256 ethAmount);

    error ZeroPoolManager();
    error ZeroToken();
    error ZeroWeth();
    error ZeroHook();
    error ZeroLaunchOperator();
    error AddressHasNoCode(address target);
    error NativeCurrencyUnsupported();
    error ReentrantCall();
    error InvalidPoolHook(address actual, address expected);
    error InvalidPoolFee(uint24 actual, uint24 expected);
    error InvalidPoolProtocolFee(uint24 actual);
    error InvalidPoolTickSpacing(int24 actual, int24 expected);
    error InvalidPoolCurrencies(address currency0, address currency1, address expectedToken, address expectedWeth);
    error PoolSqrtPriceMismatch(uint160 actual, uint160 expected);
    error PoolLiquidityNonzero(uint128 liquidity);
    error InitialTokenBalanceMismatch(uint256 actual, uint256 expected);
    error SaleAlreadyFinalized();
    error SaleAlreadyAborted();
    error SaleExpired(uint256 timestamp, uint256 saleEnd);
    error SaleNotExpired(uint256 timestamp, uint256 saleEnd);
    error SaleNotFinalizable(uint256 contributorCount, uint256 timestamp, uint256 timeBound);
    error UnauthorizedFinalizer(address caller, address launchOperator, uint256 permissionlessFinalizeAt);
    error EmergencyAbortUnavailable(
        uint256 contributorCount, uint256 timestamp, uint256 operatorAbortAt, uint256 permissionlessAbortAt
    );
    error UnauthorizedEmergencyAbort(address caller, address launchOperator, uint256 permissionlessAbortAt);
    error MinRaiseNotMet(uint256 contributorCount, uint256 minimum);
    error CapReached(uint256 contributorCount);
    error InvalidContributionAmount(uint256 actual, uint256 expected);
    error ContributorAlreadyParticipated(address contributor);
    error SmartContractContributor(address contributor, address origin);
    error NoContribution(address contributor);
    error AlreadyClaimed(address claimant);
    error AlreadyRefunded(address refundee);
    error TokenTransferFailed(address to, uint256 amount);
    error RefundTransferFailed(address to, uint256 amount);
    error InsufficientNativeBalance(uint256 actual, uint256 required);
    error InsufficientTokenInventory(uint256 actual, uint256 required);
    error ClaimReserveShortfall(uint256 actual, uint256 required);
    error ClaimReserveMismatch(uint256 actual, uint256 expected);
    error InvalidExpectedLiquidity(uint256 liquidity);
    error UnlockAlreadyInProgress();
    error UnlockDidNotComplete();
    error NoActiveUnlock();
    error UnauthorizedUnlockCaller(address actual, address expected);
    error InvalidCallbackData();
    error UnexpectedFeesAccrued(BalanceDelta feesAccrued);
    error UnexpectedLiquidityDelta(BalanceDelta delta);
    error UnexpectedSettledAmount(uint256 actual, uint256 expected);
    error AllocationDustExceeded(address currency, uint256 expected, uint256 actual, uint256 dustCap);

    modifier nonReentrant() {
        if (_entered) revert ReentrantCall();
        _entered = true;
        _;
        _entered = false;
    }

    constructor(
        IPoolManager manager_,
        address token_,
        address weth_,
        address hook_,
        PoolKey memory expectedKey_,
        uint256 contributionAmount_,
        uint256 maxRaiseWeth_,
        address launchOperator_
    ) {
        if (address(manager_) == address(0)) revert ZeroPoolManager();
        if (token_ == address(0)) revert ZeroToken();
        if (weth_ == address(0)) revert ZeroWeth();
        if (hook_ == address(0)) revert ZeroHook();
        if (launchOperator_ == address(0)) revert ZeroLaunchOperator();
        _requireCode(address(manager_));
        _requireCode(token_);
        _requireCode(weth_);
        _requireCode(hook_);
        _assertExpectedKey(expectedKey_, token_, weth_, hook_);
        LaunchConstants.SaleParams memory saleParams =
            LaunchConstants.validateSaleParams(contributionAmount_, maxRaiseWeth_);

        manager = manager_;
        token = token_;
        weth = weth_;
        hook = hook_;
        expectedSqrtPriceX96 = LaunchConstants.expectedSqrtPriceX96(token_, weth_, saleParams.contributionAmount);
        poolId = expectedKey_.toId();
        saleStart = block.timestamp;
        contributionAmount = saleParams.contributionAmount;
        maxRaiseWeth = saleParams.maxRaiseWeth;
        maxContributors = saleParams.maxContributors;
        launchOperator = launchOperator_;
        _expectedKey = expectedKey_;

        _assertPoolReady();
        uint256 initialTokenBalance = IERC20Minimal(token_).balanceOf(address(this));
        if (initialTokenBalance != LaunchConstants.INITIAL_SUPPLY) {
            revert InitialTokenBalanceMismatch(initialTokenBalance, LaunchConstants.INITIAL_SUPPLY);
        }
    }

    function poolKey() external view returns (PoolKey memory) {
        return _expectedKey;
    }

    function saleEnd() public view returns (uint256) {
        return saleStart + LaunchConstants.SALE_DURATION;
    }

    function finalizeAllowedAt() public view returns (uint256) {
        if (readyToFinalize) return readyToFinalizeAt;
        return saleEnd();
    }

    function claimAmount(address contributor) external view returns (uint256) {
        if (contributedEth[contributor] != contributionAmount) return 0;
        return LaunchConstants.CLAIM_AMOUNT;
    }

    function claimAllocation() public view returns (uint256) {
        return contributorCount * LaunchConstants.CLAIM_AMOUNT;
    }

    function lpWethAllocation() public view returns (uint256) {
        return contributorCount * contributionAmount;
    }

    function contribute() external payable nonReentrant {
        _assertActive();
        uint256 end = saleEnd();
        if (block.timestamp >= end) revert SaleExpired(block.timestamp, end);
        if (msg.value != contributionAmount) {
            revert InvalidContributionAmount(msg.value, contributionAmount);
        }
        uint256 nextContributorCount = contributorCount + 1;
        if (nextContributorCount > maxContributors) revert CapReached(contributorCount);
        if (contributedEth[msg.sender] != 0) revert ContributorAlreadyParticipated(msg.sender);
        if (!_isAllowedContributor(msg.sender)) {
            revert SmartContractContributor(msg.sender, tx.origin);
        }

        contributedEth[msg.sender] = contributionAmount;
        contributorCount = nextContributorCount;
        emit Contributed(msg.sender, contributionAmount, LaunchConstants.CLAIM_AMOUNT);

        if (nextContributorCount == maxContributors) {
            readyToFinalize = true;
            readyToFinalizeAt = block.timestamp;
            emit ReadyToFinalize(nextContributorCount);
        }
    }

    function finalize() external nonReentrant {
        _finalize();
    }

    /// @dev Under-minimum expiry path. ETH stays in the contract for refunds; all remaining tokens are burned.
    function abort() external nonReentrant {
        _assertActive();
        uint256 end = saleEnd();
        if (block.timestamp < end) revert SaleNotExpired(block.timestamp, end);
        if (contributorCount >= LaunchConstants.MIN_CONTRIBUTORS) {
            revert SaleNotFinalizable(contributorCount, block.timestamp, end);
        }

        aborted = true;
        uint256 tokenBurned = IERC20Minimal(token).balanceOf(address(this));
        if (tokenBurned > 0) IBurnableToken(token).burn(tokenBurned);
        emit Aborted(contributorCount, contributorCount * contributionAmount, tokenBurned);
    }

    function emergencyAbort() external nonReentrant {
        _assertActive();
        uint256 count = contributorCount;
        if (count < LaunchConstants.MIN_CONTRIBUTORS) {
            revert MinRaiseNotMet(count, LaunchConstants.MIN_CONTRIBUTORS);
        }
        uint256 allowedAt = finalizeAllowedAt();
        uint256 operatorAbortAt = allowedAt + OPERATOR_EMERGENCY_ABORT_DELAY;
        uint256 permissionlessAbortAt = allowedAt + PERMISSIONLESS_EMERGENCY_ABORT_DELAY;
        if (block.timestamp < operatorAbortAt) {
            revert EmergencyAbortUnavailable(count, block.timestamp, operatorAbortAt, permissionlessAbortAt);
        }
        if (block.timestamp < permissionlessAbortAt && msg.sender != launchOperator) {
            revert UnauthorizedEmergencyAbort(msg.sender, launchOperator, permissionlessAbortAt);
        }

        aborted = true;
        uint256 tokenBurned = IERC20Minimal(token).balanceOf(address(this));
        if (tokenBurned > 0) IBurnableToken(token).burn(tokenBurned);
        emit Aborted(count, count * contributionAmount, tokenBurned);
    }

    function claim() external nonReentrant {
        if (!finalized) revert SaleNotFinalizable(contributorCount, block.timestamp, saleEnd());
        if (aborted) revert SaleAlreadyAborted();
        if (contributedEth[msg.sender] != contributionAmount) revert NoContribution(msg.sender);
        if (claimed[msg.sender]) revert AlreadyClaimed(msg.sender);
        if (refunded[msg.sender]) revert AlreadyRefunded(msg.sender);

        claimed[msg.sender] = true;
        if (!IERC20Minimal(token).transfer(msg.sender, LaunchConstants.CLAIM_AMOUNT)) {
            revert TokenTransferFailed(msg.sender, LaunchConstants.CLAIM_AMOUNT);
        }
        emit Claimed(msg.sender, LaunchConstants.CLAIM_AMOUNT);
    }

    function refund() external nonReentrant {
        if (!aborted) revert SaleNotFinalizable(contributorCount, block.timestamp, saleEnd());
        if (finalized) revert SaleAlreadyFinalized();
        if (contributedEth[msg.sender] != contributionAmount) revert NoContribution(msg.sender);
        if (refunded[msg.sender]) revert AlreadyRefunded(msg.sender);
        if (claimed[msg.sender]) revert AlreadyClaimed(msg.sender);

        // State is written before the ETH call so delegated-code EOAs cannot reenter the refund path.
        refunded[msg.sender] = true;
        (bool success,) = msg.sender.call{value: contributionAmount}("");
        if (!success) revert RefundTransferFailed(msg.sender, contributionAmount);
        emit Refunded(msg.sender, contributionAmount);
    }

    /// @dev PoolManager calls back during finalize liquidity insertion. The operation hash binds the
    /// callback to the active liquidity params and expected token/WETH consumption.
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert UnauthorizedUnlockCaller(msg.sender, address(manager));
        if (!_unlockInProgress) revert NoActiveUnlock();

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        bytes32 expectedOperationHash = _activeOperationHash;
        if (
            data.operationHash != expectedOperationHash
                || _operationHash(data.params, data.expectedAmount0, data.expectedAmount1) != expectedOperationHash
        ) {
            revert InvalidCallbackData();
        }

        _unlockInProgress = false;
        _activeOperationHash = bytes32(0);

        (BalanceDelta delta, BalanceDelta feesAccrued) = manager.modifyLiquidity(_expectedKey, data.params, "");
        if (feesAccrued.amount0() != 0 || feesAccrued.amount1() != 0) {
            revert UnexpectedFeesAccrued(feesAccrued);
        }

        _settleDelta(_expectedKey.currency0, delta.amount0());
        _settleDelta(_expectedKey.currency1, delta.amount1());
        _assertConsumedWithinDust(delta, data.expectedAmount0, data.expectedAmount1);

        return abi.encode(delta);
    }

    receive() external payable {
        revert NativeCurrencyUnsupported();
    }

    fallback() external payable {
        revert NativeCurrencyUnsupported();
    }

    function _finalize() private {
        _assertActive();
        uint256 count = contributorCount;
        if (count < LaunchConstants.MIN_CONTRIBUTORS) revert MinRaiseNotMet(count, LaunchConstants.MIN_CONTRIBUTORS);
        uint256 allowedAt = finalizeAllowedAt();
        if (block.timestamp < allowedAt) {
            revert SaleNotFinalizable(count, block.timestamp, allowedAt);
        }
        uint256 permissionlessFinalizeAt = allowedAt + OPERATOR_FINALIZE_PERIOD;
        if (block.timestamp < permissionlessFinalizeAt && msg.sender != launchOperator) {
            revert UnauthorizedFinalizer(msg.sender, launchOperator, permissionlessFinalizeAt);
        }

        _assertPoolReady();
        uint256 claimReserve = count * LaunchConstants.CLAIM_AMOUNT;
        uint256 lpToken = claimReserve;
        uint256 lpWeth = count * contributionAmount;
        uint256 requiredToken = claimReserve + lpToken;
        uint256 currentTokenBalance = IERC20Minimal(token).balanceOf(address(this));
        if (currentTokenBalance < requiredToken) revert InsufficientTokenInventory(currentTokenBalance, requiredToken);
        if (address(this).balance < lpWeth) revert InsufficientNativeBalance(address(this).balance, lpWeth);

        finalized = true;
        IWETH9Minimal(weth).deposit{value: lpWeth}();
        _addLiquidity(lpToken, lpWeth);

        uint256 postLpTokenBalance = IERC20Minimal(token).balanceOf(address(this));
        if (postLpTokenBalance < claimReserve) revert ClaimReserveShortfall(postLpTokenBalance, claimReserve);
        uint256 tokenBurned = postLpTokenBalance - claimReserve;
        if (tokenBurned > 0) IBurnableToken(token).burn(tokenBurned);
        uint256 postBurnTokenBalance = IERC20Minimal(token).balanceOf(address(this));
        if (postBurnTokenBalance != claimReserve) revert ClaimReserveMismatch(postBurnTokenBalance, claimReserve);

        IBootstrapHook(hook).closeLiquidityBootstrap();
        emit Finalized(count, claimReserve, lpToken, lpWeth, tokenBurned);
    }

    function _addLiquidity(uint256 lpToken, uint256 lpWeth) private returns (BalanceDelta delta) {
        (uint256 amount0, uint256 amount1) = LaunchConstants.orderedLaunchAmountValues(token, weth, lpToken, lpWeth);
        uint128 liquidity = LaunchConstants.expectedLiquidity(token, weth, lpToken, lpWeth, contributionAmount);
        if (liquidity == 0) revert InvalidExpectedLiquidity(liquidity);

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: LaunchConstants.tickLower(),
            tickUpper: LaunchConstants.tickUpper(),
            liquidityDelta: int256(uint256(liquidity)),
            salt: LaunchConstants.LP_SALT
        });
        bytes32 operationHash = _operationHash(params, amount0, amount1);
        if (_unlockInProgress) revert UnlockAlreadyInProgress();
        _unlockInProgress = true;
        _activeOperationHash = operationHash;

        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData({
                        params: params, operationHash: operationHash, expectedAmount0: amount0, expectedAmount1: amount1
                    })
                )
            ),
            (BalanceDelta)
        );
        if (_unlockInProgress || _activeOperationHash != bytes32(0)) revert UnlockDidNotComplete();
    }

    function _operationHash(
        IPoolManager.ModifyLiquidityParams memory params,
        uint256 expectedAmount0,
        uint256 expectedAmount1
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                params.tickLower, params.tickUpper, params.liquidityDelta, params.salt, expectedAmount0, expectedAmount1
            )
        );
    }

    function _settleDelta(Currency currency, int128 amount) private {
        if (amount < 0) {
            uint256 payment = uint256((-amount).toUint128());
            manager.sync(currency);
            currency.transfer(address(manager), payment);
            uint256 settled = manager.settle();
            if (settled != payment) revert UnexpectedSettledAmount(settled, payment);
        } else if (amount > 0) {
            manager.take(currency, address(this), uint256(amount.toUint128()));
        }
    }

    function _assertConsumedWithinDust(BalanceDelta delta, uint256 expectedAmount0, uint256 expectedAmount1)
        private
        view
    {
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();
        if (delta0 >= 0 || delta1 >= 0) revert UnexpectedLiquidityDelta(delta);
        uint256 actualAmount0 = uint256((-delta0).toUint128());
        uint256 actualAmount1 = uint256((-delta1).toUint128());
        _assertWithinDust(Currency.unwrap(_expectedKey.currency0), expectedAmount0, actualAmount0);
        _assertWithinDust(Currency.unwrap(_expectedKey.currency1), expectedAmount1, actualAmount1);
    }

    function _assertWithinDust(address currency, uint256 expected, uint256 actual) private pure {
        uint256 diff = expected > actual ? expected - actual : actual - expected;
        if (diff > LaunchConstants.ALLOCATION_DUST_CAP) {
            revert AllocationDustExceeded(currency, expected, actual, LaunchConstants.ALLOCATION_DUST_CAP);
        }
    }

    function _assertActive() private view {
        if (finalized) revert SaleAlreadyFinalized();
        if (aborted) revert SaleAlreadyAborted();
    }

    function _assertPoolReady() private view {
        (uint160 actualSqrtPriceX96, int24 actualTick, uint24 protocolFee, uint24 actualLpFee) =
            manager.getSlot0(poolId);
        if (actualSqrtPriceX96 != expectedSqrtPriceX96) {
            revert PoolSqrtPriceMismatch(actualSqrtPriceX96, expectedSqrtPriceX96);
        }
        if (actualLpFee != LaunchConstants.STATIC_LP_FEE) {
            revert InvalidPoolFee(actualLpFee, LaunchConstants.STATIC_LP_FEE);
        }
        if (protocolFee != 0) revert InvalidPoolProtocolFee(protocolFee);
        actualTick;
        uint128 liquidity = manager.getLiquidity(poolId);
        if (liquidity != 0) revert PoolLiquidityNonzero(liquidity);
    }

    function _isAllowedContributor(address contributor) private view returns (bool) {
        if (contributor != tx.origin) return false;

        bytes memory code = contributor.code;
        if (code.length == 0) return true;
        // EIP-7702 delegated EOAs expose exactly `0xef0100 || delegate`; arbitrary contract code is rejected.
        if (code.length != 23) return false;
        if (code[0] != bytes1(0xef) || code[1] != bytes1(0x01) || code[2] != bytes1(0x00)) return false;

        address delegate;
        assembly ("memory-safe") {
            delegate := shr(96, mload(add(code, 0x23)))
        }
        return delegate != address(0);
    }

    function _assertExpectedKey(PoolKey memory key, address token_, address weth_, address hook_) private pure {
        if (address(key.hooks) != hook_) revert InvalidPoolHook(address(key.hooks), hook_);
        if (key.fee != LaunchConstants.STATIC_LP_FEE) revert InvalidPoolFee(key.fee, LaunchConstants.STATIC_LP_FEE);
        if (key.tickSpacing != LaunchConstants.TICK_SPACING) {
            revert InvalidPoolTickSpacing(key.tickSpacing, LaunchConstants.TICK_SPACING);
        }
        (Currency expected0, Currency expected1) = LaunchConstants.orderedLaunchCurrencies(token_, weth_);
        if (
            Currency.unwrap(key.currency0) != Currency.unwrap(expected0)
                || Currency.unwrap(key.currency1) != Currency.unwrap(expected1)
        ) {
            revert InvalidPoolCurrencies(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), token_, weth_);
        }
    }

    function _requireCode(address target) private view {
        if (target.code.length == 0) revert AddressHasNoCode(target);
    }
}
