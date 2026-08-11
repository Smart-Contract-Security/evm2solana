// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/openzeppelin/access/Ownable.sol";
import "./lib/openzeppelin/security/ReentrancyGuard.sol";
import "./lib/openzeppelin/security/Pausable.sol";
import "./lib/openzeppelin/utils/Address.sol";

/// @title HousePoolV2
/// @notice APE liquidity pool with admin-settable economic parameters. Functionally
///         identical to HousePool EXCEPT WITHDRAW_COOLDOWN, UTILIZATION_CAP_BPS, and
///         MIN_FIRST_DEPOSIT are now storage variables behind onlyOwner setters with
///         max caps. Math invariants (BASIS_POINTS, DEAD_SHARES, SHARE_PRECISION)
///         remain constant.
contract HousePoolV2 is Ownable, ReentrancyGuard, Pausable {
    using Address for address payable;

    // ===== Math invariants =====
    uint256 public constant BASIS_POINTS              = 10000;
    uint256 public constant DEAD_SHARES_FIRST_DEPOSIT = 1000;
    uint256 public constant SHARE_PRECISION           = 1e18;

    // ===== Admin caps =====
    uint256 public constant MAX_WITHDRAW_COOLDOWN     = 30 days;
    uint256 public constant MAX_UTILIZATION_CAP_BPS   = 9500; // 95% — leaves cash buffer

    // ===== Variable parameters =====
    uint256 public withdrawCooldown;
    uint256 public utilizationCapBps;
    uint256 public minFirstDeposit;

    uint256 public totalAssetsAPE;
    uint256 public totalShares;
    uint256 public reservedAPE;

    mapping(address => uint256) public shareOf;
    mapping(uint256 => uint256) public loanReserved;

    struct WithdrawRequest {
        uint128 shares;
        uint128 unlockAt;
    }
    mapping(address => WithdrawRequest) public pendingWithdraw;

    address public loanManager;
    address public revenueDistributor;

    event Deposited(address indexed lp, uint256 apeIn, uint256 sharesOut);
    event WithdrawRequested(address indexed lp, uint256 shares, uint256 unlockAt);
    event WithdrawCancelled(address indexed lp, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares, uint256 apeOut);
    event Borrowed(uint256 indexed loanId, address indexed to, uint256 amount);
    event Repaid(uint256 indexed loanId, uint256 principal);
    event ForfeitReceived(uint256 indexed loanId, uint256 amount);
    event YieldNotified(uint256 amount);
    event LossSocialized(uint256 indexed loanId, uint256 amount);
    event LoanManagerSet(address indexed loanManager);
    event RevenueDistributorSet(address indexed revenueDistributor);

    event WithdrawCooldownSet(uint256 oldValue, uint256 newValue);
    event UtilizationCapBpsSet(uint256 oldValue, uint256 newValue);
    event MinFirstDepositSet(uint256 oldValue, uint256 newValue);

    modifier onlyLoanManager() {
        require(msg.sender == loanManager, "HP: not loan mgr");
        _;
    }

    modifier onlyRevenueDistributor() {
        require(msg.sender == revenueDistributor, "HP: not RD");
        _;
    }

    constructor(address initialOwner) {
        withdrawCooldown   = 7 days;
        utilizationCapBps  = 8000;
        minFirstDeposit    = 1 ether;
        if (initialOwner != address(0) && initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
    }

    // ===== Admin =====
    function setLoanManager(address _lm) external onlyOwner {
        require(_lm != address(0), "HP: zero");
        loanManager = _lm;
        emit LoanManagerSet(_lm);
    }

    function setRevenueDistributor(address _rd) external onlyOwner {
        require(_rd != address(0), "HP: zero");
        revenueDistributor = _rd;
        emit RevenueDistributorSet(_rd);
    }

    function setWithdrawCooldown(uint256 v) external onlyOwner {
        require(v <= MAX_WITHDRAW_COOLDOWN, "HP: cooldown > cap");
        emit WithdrawCooldownSet(withdrawCooldown, v);
        withdrawCooldown = v;
    }

    function setUtilizationCapBps(uint256 v) external onlyOwner {
        require(v > 0 && v <= MAX_UTILIZATION_CAP_BPS, "HP: cap oob");
        emit UtilizationCapBpsSet(utilizationCapBps, v);
        utilizationCapBps = v;
    }

    function setMinFirstDeposit(uint256 v) external onlyOwner {
        require(v >= DEAD_SHARES_FIRST_DEPOSIT, "HP: min < dead shares");
        emit MinFirstDepositSet(minFirstDeposit, v);
        minFirstDeposit = v;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ===== LP =====
    function deposit() external payable nonReentrant whenNotPaused returns (uint256 shares) {
        require(msg.value > 0, "HP: zero deposit");
        uint256 _totalShares = totalShares;
        if (_totalShares == 0) {
            require(msg.value >= minFirstDeposit, "HP: first deposit too small");
            shares = msg.value - DEAD_SHARES_FIRST_DEPOSIT;
            totalShares = msg.value;
        } else {
            shares = (msg.value * _totalShares) / totalAssetsAPE;
            require(shares > 0, "HP: zero shares");
            totalShares = _totalShares + shares;
        }
        shareOf[msg.sender] += shares;
        totalAssetsAPE += msg.value;
        emit Deposited(msg.sender, msg.value, shares);
    }

    function requestWithdraw(uint256 shares) external whenNotPaused {
        require(shares > 0, "HP: zero shares");
        require(shares <= shareOf[msg.sender], "HP: insufficient shares");
        require(pendingWithdraw[msg.sender].shares == 0, "HP: pending exists");
        uint256 unlockAt = block.timestamp + withdrawCooldown;
        pendingWithdraw[msg.sender] = WithdrawRequest(uint128(shares), uint128(unlockAt));
        emit WithdrawRequested(msg.sender, shares, unlockAt);
    }

    function cancelWithdraw() external {
        WithdrawRequest memory req = pendingWithdraw[msg.sender];
        require(req.shares > 0, "HP: no request");
        delete pendingWithdraw[msg.sender];
        emit WithdrawCancelled(msg.sender, req.shares);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 apeOut) {
        WithdrawRequest memory req = pendingWithdraw[msg.sender];
        require(req.shares > 0, "HP: no request");
        require(block.timestamp >= req.unlockAt, "HP: cooldown");
        require(shares > 0 && shares <= req.shares, "HP: invalid shares");
        require(shares <= shareOf[msg.sender], "HP: insufficient shares");

        apeOut = (shares * totalAssetsAPE) / totalShares;
        require(apeOut > 0, "HP: zero out");
        require(apeOut <= address(this).balance, "HP: insufficient cash");

        shareOf[msg.sender] -= shares;
        totalShares -= shares;
        totalAssetsAPE -= apeOut;

        if (req.shares == uint128(shares)) {
            delete pendingWithdraw[msg.sender];
        } else {
            pendingWithdraw[msg.sender].shares = req.shares - uint128(shares);
        }

        payable(msg.sender).sendValue(apeOut);
        emit Withdrawn(msg.sender, shares, apeOut);
    }

    // ===== LoanVaultManager hooks =====
    function borrow(address to, uint256 amount, uint256 loanId)
        external onlyLoanManager nonReentrant whenNotPaused
    {
        require(to != address(0), "HP: zero to");
        require(amount > 0, "HP: zero amount");
        require(loanReserved[loanId] == 0, "HP: loan exists");
        uint256 newReserved = reservedAPE + amount;
        require(
            newReserved * BASIS_POINTS <= totalAssetsAPE * utilizationCapBps,
            "HP: utilization cap"
        );
        require(amount <= address(this).balance, "HP: insufficient cash");
        reservedAPE = newReserved;
        loanReserved[loanId] = amount;
        payable(to).sendValue(amount);
        emit Borrowed(loanId, to, amount);
    }

    function repay(uint256 loanId, uint256 principal)
        external payable onlyLoanManager nonReentrant
    {
        require(msg.value == principal, "HP: value mismatch");
        require(principal > 0, "HP: zero");
        uint256 outstanding = loanReserved[loanId];
        require(principal <= outstanding, "HP: overpay");
        loanReserved[loanId] = outstanding - principal;
        reservedAPE -= principal;
        emit Repaid(loanId, principal);
    }

    function notifyForfeit(uint256 loanId)
        external payable onlyLoanManager nonReentrant
    {
        require(msg.value > 0, "HP: zero");
        uint256 outstanding = loanReserved[loanId];
        require(msg.value <= outstanding, "HP: forfeit > outstanding");
        loanReserved[loanId] = outstanding - msg.value;
        reservedAPE -= msg.value;
        emit ForfeitReceived(loanId, msg.value);
    }

    function accrueLoss(uint256 loanId, uint256 lossAmount) external onlyLoanManager {
        uint256 outstanding = loanReserved[loanId];
        require(lossAmount <= outstanding, "HP: loss > outstanding");
        loanReserved[loanId] = 0;
        reservedAPE -= outstanding;
        totalAssetsAPE -= lossAmount;
        emit LossSocialized(loanId, lossAmount);
    }

    function notifyYield() external payable onlyRevenueDistributor {
        require(msg.value > 0, "HP: zero");
        totalAssetsAPE += msg.value;
        emit YieldNotified(msg.value);
    }

    // ===== Views =====
    function pricePerShare() external view returns (uint256) {
        if (totalShares == 0) return SHARE_PRECISION;
        return (totalAssetsAPE * SHARE_PRECISION) / totalShares;
    }

    function utilization() external view returns (uint256) {
        if (totalAssetsAPE == 0) return 0;
        return (reservedAPE * BASIS_POINTS) / totalAssetsAPE;
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsAPE;
    }

    function freeLiquidity() public view returns (uint256) {
        return address(this).balance;
    }

    function maxBorrowable() external view returns (uint256) {
        uint256 capReserved = (totalAssetsAPE * utilizationCapBps) / BASIS_POINTS;
        if (reservedAPE >= capReserved) return 0;
        uint256 capRoom = capReserved - reservedAPE;
        uint256 cash = address(this).balance;
        return capRoom < cash ? capRoom : cash;
    }

    function previewDeposit(uint256 apeIn) external view returns (uint256) {
        if (totalShares == 0) {
            if (apeIn < DEAD_SHARES_FIRST_DEPOSIT) return 0;
            return apeIn - DEAD_SHARES_FIRST_DEPOSIT;
        }
        return (apeIn * totalShares) / totalAssetsAPE;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (shares * totalAssetsAPE) / totalShares;
    }

    receive() external payable {
        revert("HP: use deposit()");
    }
}
