// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StablecoinSwap is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    uint8 public immutable decimalsA;
    uint8 public immutable decimalsB;

    uint256 public buyRateAtoB; // Rate for buying tokenB with tokenA (e.g., 995000 = 0.995)
    uint256 public sellRateBtoA; // Rate for selling tokenB to get tokenA (e.g., 995000 = 0.995)
    uint256 public constant RATE_PRECISION = 1e6;

    address public treasuryAddress;

    mapping(address => bool) public isSpenderWhitelisted;
    mapping(address => bool) public isRecipientWhitelisted;

    event Swap(
        address indexed sender,
        address indexed recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event RatesUpdated(uint256 newBuyRate, uint256 newSellRate);
    event TreasuryAddressUpdated(address newTreasury);
    event SpenderWhitelisted(address indexed spender, bool status);
    event RecipientWhitelisted(address indexed recipient, bool status);
    event TreasuryWithdrawal(address indexed token, uint256 amount, address indexed to);

    constructor(
        address _tokenA,
        address _tokenB,
        uint256 _buyRateAtoB,
        uint256 _sellRateBtoA,
        address _treasuryAddress
    ) {
        require(_tokenA != address(0), "Invalid tokenA address");
        require(_tokenB != address(0), "Invalid tokenB address");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_buyRateAtoB > 0 && _buyRateAtoB <= RATE_PRECISION, "Invalid buy rate");
        require(_sellRateBtoA > 0 && _sellRateBtoA <= RATE_PRECISION, "Invalid sell rate");
        require(_treasuryAddress != address(0), "Invalid treasury address");

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        decimalsA = IERC20Metadata(_tokenA).decimals();
        decimalsB = IERC20Metadata(_tokenB).decimals();
        buyRateAtoB = _buyRateAtoB;
        sellRateBtoA = _sellRateBtoA;
        treasuryAddress = _treasuryAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TREASURER_ROLE, msg.sender);
    }

    function swap(address tokenIn, uint256 amountIn, address recipient)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "Amount must be greater than 0");
        require(recipient != address(0), "Invalid recipient");
        require(
            isSpenderWhitelisted[msg.sender] || isRecipientWhitelisted[recipient],
            "Neither sender nor recipient is whitelisted"
        );

        address tokenOut;
        uint256 rate;

        if (tokenIn == address(tokenA)) {
            tokenOut = address(tokenB);
            rate = buyRateAtoB;
        } else if (tokenIn == address(tokenB)) {
            tokenOut = address(tokenA);
            rate = sellRateBtoA;
        } else {
            revert("Invalid token");
        }

        amountOut = _calculateAmountOut(tokenIn, amountIn, rate);
        require(amountOut > 0, "Output amount too small");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit Swap(msg.sender, recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function setRates(uint256 _buyRateAtoB, uint256 _sellRateBtoA) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_buyRateAtoB > 0 && _buyRateAtoB <= RATE_PRECISION, "Invalid buy rate");
        require(_sellRateBtoA > 0 && _sellRateBtoA <= RATE_PRECISION, "Invalid sell rate");

        buyRateAtoB = _buyRateAtoB;
        sellRateBtoA = _sellRateBtoA;

        emit RatesUpdated(_buyRateAtoB, _sellRateBtoA);
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        treasuryAddress = _treasuryAddress;
        emit TreasuryAddressUpdated(_treasuryAddress);
    }

    function setSpenderWhitelist(address spender, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isSpenderWhitelisted[spender] = status;
        emit SpenderWhitelisted(spender, status);
    }

    function setRecipientWhitelist(address recipient, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isRecipientWhitelisted[recipient] = status;
        emit RecipientWhitelisted(recipient, status);
    }

    function withdrawToTreasury(address token, uint256 amount) external onlyRole(TREASURER_ROLE) {
        require(token == address(tokenA) || token == address(tokenB), "Invalid token");
        require(amount > 0, "Amount must be greater than 0");

        IERC20(token).safeTransfer(treasuryAddress, amount);
        emit TreasuryWithdrawal(token, amount, treasuryAddress);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256) {
        if (tokenIn == address(tokenA)) {
            return _calculateAmountOut(tokenIn, amountIn, buyRateAtoB);
        } else if (tokenIn == address(tokenB)) {
            return _calculateAmountOut(tokenIn, amountIn, sellRateBtoA);
        } else {
            revert("Invalid token");
        }
    }

    function _calculateAmountOut(address tokenIn, uint256 amountIn, uint256 rate) internal view returns (uint256) {
        if (tokenIn == address(tokenA)) {
            // Converting from tokenA to tokenB
            if (decimalsA == decimalsB) {
                return (amountIn * rate) / RATE_PRECISION;
            } else if (decimalsA > decimalsB) {
                // Scale down (e.g., 18 decimals to 6 decimals)
                uint256 scaleFactor = 10 ** (decimalsA - decimalsB);
                return (amountIn * rate) / (RATE_PRECISION * scaleFactor);
            } else {
                // Scale up (e.g., 6 decimals to 18 decimals)
                uint256 scaleFactor = 10 ** (decimalsB - decimalsA);
                return (amountIn * rate * scaleFactor) / RATE_PRECISION;
            }
        } else {
            // Converting from tokenB to tokenA
            if (decimalsA == decimalsB) {
                return (amountIn * rate) / RATE_PRECISION;
            } else if (decimalsB > decimalsA) {
                // Scale down (e.g., 18 decimals to 6 decimals)
                uint256 scaleFactor = 10 ** (decimalsB - decimalsA);
                return (amountIn * rate) / (RATE_PRECISION * scaleFactor);
            } else {
                // Scale up (e.g., 6 decimals to 18 decimals)
                uint256 scaleFactor = 10 ** (decimalsA - decimalsB);
                return (amountIn * rate * scaleFactor) / RATE_PRECISION;
            }
        }
    }
}
