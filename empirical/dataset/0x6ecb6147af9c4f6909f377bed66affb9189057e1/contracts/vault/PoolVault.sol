// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IJudgmentObligationController.sol";

contract PoolVault is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CIRCUIT_BREAKER_ROLE =
        keccak256("CIRCUIT_BREAKER_ROLE");
    address public constant ETH_ASSET = address(0);

    address public immutable asset;
    address public immutable budgetController;
    uint256 public immutable withdrawalCooldown;

    uint8 private immutable shareDecimals;

    address public businessController;
    uint256 private accountedAssets;
    uint256 public activeBusinessRoundCount;
    uint256 public businessEscrowAssets;
    uint256 public reservedBusinessPayout;
    uint256 public unallocatedClaimableAssets;
    uint256 public totalClaimableAssets;

    bool public governanceWithdrawalsFrozen;
    bool public userRedeemsFrozen;
    bool public businessActionsFrozen;

    mapping(address => uint256) public lastDepositAt;
    mapping(address => uint256) public claimableAssets;

    event Deposited(
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event Redeemed(
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event GovernanceWithdrawal(address indexed recipient, uint256 amount);
    event BusinessControllerUpdated(
        address indexed previousController,
        address indexed newController
    );
    event BusinessRoundOpened(uint256 activeBusinessRoundCount);
    event BusinessRoundClosed(uint256 activeBusinessRoundCount);
    event BusinessAssetsReceived(
        address indexed payer,
        uint256 amount,
        uint256 reservedPayoutAmount
    );
    event BusinessPayout(
        address indexed recipient,
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount,
        int256 accountedAssetDelta
    );
    event BusinessPayoutPoolSettled(
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount,
        int256 accountedAssetDelta
    );
    event BusinessPayoutPoolRefunded(
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    );
    event BusinessPayoutAllocated(address indexed recipient, uint256 amount);
    event BusinessPayoutClaimed(
        address indexed account,
        address indexed receiver,
        uint256 amount
    );
    event BusinessPayoutReserveIncreased(
        uint256 additionalReservedPayout,
        uint256 reservedBusinessPayout
    );
    event GovernanceWithdrawalsFrozen(address indexed caller);
    event UserRedeemsFrozen(address indexed caller);
    event BusinessActionsFrozen(address indexed caller);
    event AllOutflowsFrozen(address indexed caller);
    event GovernanceWithdrawalsUnfrozen(address indexed caller);
    event UserRedeemsUnfrozen(address indexed caller);
    event BusinessActionsUnfrozen(address indexed caller);

    error InvalidAddress();
    error InvalidAmount();
    error InvalidAssetTransfer();
    error DirectEthTransferDisabled();
    error ThirdPartyDepositDisabled();
    error ShareTransferDisabled();
    error WithdrawalCooldownActive();
    error GovernanceWithdrawalsAreFrozen();
    error UserRedeemsAreFrozen();
    error BusinessActionsAreFrozen();
    error OnlyBudgetController();
    error OnlyBusinessController();
    error InvalidBusinessController();
    error EmptyAssetBase();
    error BusinessControllerAlreadySet();
    error BusinessObligationsActive();
    error NoActiveBusinessRound();
    error InsufficientAvailableAssets();
    error PayoutExceedsReserved();
    error UnallocatedPayoutExceeded();
    error ClaimableBalanceExceeded();

    constructor(
        string memory name_,
        string memory symbol_,
        address asset_,
        uint8 shareDecimals_,
        address budgetController_,
        address admin_,
        address circuitBreaker_,
        uint256 withdrawalCooldown_
    ) ERC20(name_, symbol_) {
        if (
            budgetController_ == address(0) ||
            admin_ == address(0) ||
            circuitBreaker_ == address(0)
        ) {
            revert InvalidAddress();
        }

        asset = asset_;
        shareDecimals = shareDecimals_;
        budgetController = budgetController_;
        withdrawalCooldown = withdrawalCooldown_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(CIRCUIT_BREAKER_ROLE, circuitBreaker_);
    }

    receive() external payable {
        revert DirectEthTransferDisabled();
    }

    function decimals() public view override returns (uint8) {
        return shareDecimals;
    }

    function totalAssets() public view returns (uint256) {
        return accountedAssets;
    }

    function custodiedAssets() public view returns (uint256) {
        if (asset == ETH_ASSET) {
            return address(this).balance;
        }

        return IERC20(asset).balanceOf(address(this));
    }

    function previewDeposit(uint256 amount) external view returns (uint256) {
        return _calculateShares(amount, totalAssets());
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        uint256 supply = totalSupply();
        if (shares == 0 || supply == 0) {
            return 0;
        }

        return (shares * totalAssets()) / supply;
    }

    function deposit(
        uint256 amount,
        address receiver
    ) external payable nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) {
            revert InvalidAddress();
        }
        if (receiver != msg.sender) {
            revert ThirdPartyDepositDisabled();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (_hasActiveBusinessObligations()) {
            revert BusinessObligationsActive();
        }

        uint256 preAssets;
        if (asset == ETH_ASSET) {
            if (msg.value != amount) {
                revert InvalidAssetTransfer();
            }
            preAssets = accountedAssets;
        } else {
            if (msg.value != 0) {
                revert InvalidAssetTransfer();
            }

            IERC20 token = IERC20(asset);
            preAssets = custodiedAssets();
            token.safeTransferFrom(msg.sender, address(this), amount);
            if (custodiedAssets() - preAssets != amount) {
                revert InvalidAssetTransfer();
            }
            preAssets = accountedAssets;
        }

        shares = _calculateShares(amount, preAssets);
        accountedAssets += amount;
        lastDepositAt[receiver] = block.timestamp;
        _mint(receiver, shares);

        emit Deposited(msg.sender, receiver, amount, shares);
    }

    function redeem(
        uint256 shares,
        address receiver
    ) external nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) {
            revert InvalidAddress();
        }
        if (shares == 0) {
            revert InvalidAmount();
        }
        if (userRedeemsFrozen) {
            revert UserRedeemsAreFrozen();
        }
        if (block.timestamp < lastDepositAt[msg.sender] + withdrawalCooldown) {
            revert WithdrawalCooldownActive();
        }
        if (_hasActiveBusinessObligations()) {
            revert BusinessObligationsActive();
        }

        uint256 supply = totalSupply();
        assets = (shares * accountedAssets) / supply;
        if (assets == 0) {
            revert InvalidAmount();
        }

        accountedAssets -= assets;
        _burn(msg.sender, shares);
        _transferAsset(receiver, assets);

        emit Redeemed(msg.sender, receiver, assets, shares);
    }

    function withdrawByBudget(
        address recipient,
        uint256 amount
    ) external nonReentrant {
        if (msg.sender != budgetController) {
            revert OnlyBudgetController();
        }
        if (recipient == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (governanceWithdrawalsFrozen) {
            revert GovernanceWithdrawalsAreFrozen();
        }
        if (_hasActiveBusinessObligations()) {
            revert BusinessObligationsActive();
        }
        if (amount > accountedAssets) {
            revert InsufficientAvailableAssets();
        }

        accountedAssets -= amount;
        _transferAsset(recipient, amount);
        emit GovernanceWithdrawal(recipient, amount);
    }

    function setBusinessController(
        address newController
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newController == address(0)) {
            revert InvalidAddress();
        }
        if (newController.code.length == 0) {
            revert InvalidBusinessController();
        }
        if (businessController != address(0)) {
            revert BusinessControllerAlreadySet();
        }
        IJudgmentObligationController controller = IJudgmentObligationController(
                newController
            );
        if (
            controller.poolVault() != address(this) ||
            controller.asset() != asset
        ) {
            revert InvalidBusinessController();
        }

        address previousController = businessController;
        businessController = newController;

        emit BusinessControllerUpdated(previousController, newController);
    }

    function openBusinessRound() external nonReentrant onlyBusinessController {
        activeBusinessRoundCount += 1;
        emit BusinessRoundOpened(activeBusinessRoundCount);
    }

    function closeBusinessRound() external nonReentrant onlyBusinessController {
        if (activeBusinessRoundCount == 0) {
            revert NoActiveBusinessRound();
        }
        activeBusinessRoundCount -= 1;
        emit BusinessRoundClosed(activeBusinessRoundCount);
    }

    function receiveBusinessEth(
        uint256 amount,
        uint256 reservedPayoutAmount
    ) external payable nonReentrant onlyBusinessController {
        if (asset != ETH_ASSET) {
            revert InvalidAssetTransfer();
        }
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (amount == 0 || msg.value != amount) {
            revert InvalidAmount();
        }
        if (totalSupply() == 0 || accountedAssets == 0) {
            revert EmptyAssetBase();
        }
        businessEscrowAssets += amount;
        reservedBusinessPayout += reservedPayoutAmount;
        _enforceBusinessPayoutSolvency();

        emit BusinessAssetsReceived(msg.sender, amount, reservedPayoutAmount);
    }

    function receiveBusinessAssetFrom(
        address payer,
        uint256 amount,
        uint256 reservedPayoutAmount
    ) external nonReentrant onlyBusinessController {
        if (asset == ETH_ASSET) {
            revert InvalidAssetTransfer();
        }
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (payer == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (totalSupply() == 0 || accountedAssets == 0) {
            revert EmptyAssetBase();
        }
        IERC20 token = IERC20(asset);
        uint256 preAssets = custodiedAssets();
        token.safeTransferFrom(payer, address(this), amount);
        if (custodiedAssets() - preAssets != amount) {
            revert InvalidAssetTransfer();
        }

        businessEscrowAssets += amount;
        reservedBusinessPayout += reservedPayoutAmount;
        _enforceBusinessPayoutSolvency();

        emit BusinessAssetsReceived(payer, amount, reservedPayoutAmount);
    }

    function increaseBusinessPayoutReserve(
        uint256 additionalReservedPayout
    ) external nonReentrant onlyBusinessController {
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (additionalReservedPayout == 0) {
            revert InvalidAmount();
        }

        reservedBusinessPayout += additionalReservedPayout;
        _enforceBusinessPayoutSolvency();

        emit BusinessPayoutReserveIncreased(
            additionalReservedPayout,
            reservedBusinessPayout
        );
    }

    function businessPayout(
        address recipient,
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    ) external nonReentrant onlyBusinessController {
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (recipient == address(0)) {
            revert InvalidAddress();
        }
        if (receivedAmount == 0) {
            revert InvalidAmount();
        }
        if (payoutAmount > reservedPayoutAmount) {
            revert PayoutExceedsReserved();
        }
        if (
            receivedAmount > businessEscrowAssets ||
            reservedPayoutAmount > reservedBusinessPayout
        ) {
            revert PayoutExceedsReserved();
        }

        businessEscrowAssets -= receivedAmount;
        reservedBusinessPayout -= reservedPayoutAmount;

        int256 accountedAssetDelta;
        if (payoutAmount > receivedAmount) {
            uint256 vaultLoss = payoutAmount - receivedAmount;
            if (vaultLoss > accountedAssets) {
                revert InsufficientAvailableAssets();
            }
            accountedAssets -= vaultLoss;
            accountedAssetDelta = -int256(vaultLoss);
        } else {
            uint256 vaultProfit = receivedAmount - payoutAmount;
            accountedAssets += vaultProfit;
            accountedAssetDelta = int256(vaultProfit);
        }

        if (payoutAmount > 0) {
            claimableAssets[recipient] += payoutAmount;
            totalClaimableAssets += payoutAmount;
        }
        emit BusinessPayout(
            recipient,
            payoutAmount,
            receivedAmount,
            reservedPayoutAmount,
            accountedAssetDelta
        );
    }

    function settleBusinessPayoutPool(
        uint256 payoutAmount,
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    ) external nonReentrant onlyBusinessController {
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (receivedAmount == 0) {
            revert InvalidAmount();
        }
        if (payoutAmount > reservedPayoutAmount) {
            revert PayoutExceedsReserved();
        }
        if (
            receivedAmount > businessEscrowAssets ||
            reservedPayoutAmount > reservedBusinessPayout
        ) {
            revert PayoutExceedsReserved();
        }

        businessEscrowAssets -= receivedAmount;
        reservedBusinessPayout -= reservedPayoutAmount;

        int256 accountedAssetDelta;
        if (payoutAmount > receivedAmount) {
            uint256 vaultLoss = payoutAmount - receivedAmount;
            if (vaultLoss > accountedAssets) {
                revert InsufficientAvailableAssets();
            }
            accountedAssets -= vaultLoss;
            accountedAssetDelta = -int256(vaultLoss);
        } else {
            uint256 vaultProfit = receivedAmount - payoutAmount;
            accountedAssets += vaultProfit;
            accountedAssetDelta = int256(vaultProfit);
        }

        if (payoutAmount > 0) {
            unallocatedClaimableAssets += payoutAmount;
            totalClaimableAssets += payoutAmount;
        }

        emit BusinessPayoutPoolSettled(
            payoutAmount,
            receivedAmount,
            reservedPayoutAmount,
            accountedAssetDelta
        );
    }

    function refundBusinessPayoutPool(
        uint256 receivedAmount,
        uint256 reservedPayoutAmount
    ) external nonReentrant onlyBusinessController {
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (receivedAmount == 0) {
            revert InvalidAmount();
        }
        if (
            receivedAmount > businessEscrowAssets ||
            reservedPayoutAmount > reservedBusinessPayout
        ) {
            revert PayoutExceedsReserved();
        }

        businessEscrowAssets -= receivedAmount;
        reservedBusinessPayout -= reservedPayoutAmount;
        unallocatedClaimableAssets += receivedAmount;
        totalClaimableAssets += receivedAmount;

        emit BusinessPayoutPoolSettled(
            receivedAmount,
            receivedAmount,
            reservedPayoutAmount,
            0
        );
        emit BusinessPayoutPoolRefunded(receivedAmount, reservedPayoutAmount);
    }

    function allocateBusinessPayout(
        address recipient,
        uint256 amount
    ) external nonReentrant onlyBusinessController {
        _allocateBusinessPayout(recipient, amount);
    }

    function claimBusinessPayout(
        address receiver,
        uint256 amount
    ) external nonReentrant {
        _claimBusinessPayout(msg.sender, receiver, amount);
    }

    function allocateAndClaimBusinessPayout(
        address recipient,
        address receiver,
        uint256 amount
    ) external nonReentrant onlyBusinessController {
        _allocateBusinessPayout(recipient, amount);
        _claimBusinessPayout(recipient, receiver, amount);
    }

    function _allocateBusinessPayout(address recipient, uint256 amount) private {
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (recipient == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (amount > unallocatedClaimableAssets) {
            revert UnallocatedPayoutExceeded();
        }

        unallocatedClaimableAssets -= amount;
        claimableAssets[recipient] += amount;

        emit BusinessPayoutAllocated(recipient, amount);
    }

    function _claimBusinessPayout(
        address account,
        address receiver,
        uint256 amount
    ) private {
        if (businessActionsFrozen) {
            revert BusinessActionsAreFrozen();
        }
        if (account == address(0) || receiver == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (amount > claimableAssets[account]) {
            revert ClaimableBalanceExceeded();
        }

        claimableAssets[account] -= amount;
        totalClaimableAssets -= amount;
        _transferAsset(receiver, amount);

        emit BusinessPayoutClaimed(account, receiver, amount);
    }

    function freezeGovernanceWithdrawals()
        external
        onlyRole(CIRCUIT_BREAKER_ROLE)
    {
        governanceWithdrawalsFrozen = true;
        emit GovernanceWithdrawalsFrozen(msg.sender);
    }

    function freezeUserRedeems() external onlyRole(CIRCUIT_BREAKER_ROLE) {
        userRedeemsFrozen = true;
        emit UserRedeemsFrozen(msg.sender);
    }

    function freezeBusinessActions() external onlyRole(CIRCUIT_BREAKER_ROLE) {
        businessActionsFrozen = true;
        emit BusinessActionsFrozen(msg.sender);
    }

    function freezeAllOutflows() external onlyRole(CIRCUIT_BREAKER_ROLE) {
        governanceWithdrawalsFrozen = true;
        userRedeemsFrozen = true;
        businessActionsFrozen = true;
        emit AllOutflowsFrozen(msg.sender);
    }

    function unfreezeGovernanceWithdrawals()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        governanceWithdrawalsFrozen = false;
        emit GovernanceWithdrawalsUnfrozen(msg.sender);
    }

    function unfreezeUserRedeems() external onlyRole(DEFAULT_ADMIN_ROLE) {
        userRedeemsFrozen = false;
        emit UserRedeemsUnfrozen(msg.sender);
    }

    function unfreezeBusinessActions() external onlyRole(DEFAULT_ADMIN_ROLE) {
        businessActionsFrozen = false;
        emit BusinessActionsUnfrozen(msg.sender);
    }

    function _calculateShares(
        uint256 amount,
        uint256 preAssets
    ) private view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return amount;
        }
        if (preAssets == 0) {
            revert EmptyAssetBase();
        }

        uint256 shares = (amount * supply) / preAssets;
        if (shares == 0) {
            revert InvalidAmount();
        }

        return shares;
    }

    function _transferAsset(address recipient, uint256 amount) private {
        if (asset == ETH_ASSET) {
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) {
                revert InvalidAssetTransfer();
            }
        } else {
            IERC20(asset).safeTransfer(recipient, amount);
        }
    }

    modifier onlyBusinessController() {
        if (msg.sender != businessController) {
            revert OnlyBusinessController();
        }
        _;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (from != address(0) && to != address(0)) {
            revert ShareTransferDisabled();
        }
    }

    function _hasActiveBusinessObligations() private view returns (bool) {
        return
            activeBusinessRoundCount != 0 ||
            businessEscrowAssets != 0 ||
            reservedBusinessPayout != 0;
    }

    function _enforceBusinessPayoutSolvency() private view {
        if (reservedBusinessPayout > accountedAssets + businessEscrowAssets) {
            revert InsufficientAvailableAssets();
        }
    }
}
