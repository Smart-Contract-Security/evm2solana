// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {ITFLOBuyback} from "./interfaces/ITFLOBuyback.sol";
import {BasisLedger} from "./BasisLedger.sol";

contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using BasisLedger for BasisLedger.Tranche[];

    ISwapRouter   public immutable SWAP_ROUTER;
    ITFLOBuyback  public immutable BUYBACK;

    uint256 public constant MAX_BUY_THRESHOLD = 10 ether;
    uint16  public constant MAX_SELL_GAIN_BPS = 5000;
    uint8   public constant MAX_ELIGIBLE_TOKENS = 50;
    uint8   public constant PER_BUY_CAP_MULTIPLIER = 2;

    mapping(address => BasisLedger.Tranche[]) public _tranches;
    address[] public eligibleTokens;
    mapping(address => bool)  public isEligible;
    uint256 public nextBuyIndex;

    uint256 public buyThreshold;
    uint16  public sellGainBps;

    address public trader;

    event Bought(address indexed winner, uint256 indexed idx, uint256 ethSpent, uint256 tokenOut);
    event Sold(
        address indexed token,
        uint256 indexed trancheIndex,
        uint256 amount,
        uint256 ethReceived,
        uint256 realizedGainBps
    );
    event EligibleAdded(address indexed token);
    event EligibleRemoved(address indexed token);
    event BuyThresholdSet(uint256 newValue);
    event SellGainBpsSet(uint16 newValue);
    event TraderSet(address indexed oldTrader, address indexed newTrader);

    error BuyThresholdOutOfBounds(uint256 value);
    error SellGainBpsOutOfBounds(uint16 value);
    error AlreadyEligible(address token);
    error NotEligible(address token);
    error EligibleListFull();
    error InsufficientTreasuryBalance(uint256 balance, uint256 threshold);
    error NoEligibleTokens();
    error TrancheOutOfRange(address token, uint256 trancheIndex);
    error TrancheAlreadySold();
    error RealizedGainBelowFloor(uint256 realized, uint256 floor);
    error NotOwnerOrTrader(address caller);

    constructor(
        ISwapRouter swapRouter,
        ITFLOBuyback buyback,
        uint256 defaultBuyThreshold,
        uint16 defaultSellGainBps
    ) Ownable(msg.sender) {
        if (defaultBuyThreshold > MAX_BUY_THRESHOLD) {
            revert BuyThresholdOutOfBounds(defaultBuyThreshold);
        }
        if (defaultSellGainBps > MAX_SELL_GAIN_BPS) {
            revert SellGainBpsOutOfBounds(defaultSellGainBps);
        }

        SWAP_ROUTER = swapRouter;
        BUYBACK     = buyback;

        buyThreshold = defaultBuyThreshold;
        sellGainBps  = defaultSellGainBps;
    }

    receive() external payable {}

    function setBuyThreshold(uint256 value) external onlyOwner {
        if (value > MAX_BUY_THRESHOLD) {
            revert BuyThresholdOutOfBounds(value);
        }
        buyThreshold = value;
        emit BuyThresholdSet(value);
    }

    function setSellGainBps(uint16 value) external onlyOwner {
        if (value > MAX_SELL_GAIN_BPS) {
            revert SellGainBpsOutOfBounds(value);
        }
        sellGainBps = value;
        emit SellGainBpsSet(value);
    }

    function setTrader(address newTrader) external onlyOwner {
        address old = trader;
        trader = newTrader;
        emit TraderSet(old, newTrader);
    }

    function addEligibleToken(address token) external onlyOwner {
        if (eligibleTokens.length >= MAX_ELIGIBLE_TOKENS) revert EligibleListFull();
        if (isEligible[token]) revert AlreadyEligible(token);

        eligibleTokens.push(token);
        isEligible[token] = true;

        IERC20(token).forceApprove(address(SWAP_ROUTER), type(uint256).max);

        emit EligibleAdded(token);
    }

    function removeEligibleToken(address token) external onlyOwner {
        if (!isEligible[token]) revert NotEligible(token);

        uint256 len = eligibleTokens.length;
        for (uint256 i = 0; i < len; ) {
            if (eligibleTokens[i] == token) {
                if (i != len - 1) {
                    eligibleTokens[i] = eligibleTokens[len - 1];
                }
                eligibleTokens.pop();
                break;
            }
            unchecked { ++i; }
        }

        isEligible[token] = false;

        emit EligibleRemoved(token);
    }

    function _requireOwnerOrTrader() internal view {
        if (msg.sender != owner() && msg.sender != trader) revert NotOwnerOrTrader(msg.sender);
    }

    function triggerBuy(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOut
    ) external nonReentrant {
        _requireOwnerOrTrader();
        uint256 balance = address(this).balance;
        if (balance < buyThreshold) revert InsufficientTreasuryBalance(balance, buyThreshold);

        uint256 len = eligibleTokens.length;
        if (len == 0) revert NoEligibleTokens();

        uint256 idx = nextBuyIndex % len;
        address winner = eligibleTokens[idx];

        unchecked { nextBuyIndex = nextBuyIndex + 1; }

        uint256 ethToSpend = balance < buyThreshold * PER_BUY_CAP_MULTIPLIER
            ? balance
            : buyThreshold * PER_BUY_CAP_MULTIPLIER;

        uint256 out = SWAP_ROUTER.swapExactEthForToken{value: ethToSpend}(
            winner,
            commands,
            inputs,
            minOut
        );

        _tranches[winner].pushTranche(winner, out, ethToSpend);
        emit Bought(winner, idx, ethToSpend, out);
    }

    function executeSell(
        address token,
        uint256 trancheIndex,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOutSell,
        uint128 minOutBuyback
    ) external nonReentrant {
        _requireOwnerOrTrader();
        BasisLedger.Tranche[] storage arr = _tranches[token];
        if (trancheIndex >= arr.length) revert TrancheOutOfRange(token, trancheIndex);
        BasisLedger.Tranche storage t = arr[trancheIndex];
        if (t.sold) revert TrancheAlreadySold();

        uint256 ethReceived = SWAP_ROUTER.swapExactTokenForEth(
            token,
            t.amount,
            commands,
            inputs,
            minOutSell
        );

        uint256 realized = ethReceived <= t.ethSpent
            ? 0
            : ((ethReceived - t.ethSpent) * 10_000) / t.ethSpent;
        if (realized < sellGainBps) revert RealizedGainBelowFloor(realized, sellGainBps);

        t.sold = true;

        BUYBACK.buyAndBurn{value: ethReceived}(minOutBuyback);

        emit Sold(token, trancheIndex, t.amount, ethReceived, realized);
    }

    function eligibleTokensLength() external view returns (uint256) {
        return eligibleTokens.length;
    }

    function getEligibleTokens() external view returns (address[] memory) {
        return eligibleTokens;
    }

    function getTranches(address token) external view returns (BasisLedger.Tranche[] memory) {
        return _tranches[token];
    }

    function previewNextBuyTarget() external view returns (address) {
        uint256 len = eligibleTokens.length;
        if (len == 0) revert NoEligibleTokens();
        return eligibleTokens[nextBuyIndex % len];
    }
}