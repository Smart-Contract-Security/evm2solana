// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMoolahVault} from "./interfaces/IMoolahVault.sol";
import {Id, IMoolah, Market, MarketParams, Position} from "./interfaces/IMoolah.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {MathLib, WAD} from "./libraries/MathLib.sol";
import {IBroker, FixedTermAndRate} from "./interfaces/IBroker.sol";
import {RateMath} from "./libraries/RateMath.sol";

struct VaultConfig {
    address asset;
    string symbol;
    uint256 decimals;
}

struct VaultResponse {
    VaultConfig config;
    uint256 fee;
    address feeRecipient;
    address skimRecipient;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 lastTotalAssets;
    address provider;
    uint256 liquidity;
    uint256 supplyRateView;
    uint256 utilization;
}

contract GetVault {
    using MathLib for uint256;
    using MathLib for uint128;

    function query(IMoolahVault vault, IMoolah moolah) external view returns (VaultResponse memory res) {
        res.config = VaultConfig({asset: vault.asset(), symbol: vault.symbol(), decimals: vault.decimals()});

        res.fee = vault.fee();
        res.feeRecipient = vault.feeRecipient();
        res.skimRecipient = vault.skimRecipient();
        res.totalSupply = vault.totalSupply();
        res.totalAssets = vault.totalAssets();
        res.lastTotalAssets = vault.lastTotalAssets();
        try vault.provider() returns (address providerAddr) {
            res.provider = providerAddr;
        } catch {
            res.provider = address(0);
        }

        (res.liquidity, res.utilization, res.supplyRateView) = _aggregateQueue(moolah, vault, _withdrawQueue(vault));
    }

    /// @return liquidity Sum of (totalSupplyAssets - totalBorrowAssets) per market when positive.
    /// @return utilization Weighted average utilization of the supply queue.
    /// @return supplyRateView Weighted average supply rate (by allocation).
    function _aggregateQueue(IMoolah moolah, IMoolahVault vault, Id[] memory queue)
        internal
        view
        returns (uint256 liquidity, uint256 utilization, uint256 supplyRateView)
    {
        uint256 weightedRate = 0;
        uint256 totalLoan = 0;
        for (uint256 i; i < queue.length; ++i) {
            (uint256 liq, uint256 loan, uint256 rateWeighted) =
                _marketLiquidityAllocationAndWeightedRate(moolah, vault, queue[i]);
            liquidity += liq;
            totalLoan += loan;
            weightedRate += rateWeighted;
        }
        uint256 totalSupplyAssets = vault.totalAssets();
        supplyRateView = totalSupplyAssets > 0 ? weightedRate.wDivDown(totalSupplyAssets) : 0;
        utilization = totalSupplyAssets > 0 ? totalLoan.wDivDown(totalSupplyAssets) : 0;
    }

    function _marketLiquidityAllocationAndWeightedRate(IMoolah moolah, IMoolahVault vault, Id marketId)
        internal
        view
        returns (uint256 liquidity, uint256 loan, uint256 weightedRate)
    {
        Market memory mkt = moolah.market(marketId);
        uint256 supplyAssets = uint256(mkt.totalSupplyAssets);

        if (supplyAssets == 0 || mkt.totalSupplyShares == 0) {
            return (liquidity, 0, 0);
        }

        IBroker broker = IBroker(moolah.brokers(marketId));
        uint256 borrowRateBySecond = 0;
        if (address(broker) != address(0)) {
            FixedTermAndRate[] memory fixedTerms = broker.getFixedTerms();
            // get the last fixed term and convert the APR to a per-second rate
            borrowRateBySecond =
                fixedTerms.length > 0 ? RateMath.aprPerSecond(fixedTerms[fixedTerms.length - 1].apr) : 0;
        } else {
            MarketParams memory mktParams = moolah.idToMarketParams(marketId);
            if (mktParams.irm != address(0)) {
                borrowRateBySecond = IIrm(mktParams.irm).borrowRateView(mktParams, mkt);
            }
        }

        uint256 borrowAssets = uint256(mkt.totalBorrowAssets);
        uint256 marketLiquidity = supplyAssets - borrowAssets;
        Position memory pos = moolah.position(marketId, address(vault));
        uint256 allocation = pos.supplyShares.wDivDown(mkt.totalSupplyShares).wMulDown(mkt.totalSupplyAssets);
        uint256 utilization = borrowAssets.wDivDown(supplyAssets);
        uint256 feeFactor = mkt.fee <= WAD ? WAD - uint256(mkt.fee) : 0;
        // calculate the borrowed
        loan = utilization.wMulDown(allocation);
        // calculate not borrowed
        liquidity = marketLiquidity < allocation ? marketLiquidity : allocation;
        // calculate the weighted rate
        weightedRate = borrowRateBySecond.wMulDown(feeFactor).wMulDown(loan);
    }

    function _withdrawQueue(IMoolahVault vault) internal view returns (Id[] memory withdrawQueue) {
        uint256 withdrawQueueLength = vault.withdrawQueueLength();
        withdrawQueue = new Id[](withdrawQueueLength);
        for (uint256 i; i < withdrawQueueLength; ++i) {
            withdrawQueue[i] = vault.withdrawQueue(i);
        }
    }

    function _supplyQueue(IMoolahVault vault) internal view returns (Id[] memory supplyQueue) {
        uint256 supplyQueueLength = vault.supplyQueueLength();
        supplyQueue = new Id[](supplyQueueLength);
        for (uint256 i; i < supplyQueueLength; ++i) {
            supplyQueue[i] = vault.supplyQueue(i);
        }
    }

    function querySupplyQueue(IMoolahVault vault) external view returns (Id[] memory supplyQueue) {
        supplyQueue = _supplyQueue(vault);
    }

    function queryWithdrawQueue(IMoolahVault vault) external view returns (Id[] memory withdrawQueue) {
        withdrawQueue = _withdrawQueue(vault);
    }
}
