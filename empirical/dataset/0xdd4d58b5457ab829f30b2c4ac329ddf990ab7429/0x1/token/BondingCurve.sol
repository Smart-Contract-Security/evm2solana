// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBondingCurve} from "../interfaces/IBondingCurve.sol";

/// @title BondingCurve
/// @notice Linear bonding curve sale gated by `openMinting()`.
///         price(s) = (s + SUPPLY_OFFSET) / SCALE
///         The offset sets the starting price to ~1.2× the initial LP price.
contract BondingCurve is Ownable2Step, ReentrancyGuard, IBondingCurve {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant CURVE_ALLOC = 900_000_000 ether;
    uint256 public constant override MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant override MAX_MINT_PER_TX = 500_000 ether;
    uint256 public constant override TARGET_ETH = 500 ether;
    uint256 public constant SCALE = 81e31;
    uint256 public constant SUPPLY_OFFSET = 19_440_000 ether;

    IERC20 public immutable token;
    address public immutable treasury;

    bool public mintingOpen;
    bool public override curveClosed;
    uint256 public sold;
    uint256 public ethRaised;

    error AmountIsZero();
    error AmountAboveCap();
    error CurveExhausted();
    error InsufficientEth();
    error EthRefundFailed();
    error EthSendFailed();
    error NothingToWithdraw();
    error MintingNotOpen();
    error AlreadyOpen();

    event MintingOpened();

    constructor(address token_, address treasury_) Ownable(msg.sender) {
        require(token_ != address(0) && treasury_ != address(0), "BC: zero addr");
        token = IERC20(token_);
        treasury = treasury_;
    }

    /// @notice Open public minting. One-way. Curve must be funded first.
    function openMinting() external onlyOwner {
        if (mintingOpen) revert AlreadyOpen();
        require(token.balanceOf(address(this)) >= CURVE_ALLOC, "BC: not funded");
        mintingOpen = true;
        emit MintingOpened();
    }

    function _costForBuy(uint256 s, uint256 n) internal pure returns (uint256) {
        uint256 effectiveS = s + SUPPLY_OFFSET;
        uint256 numerator = 2 * effectiveS * n + n * n;
        return numerator.ceilDiv(2 * SCALE);
    }

    /// @inheritdoc IBondingCurve
    function quoteBuy(uint256 amount) external view override returns (uint256) {
        return _costForBuy(sold, amount);
    }

    /// @inheritdoc IBondingCurve
    function quoteSell(uint256) external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBondingCurve
    function curveProgress()
        external
        view
        override
        returns (uint256 soldSoFar, uint256 ethRaisedSoFar, uint256 percentComplete)
    {
        soldSoFar = sold;
        ethRaisedSoFar = ethRaised;
        percentComplete = (sold * 10_000) / CURVE_ALLOC;
    }

    function ethBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Current marginal price scaled by 1e18 (wei per token-wei × 1e18).
    function currentPriceScaled() external view returns (uint256) {
        return (sold + SUPPLY_OFFSET) * 1e18 / SCALE;
    }

    /// @inheritdoc IBondingCurve
    function mint(uint256 amount) external payable override nonReentrant {
        if (!mintingOpen) revert MintingNotOpen();
        if (amount == 0) revert AmountIsZero();
        if (amount > MAX_MINT_PER_TX) revert AmountAboveCap();

        uint256 s = sold;
        if (s + amount > CURVE_ALLOC) revert CurveExhausted();

        uint256 cost = _costForBuy(s, amount);
        if (msg.value < cost) revert InsufficientEth();

        sold = s + amount;
        ethRaised += cost;
        if (sold == CURVE_ALLOC) {
            curveClosed = true;
            emit CurveClosed(ethRaised);
        }

        token.safeTransfer(msg.sender, amount);
        emit Minted(msg.sender, amount, cost, sold);

        uint256 refund = msg.value - cost;
        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert EthRefundFailed();
        }
    }

    /// @inheritdoc IBondingCurve
    function sellBack(uint256) external pure override {
        revert("BC: sell-back disabled");
    }

    /// @inheritdoc IBondingCurve
    function withdrawToTreasury() external override nonReentrant {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool ok,) = treasury.call{value: amount}("");
        if (!ok) revert EthSendFailed();
        emit TreasuryWithdrawal(treasury, amount);
    }
}
