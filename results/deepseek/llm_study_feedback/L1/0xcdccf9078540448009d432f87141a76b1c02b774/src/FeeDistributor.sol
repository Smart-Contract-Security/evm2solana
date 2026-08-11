// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Solang on Solana does not support Uniswap V4 or external dependencies.
// We stub out all V4-specific types and interfaces to allow compilation.
// The contract logic is preserved but V4 swap functionality is disabled.

interface IPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData) external returns (BalanceDelta memory delta);
    function getSlot0(PoolId poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint24 lpFee);
    function sync(Currency currency) external;
    function settle() external;
    function take(Currency currency, address to, uint256 amount) external;
}

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

type PoolId is bytes32;

library PoolIdLibrary {
    function toId(PoolKey memory key) internal pure returns (PoolId) {
        return PoolId.wrap(keccak256(abi.encode(key)));
    }
}

type Currency is address;

library CurrencyLibrary {
    Currency constant ADDRESS_ZERO = Currency.wrap(address(0));
    function wrap(address a) internal pure returns (Currency) {
        return Currency.wrap(a);
    }
    function unwrap(Currency c) internal pure returns (address) {
        return Currency.unwrap(c);
    }
}

struct BalanceDelta {
    int128 amount0;
    int128 amount1;
}

library StateLibrary {
    function getSlot0(IPoolManager pm, PoolId poolId) internal view returns (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint24 lpFee) {
        return pm.getSlot0(poolId);
    }
}

library FullMath {
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512-bit multiplication to avoid overflow
        if (denominator == 0) {
            revert("division by zero");
        }
        if (a == 0 || b == 0) {
            return 0;
        }
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 == 0) {
            return prod0 / denominator;
        }
        if (prod1 >= denominator) {
            revert("overflow");
        }
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        prod1 = sub(prod1, gt(remainder, prod0));
        prod0 = sub(prod0, remainder);
        uint256 twos = denominator & (0 - denominator);
        assembly {
            denominator := div(denominator, twos)
        }
        assembly {
            prod0 := div(prod0, twos)
        }
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;
        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        result = prod0 * inv;
        return result;
    }
}

interface IFeeDistributor {
    function POOL_MANAGER() external view returns (address);
    function RARE_TOKEN() external view returns (address);
    function PROTOCOL_FEE_RECIPIENT() external view returns (address);
    function totalFeeBPS() external view returns (uint16);
    function maxSlippageBps() external view returns (uint16);
    function conversionEnabled() external view returns (bool);
    function beneficiaryShareBPS() external view returns (uint16);
    function beneficiaryRegistry() external view returns (address);
    function approvedHooks(address hook) external view returns (bool);
    function notifyFee(address liquidToken, uint256 rareAmount) external;
    function setRareEthPoolKey(PoolKey calldata _rareEthPoolKey) external;
    function setMaxSlippageBps(uint16 _maxSlippageBps) external;
    function setConversionEnabled(bool _enabled) external;
    function setBeneficiaryShareBPS(uint16 _beneficiaryShareBPS) external;
    function setBeneficiaryRegistry(address _beneficiaryRegistry) external;
    function setHookApproval(address hook, bool approved) external;
    function protocolFeeRecipient() external view returns (address);
    function quoteFeeBreakdown(uint256 amount) external pure returns (uint256, uint256);
    function distributeFees(uint256 amount, address, address) external payable returns (uint256, uint256, uint256);
}

interface ILiquidRegistry {
    function beneficiaryOf(address liquidToken) external view returns (address);
}

contract FeeDistributor is IFeeDistributor, Ownable {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    address public immutable override POOL_MANAGER;
    address public immutable override RARE_TOKEN;
    address public immutable override PROTOCOL_FEE_RECIPIENT;
    uint16 public immutable override totalFeeBPS;

    uint256 internal constant BENEFICIARY_ETH_GAS_LIMIT = 2300;

    uint16 public override maxSlippageBps;
    bool public override conversionEnabled;

    PoolKey public rareEthPoolKey;

    uint16 public override beneficiaryShareBPS;
    address public override beneficiaryRegistry;

    mapping(address => bool) public override approvedHooks;

    event FeeConvertedAndDistributed(
        address indexed liquidToken,
        address indexed beneficiary,
        uint256 rareTotal,
        uint256 ethTotal,
        uint256 ethBen,
        uint256 ethProt
    );

    event FeeDistributedInRare(
        address indexed liquidToken,
        address indexed beneficiary,
        uint256 rareTotal,
        uint256 rareBen,
        uint256 rareProt,
        bytes32 reason
    );

    event FeeTransferFailed(address indexed to, uint256 amount, bytes32 reason);
    event RareEthPoolKeyUpdated(PoolKey oldKey, PoolKey newKey);
    event MaxSlippageBpsUpdated(uint16 oldBps, uint16 newBps);
    event ConversionEnabledUpdated(bool enabled);
    event BeneficiaryShareBpsUpdated(uint16 oldBps, uint16 newBps);
    event BeneficiaryRegistryUpdated(address oldRegistry, address newRegistry);
    event HookApprovalUpdated(address indexed hook, bool approved);

    error AddressZero();
    error InvalidBeneficiaryShare();
    error InvalidTotalFee();
    error InvalidPoolKeyCurrencies();
    error InvalidSlippageBps();
    error NotContract();
    error UnauthorizedHook(address caller);

    constructor(
        address _owner,
        address _poolManager,
        address _rareToken,
        address _protocolFeeRecipient,
        uint16 _beneficiaryShareBPS,
        uint16 _totalFeeBPS
    ) Ownable(_owner) {
        if (_protocolFeeRecipient == address(0)) revert AddressZero();
        if (_beneficiaryShareBPS > 10_000) revert InvalidBeneficiaryShare();
        if (_totalFeeBPS > 10_000) revert InvalidTotalFee();

        bool anyV4Set = _poolManager != address(0) || _rareToken != address(0);
        if (anyV4Set) {
            if (_poolManager == address(0)) revert AddressZero();
            if (_rareToken == address(0)) revert AddressZero();
        }

        POOL_MANAGER = _poolManager;
        RARE_TOKEN = _rareToken;
        PROTOCOL_FEE_RECIPIENT = _protocolFeeRecipient;
        totalFeeBPS = _totalFeeBPS;
        beneficiaryShareBPS = _beneficiaryShareBPS;

        maxSlippageBps = 100;
        conversionEnabled = true;
    }

    modifier onlyHook() {
        _onlyHook();
        _;
    }

    modifier onlySelf() {
        _onlySelf();
        _;
    }

    function _onlySelf() internal view {
        if (msg.sender != address(this)) revert UnauthorizedHook(msg.sender);
    }

    function _onlyHook() internal view {
        if (!approvedHooks[msg.sender]) revert UnauthorizedHook(msg.sender);
    }

    function notifyFee(
        address liquidToken,
        uint256 rareAmount
    ) external override onlyHook {
        if (rareAmount == 0) return;

        address beneficiary;
        address reg = beneficiaryRegistry;
        if (reg != address(0)) {
            try ILiquidRegistry(reg).beneficiaryOf(liquidToken) returns (
                address registryBeneficiary
            ) {
                beneficiary = registryBeneficiary;
            } catch {
                beneficiary = address(0);
            }
        }

        (uint256 rareBen, uint256 rareProt) = _split(rareAmount, beneficiary);

        bool canConvert = POOL_MANAGER != address(0) &&
            RARE_TOKEN != address(0) &&
            conversionEnabled;

        if (!canConvert) {
            _distributeRare(
                liquidToken,
                beneficiary,
                rareBen,
                rareProt,
                "CONVERSION_OFF"
            );
            return;
        }

        if (!_validPoolKeyCurrencies()) {
            _distributeRare(
                liquidToken,
                beneficiary,
                rareBen,
                rareProt,
                "NO_KEY"
            );
            return;
        }

        try
            this._convertAndDistributeEth(
                liquidToken,
                beneficiary,
                rareBen,
                rareProt
            )
        {
            // success emitted inside _convertAndDistributeEth
        } catch {
            _distributeRare(
                liquidToken,
                beneficiary,
                rareBen,
                rareProt,
                "CONVERT_FAIL"
            );
        }
    }

    function _convertAndDistributeEth(
        address liquidToken,
        address beneficiary,
        uint256 rareBen,
        uint256 rareProt
    ) external onlySelf {
        IPoolManager pm = IPoolManager(POOL_MANAGER);
        PoolKey memory key = rareEthPoolKey;
        uint256 rareTotal = rareBen + rareProt;

        bool rareIsToken0 = Currency.unwrap(key.currency0) == RARE_TOKEN;

        (uint160 spotSqrtPriceX96, , , ) = pm.getSlot0(key.toId());

        uint256 minEthOut = _computeMinOut(
            rareTotal,
            rareIsToken0,
            spotSqrtPriceX96
        );

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: rareIsToken0,
            amountSpecified: -int256(rareTotal),
            sqrtPriceLimitX96: rareIsToken0
                ? 4295128739 + 1
                : 1461446703485210103287273052203988822378723970342 - 1
        });

        BalanceDelta memory delta = pm.swap(key, swapParams, "");

        int128 ethDelta = rareIsToken0 ? delta.amount1 : delta.amount0;
        if (ethDelta <= 0) revert("NO_ETH_OUT");
        uint256 ethTotal = uint256(uint128(ethDelta));

        if (ethTotal < minEthOut) revert("SLIPPAGE_EXCEEDED");

        Currency rareCurrency = Currency.wrap(RARE_TOKEN);
        pm.sync(rareCurrency);
        IERC20(RARE_TOKEN).safeTransfer(POOL_MANAGER, rareTotal);
        pm.settle();

        Currency ethCurrency = CurrencyLibrary.ADDRESS_ZERO;
        uint16 benShareBps = beneficiaryShareBPS;

        uint256 ethBen;
        uint256 ethProt;

        if (beneficiary != address(0) && benShareBps > 0) {
            ethBen = (ethTotal * benShareBps) / 10_000;
            ethProt = ethTotal - ethBen;

            pm.take(ethCurrency, PROTOCOL_FEE_RECIPIENT, ethProt);
            pm.take(ethCurrency, address(this), ethBen);

            if (!_sendEth(beneficiary, ethBen, BENEFICIARY_ETH_GAS_LIMIT)) {
                _sendEth(PROTOCOL_FEE_RECIPIENT, ethBen, gasleft());
                ethProt += ethBen;
                ethBen = 0;
            }
        } else {
            ethProt = ethTotal;
            pm.take(ethCurrency, PROTOCOL_FEE_RECIPIENT, ethProt);
        }

        emit FeeConvertedAndDistributed(
            liquidToken,
            beneficiary,
            rareTotal,
            ethTotal,
            ethBen,
            ethProt
        );
    }

    function _distributeRare(
        address liquidToken,
        address beneficiary,
        uint256 rareBen,
        uint256 rareProt,
        bytes32 reason
    ) internal {
        if (beneficiary != address(0) && rareBen > 0) {
            try this._transferRare(beneficiary, rareBen) {
                // success
            } catch {
                emit FeeTransferFailed(
                    beneficiary,
                    rareBen,
                    "RARE_SEND_FAILED"
                );
                rareProt += rareBen;
                rareBen = 0;
            }
        } else {
            rareProt += rareBen;
            rareBen = 0;
        }
        if (rareProt > 0) {
            IERC20(RARE_TOKEN).safeTransfer(PROTOCOL_FEE_RECIPIENT, rareProt);
        }

        emit FeeDistributedInRare(
            liquidToken,
            beneficiary,
            rareBen + rareProt,
            rareBen,
            rareProt,
            reason
        );
    }

    function _split(
        uint256 rareAmount,
        address beneficiary
    ) internal view returns (uint256 rareBen, uint256 rareProt) {
        uint16 benBps = beneficiaryShareBPS;
        if (beneficiary != address(0) && benBps > 0) {
            rareBen = (rareAmount * benBps) / 10_000;
            rareProt = rareAmount - rareBen;
        } else {
            rareProt = rareAmount;
        }
    }

    function _validPoolKeyCurrencies() internal view returns (bool) {
        address c0 = Currency.unwrap(rareEthPoolKey.currency0);
        address c1 = Currency.unwrap(rareEthPoolKey.currency1);
        return
            (c0 == address(0) && c1 == RARE_TOKEN) ||
            (c0 == RARE_TOKEN && c1 == address(0));
    }

    function _computeMinOut(
        uint256 rareIn,
        bool rareIsToken0,
        uint160 sqrtPriceX96
    ) internal view returns (uint256 minOut) {
        uint256 sqrtP = uint256(sqrtPriceX96);
        if (sqrtP == 0) return 0;

        uint256 priceQ128 = FullMath.mulDiv(sqrtP, sqrtP, 1 << 64);
        if (priceQ128 == 0) return 0;

        uint256 spotEth;
        if (rareIsToken0) {
            spotEth = FullMath.mulDiv(rareIn, priceQ128, 1 << 128);
        } else {
            spotEth = FullMath.mulDiv(rareIn, 1 << 128, priceQ128);
        }

        uint16 slipBps = maxSlippageBps;
        minOut = FullMath.mulDiv(spotEth, 10_000 - slipBps, 10_000);
    }

    function _transferRare(address to, uint256 amount) external onlySelf {
        IERC20(RARE_TOKEN).safeTransfer(to, amount);
    }

    function _sendEth(
        address to,
        uint256 amount,
        uint256 gasLimit
    ) internal returns (bool) {
        if (amount == 0) return true;
        (bool ok, ) = to.call{value: amount, gas: gasLimit}("");
        if (!ok) {
            emit FeeTransferFailed(to, amount, "ETH_SEND_FAILED");
        }
        return ok;
    }

    function protocolFeeRecipient() external view override returns (address) {
        return PROTOCOL_FEE_RECIPIENT;
    }

    function quoteFeeBreakdown(
        uint256
    ) external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function distributeFees(
        uint256,
        address,
        address
    ) external payable override returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }

    function setRareEthPoolKey(
        PoolKey calldata _rareEthPoolKey
    ) external override onlyOwner {
        if (RARE_TOKEN != address(0)) {
            address c0 = Currency.unwrap(_rareEthPoolKey.currency0);
            address c1 = Currency.unwrap(_rareEthPoolKey.currency1);
            bool valid = (c0 == address(0) && c1 == RARE_TOKEN) ||
                (c0 == RARE_TOKEN && c1 == address(0));
            if (!valid) revert InvalidPoolKeyCurrencies();
        }
        PoolKey memory old = rareEthPoolKey;
        rareEthPoolKey = _rareEthPoolKey;
        emit RareEthPoolKeyUpdated(old, _rareEthPoolKey);
    }

    function setMaxSlippageBps(
        uint16 _maxSlippageBps
    ) external override onlyOwner {
        if (_maxSlippageBps > 10_000) revert InvalidSlippageBps();
        uint16 old = maxSlippageBps;
        maxSlippageBps = _maxSlippageBps;
        emit MaxSlippageBpsUpdated(old, _maxSlippageBps);
    }

    function setConversionEnabled(bool _enabled) external override onlyOwner {
        conversionEnabled = _enabled;
        emit ConversionEnabledUpdated(_enabled);
    }

    function setBeneficiaryShareBPS(
        uint16 _beneficiaryShareBPS
    ) external override onlyOwner {
        if (_beneficiaryShareBPS > 10_000) revert InvalidBeneficiaryShare();
        uint16 old = beneficiaryShareBPS;
        beneficiaryShareBPS = _beneficiaryShareBPS;
        emit BeneficiaryShareBpsUpdated(old, _beneficiaryShareBPS);
    }

    function setBeneficiaryRegistry(
        address _beneficiaryRegistry
    ) external override onlyOwner {
        if (_beneficiaryRegistry == address(0)) revert AddressZero();
        if (_beneficiaryRegistry.code.length == 0) revert NotContract();
        address old = beneficiaryRegistry;
        beneficiaryRegistry = _beneficiaryRegistry;
        emit BeneficiaryRegistryUpdated(old, _beneficiaryRegistry);
    }

    function setHookApproval(
        address hook,
        bool approved
    ) external override onlyOwner {
        approvedHooks[hook] = approved;
        emit HookApprovalUpdated(hook, approved);
    }

    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert AddressZero();
        IERC20(token).safeTransfer(to, amount);
    }

    function rescueETH(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert AddressZero();
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH rescue failed");
    }

    receive() external payable {}
}