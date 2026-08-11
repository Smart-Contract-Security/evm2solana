// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";

/**
 * @title MainframeToken
 * @dev ERC20 token with fee system, metadata management, and Uniswap liquidity integration
 */
contract MainframeToken is ERC20, ERC20Pausable, AccessControl, ReentrancyGuard {
    // Roles
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // Token constants
    uint256 public constant TOTAL_SUPPLY = 100_000 * 10**18; // 100,000 tokens
    uint256 public constant TREASURY_ALLOCATION = 500 * 10**18; // 0.5% to treasury
    uint256 public constant LIQUIDITY_ALLOCATION = 70_000 * 10**18; // 70% for liquidity

    // Fee settings
    uint256 public transferFeeRate = 200; // 2% (in basis points, 10000 = 100%)
    uint256 public constant MAX_FEE_RATE = 1000; // Maximum 10% fee
    
    // Addresses
    address public treasury;
    address public controller;
    address public immutable BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Uniswap integration
    IUniswapV2Router public uniswapRouter;
    address public uniswapPair;
    bool public liquidityLocked;
    uint256 public liquidityUnlockTime;
    uint256 public lockedLiquidityAmount;

    // Metadata
    struct TokenMetadata {
        string description;
        string logoURI;
        string website;
        string social;
    }
    
    TokenMetadata public metadata;

    // Events
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event MetadataUpdated(string field, string newValue);
    event LiquidityPoolCreated(address indexed pair, uint256 tokenAmount, uint256 ethAmount);
    event LiquidityLocked(uint256 amount, uint256 unlockTime);
    event FeeCollected(address indexed from, address indexed to, uint256 amount, uint256 fee);

    constructor(
        address _controller,
        address _treasury,
        address _uniswapRouter
    ) ERC20("Mainframe", "MAIN") {
        require(_controller != address(0), "Controller cannot be zero address");
        require(_treasury != address(0), "Treasury cannot be zero address");
        require(_uniswapRouter != address(0), "Router cannot be zero address");

        controller = _controller;
        treasury = _treasury;
        uniswapRouter = IUniswapV2Router(_uniswapRouter);

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Deployer gets admin role initially
        _grantRole(CONTROLLER_ROLE, _controller);
        _grantRole(TREASURY_ROLE, _treasury);

        // Mint total supply
        _mint(address(this), TOTAL_SUPPLY);
        
        // Transfer treasury allocation
        _transfer(address(this), treasury, TREASURY_ALLOCATION);
        
        // Transfer remaining tokens to deployer (can be burned later)
        uint256 remainingTokens = TOTAL_SUPPLY - TREASURY_ALLOCATION - LIQUIDITY_ALLOCATION;
        if (remainingTokens > 0) {
            _transfer(address(this), msg.sender, remainingTokens);
        }

        // Set initial metadata
        metadata = TokenMetadata({
            description: "Mainframe - A decentralized token with built-in fee mechanisms and locked liquidity",
            logoURI: "",
            website: "",
            social: ""
        });
    }

    /**
     * @dev Override transfer to include fee mechanism
     */
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        address owner = _msgSender();
        _transferWithFee(owner, to, amount);
        return true;
    }

    /**
     * @dev Override transferFrom to include fee mechanism
     */
    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transferWithFee(from, to, amount);
        return true;
    }

    /**
     * @dev Internal function to handle transfers with fees
     */
    function _transferWithFee(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");

        // Calculate fee (no fee for treasury or controller operations)
        uint256 fee = 0;
        if (!hasRole(TREASURY_ROLE, from) && !hasRole(CONTROLLER_ROLE, from) && 
            !hasRole(TREASURY_ROLE, to) && !hasRole(CONTROLLER_ROLE, to)) {
            fee = (amount * transferFeeRate) / 10000;
        }

        uint256 transferAmount = amount - fee;

        // Execute transfers
        if (fee > 0) {
            _transfer(from, treasury, fee);
            emit FeeCollected(from, to, amount, fee);
        }
        
        _transfer(from, to, transferAmount);
    }

    /**
     * @dev Create Uniswap pair and add liquidity (Controller only)
     */
    function createUniswapPair() external payable onlyRole(CONTROLLER_ROLE) nonReentrant {
        require(uniswapPair == address(0), "Pair already created");
        require(msg.value > 0, "ETH required for liquidity");

        // Create pair
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouter.factory());
        uniswapPair = factory.createPair(address(this), uniswapRouter.WETH());

        // Add liquidity
        _addLiquidity(LIQUIDITY_ALLOCATION, msg.value);

        emit LiquidityPoolCreated(uniswapPair, LIQUIDITY_ALLOCATION, msg.value);
    }

    /**
     * @dev Add liquidity to existing pair (Controller only)
     */
    function addLiquidity(uint256 tokenAmount) external payable onlyRole(CONTROLLER_ROLE) nonReentrant {
        require(uniswapPair != address(0), "Pair not created yet");
        require(tokenAmount > 0 && msg.value > 0, "Invalid amounts");
        require(balanceOf(address(this)) >= tokenAmount, "Insufficient contract balance");

        _addLiquidity(tokenAmount, msg.value);
    }

    /**
     * @dev Internal function to add liquidity
     */
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        // Approve tokens for router
        _approve(address(this), address(uniswapRouter), tokenAmount);

        // Add liquidity
        uniswapRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // Accept any amount of tokens
            0, // Accept any amount of ETH
            address(this), // LP tokens go to contract
            block.timestamp + 300 // 5 minute deadline
        );
    }

    /**
     * @dev Lock liquidity for specified duration (Controller only)
     */
    function lockLiquidity(uint256 duration) external onlyRole(CONTROLLER_ROLE) {
        require(uniswapPair != address(0), "Pair not created");
        require(duration > 0, "Duration must be positive");
        require(!liquidityLocked || block.timestamp >= liquidityUnlockTime, "Already locked");

        IUniswapV2Pair pair = IUniswapV2Pair(uniswapPair);
        uint256 lpBalance = pair.balanceOf(address(this));
        require(lpBalance > 0, "No LP tokens to lock");

        liquidityLocked = true;
        liquidityUnlockTime = block.timestamp + duration;
        lockedLiquidityAmount = lpBalance;

        emit LiquidityLocked(lpBalance, liquidityUnlockTime);
    }

    /**
     * @dev Update transfer fee rate (Controller only)
     */
    function setTransferFeeRate(uint256 newRate) external onlyRole(CONTROLLER_ROLE) {
        require(newRate <= MAX_FEE_RATE, "Fee rate too high");
        
        uint256 oldRate = transferFeeRate;
        transferFeeRate = newRate;
        
        emit FeeRateUpdated(oldRate, newRate);
    }

    /**
     * @dev Update metadata (Controller only)
     */
    function updateMetadata(
        string calldata description,
        string calldata logoURI,
        string calldata website,
        string calldata social
    ) external onlyRole(CONTROLLER_ROLE) {
        metadata.description = description;
        metadata.logoURI = logoURI;
        metadata.website = website;
        metadata.social = social;

        emit MetadataUpdated("description", description);
        emit MetadataUpdated("logoURI", logoURI);
        emit MetadataUpdated("website", website);
        emit MetadataUpdated("social", social);
    }

    /**
     * @dev Pause token transfers (Controller only)
     */
    function pause() external onlyRole(CONTROLLER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause token transfers (Controller only)
     */
    function unpause() external onlyRole(CONTROLLER_ROLE) {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal of collected fees (Treasury only)
     */
    function emergencyWithdraw() external onlyRole(TREASURY_ROLE) nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        payable(treasury).transfer(balance);
    }

    /**
     * @dev Burn remaining tokens (Controller only)
     */
    function burnRemainingTokens() external onlyRole(CONTROLLER_ROLE) {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance > 0) {
            _transfer(address(this), BURN_ADDRESS, contractBalance);
        }
    }

    /**
     * @dev Get liquidity info
     */
    function getLiquidityInfo() external view returns (
        address pair,
        uint256 locked,
        uint256 unlockTime,
        bool isLocked
    ) {
        return (uniswapPair, lockedLiquidityAmount, liquidityUnlockTime, liquidityLocked);
    }

    /**
     * @dev Check if liquidity is currently locked
     */
    function isLiquidityCurrentlyLocked() external view returns (bool) {
        return liquidityLocked && block.timestamp < liquidityUnlockTime;
    }

    /**
     * @dev Get current fee information
     */
    function getFeeInfo() external view returns (uint256 currentRate, uint256 maxRate) {
        return (transferFeeRate, MAX_FEE_RATE);
    }

    /**
     * @dev Required override for multiple inheritance
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }

    /**
     * @dev Allow contract to receive ETH
     */
    receive() external payable {}
}
