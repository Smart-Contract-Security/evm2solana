// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// ==========================================
// Lido Interfaces
// ==========================================
interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function stEthPerToken() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IWithdrawalQueue {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;

    function getWithdrawalStatus(uint256[] calldata _requestIds) external view returns (WithdrawalRequestStatus[] memory);
}

// ==========================================
// Main Contract
// ==========================================
contract LSD is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuard, IERC721Receiver, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public stETH;
    IWstETH public wstETH;
    address public WITHDRAWAL_QUEUE;

    address public feeRecipient;
    uint256 public performanceFeeBps; // 1000 = 10%
    uint256 public lastStEthPerToken;
    mapping(uint256 => address) public requestOwner;
    mapping(address => uint256[]) public userRequests;

    uint256 public constant MAX_PENDING_REQUESTS = 20;

    // Reserved space to prevent storage collision during upgrades
    uint256[42] private __gap;

    event Deposited(address indexed user, uint256 ethAmount, uint256 sharesMinted);
    event WithdrawalRequested(address indexed user, uint256 sharesBurned, uint256[] requestIds);
    event ETHClaimed(address indexed user, uint256 ethAmount, uint256[] requestIds);
    event FeeMinted(address indexed recipient, uint256 sharesMinted, uint256 profitInStEth);

    event AdminUnwrapped(uint256 wstEthBurned, uint256 stEthReceived);
    event AdminWithdrawalRequested(uint256 requestId, uint256 stEthAmount);
    event AdminWithdrawalClaimed(uint256[] requestIds, uint256 ethReceived);
    event AdminETHSent(address indexed to, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _feeRecipient,
        uint256 _feeBps,
        address _stETH,
        address _wstETH,
        address _withdrawalQueue
    ) public initializer {
        __ERC20_init("Cavro ETH", "roETH");
        __ERC20Permit_init("Cavro ETH");
        __Ownable_init(msg.sender);
        __Pausable_init();

        feeRecipient = _feeRecipient;
        performanceFeeBps = _feeBps;
        stETH = IERC20(_stETH);
        wstETH = IWstETH(_wstETH);
        WITHDRAWAL_QUEUE = _withdrawalQueue;
        lastStEthPerToken = wstETH.stEthPerToken();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function deposit() external payable nonReentrant whenNotPaused _harvestFee {
        require(msg.value > 0, "Zero ETH");

        uint256 totalAssets = wstETH.balanceOf(address(this));
        uint256 totalSupply_ = totalSupply();

        // ETH -> stETH
        uint256 before = stETH.balanceOf(address(this));
        IStETH(address(stETH)).submit{value: msg.value}(address(0));
        uint256 received = stETH.balanceOf(address(this)) - before;

        // stETH -> wstETH
        stETH.approve(address(wstETH), received);
        uint256 wstEthAmount = wstETH.wrap(received);

        uint256 sharesToMint = (totalSupply_ == 0)
            ? wstEthAmount
            : (wstEthAmount * totalSupply_) / totalAssets;

        _mint(msg.sender, sharesToMint);
        emit Deposited(msg.sender, msg.value, sharesToMint);
    }

    function requestWithdrawal(uint256 _shares) external nonReentrant whenNotPaused _harvestFee {
        require(balanceOf(msg.sender) >= _shares, "Not enough shares");

        uint256 totalAssets = wstETH.balanceOf(address(this));
        uint256 wstEthToUnwrap = (_shares * totalAssets) / totalSupply();

        _burn(msg.sender, _shares);

        uint256 stEthAmount = wstETH.unwrap(wstEthToUnwrap);

        IStETH(address(stETH)).approve(WITHDRAWAL_QUEUE, stEthAmount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stEthAmount;

        uint256[] memory reqIds = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, address(this));

        for (uint256 i = 0; i < reqIds.length; i++) {
            requestOwner[reqIds[i]] = msg.sender;
            userRequests[msg.sender].push(reqIds[i]);
        }

        require(userRequests[msg.sender].length <= MAX_PENDING_REQUESTS, "Too many pending requests. Please claim first.");

        emit WithdrawalRequested(msg.sender, _shares, reqIds);
    }

    function claimETH(uint256[] calldata _requestIds, uint256[] calldata _hints) external nonReentrant whenNotPaused {
        // Verify ownership
        for (uint256 i = 0; i < _requestIds.length; i++) {
            uint256 reqId = _requestIds[i];
            require(requestOwner[reqId] == msg.sender, "Not your request");

            delete requestOwner[reqId];
            _removeUserRequest(msg.sender, reqId);
        }

        // Claim from Lido
        uint256 balBefore = address(this).balance;
        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawals(_requestIds, _hints);
        uint256 ethReceived = address(this).balance - balBefore;

        // Send ETH to user
        (bool success, ) = msg.sender.call{value: ethReceived}("");
        require(success, "ETH transfer failed");

        emit ETHClaimed(msg.sender, ethReceived, _requestIds);
    }

    function _removeUserRequest(address user, uint256 reqId) internal {
        uint256[] storage requests = userRequests[user];
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i] == reqId) {
                // Optimize gas
                requests[i] = requests[requests.length - 1];
                requests.pop();
                break;
            }
        }
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function pause() external onlyOwner {
        _pause();
    }

    // Admin: unwrap wstETH held by this contract into stETH.
    // Used during the final wind-down to prepare assets for a Lido withdrawal.
    function adminUnwrapWstETH(uint256 _wstEthAmount) external onlyOwner nonReentrant returns (uint256 stEthReceived) {
        require(_wstEthAmount > 0, "Zero amount");
        uint256 before = stETH.balanceOf(address(this));
        wstETH.unwrap(_wstEthAmount);
        stEthReceived = stETH.balanceOf(address(this)) - before;
        emit AdminUnwrapped(_wstEthAmount, stEthReceived);
    }

    // Admin: submit a single Lido withdrawal request using stETH held by this contract.
    // Lido enforces a per-request max (~1000 stETH); for larger amounts, call this multiple times.
    function adminRequestWithdrawal(uint256 _stEthAmount) external onlyOwner nonReentrant returns (uint256 requestId) {
        require(_stEthAmount > 0, "Zero amount");

        IStETH(address(stETH)).approve(WITHDRAWAL_QUEUE, _stEthAmount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _stEthAmount;
        uint256[] memory reqIds = IWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdrawals(amounts, address(this));

        requestId = reqIds[0];
        emit AdminWithdrawalRequested(requestId, _stEthAmount);
    }

    // Admin: claim ETH from finalized Lido withdrawal requests owned by this contract.
    // Covers both legacy user-originated requests (this contract is the registered owner)
    // and admin-originated requests created via adminRequestWithdrawal.
    function adminClaimWithdrawal(uint256[] calldata _requestIds, uint256[] calldata _hints) external onlyOwner nonReentrant {
        uint256 balBefore = address(this).balance;
        IWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawals(_requestIds, _hints);
        uint256 ethReceived = address(this).balance - balBefore;
        emit AdminWithdrawalClaimed(_requestIds, ethReceived);
    }

    // Admin: send ETH held by this contract to any address. Used to distribute
    // recovered ETH to roETH holders off-chain.
    function adminSendETH(address payable _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "Zero address");
        require(_amount > 0, "Zero amount");
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "ETH transfer failed");
        emit AdminETHSent(_to, _amount);
    }

    function setPerformanceFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 2000, "Fee too high");
        performanceFeeBps = _feeBps;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Zero address");
        feeRecipient = _feeRecipient;
    }

    function getExchangeRate() external view returns (uint256) {
        if (totalSupply() == 0) return 1 ether;
        uint256 totalAssetsStEth = (wstETH.balanceOf(address(this)) * wstETH.stEthPerToken()) / 1 ether;
        return (totalAssetsStEth * 1 ether) / totalSupply();
    }

    function getUserPendingRequests(address _user) external view returns (uint256[] memory) {
        return userRequests[_user];
    }

    function _calculateFee() internal view returns (uint256 sharesToMint, uint256 profitInStEth, uint256 currentRate) {
        currentRate = wstETH.stEthPerToken();

        if (currentRate <= lastStEthPerToken) return (0, 0, currentRate);

        uint256 totalWstEth = wstETH.balanceOf(address(this));
        if (totalWstEth == 0 || totalSupply() == 0) return (0, 0, currentRate);

        uint256 rateDiff = currentRate - lastStEthPerToken;
        profitInStEth = (rateDiff * totalWstEth) / 1 ether;

        uint256 feeInStEth = (profitInStEth * performanceFeeBps) / 10000;
        if (feeInStEth == 0) return (0, profitInStEth, currentRate);

        uint256 totalAssetsStEth = (totalWstEth * currentRate) / 1 ether;
        sharesToMint = (feeInStEth * totalSupply()) / (totalAssetsStEth - feeInStEth);

        return (sharesToMint, profitInStEth, currentRate);
    }

    function getPendingFee() external view returns (uint256) {
        (uint256 sharesToMint, , ) = _calculateFee(); // 필요한 값(sharesToMint)만 쏙 빼서 씁니다.
        return sharesToMint;
    }

    function harvestFee() public {
        (uint256 sharesToMint, uint256 profitInStEth, uint256 currentRate) = _calculateFee();

        if (sharesToMint > 0) {
            _mint(feeRecipient, sharesToMint);
            emit FeeMinted(feeRecipient, sharesToMint, profitInStEth);
        }

        if (currentRate > lastStEthPerToken) {
            lastStEthPerToken = currentRate;
        }
    }

    modifier _harvestFee()  {
        harvestFee();
        _;
    }
}