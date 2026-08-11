// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title VSTONE
 * @dev ERC20 token contract for vSTONE
 * @notice Allows users to purchase vSTONE tokens with ETH and later claim STONE tokens
 */
contract VSTONE is ERC20, ERC20Burnable, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20Metadata;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Token configuration
    IERC20Metadata public stoneContract;
    uint256 public immutable maxSupply;
    uint256 public price;
    
    // Sale configuration
    uint256 public constant EXP = 1e18;
    uint256 public constant MAX_BUY = 3e18;
    
    // Financial configuration
    address private beneficiary;
    mapping(address => uint256) private purchaseAmount;

    // Custom errors
    error MaxSupplyExceeded();
    error MaxBuyExceeded();
    error InsufficientPayment();
    error StoneContractNotSet();
    error TransferFailed();
    error InvalidBeneficiary();
    error InvalidPrice();
    error NoTokensToRedeem();

    // Events
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 ethPaid);
    event STONEClaimed(address indexed claimer, uint256 amount);
    event StoneContractSet(address indexed stoneContract);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);

    /**
     * @dev Constructor to initialize the VSTONE token
     * @param _admin Address that will have admin role
     * @param _maxCap Maximum sale supply cap
     * @param _price Price per token in wei
     * @param _beneficiary Address to receive ETH payments
     */
    constructor(
        address _admin,
        uint256 _maxCap,
        uint256 _price,
        address _beneficiary
    ) ERC20("vSTONE", "vSTONE") {
        if (_admin == address(0) || _beneficiary == address(0)) {
            revert InvalidBeneficiary();
        }
        if (_price == 0) {
            revert InvalidPrice();
        }

        maxSupply = _maxCap * EXP;
        price = _price;
        beneficiary = _beneficiary;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @notice Set the STONE token contract address
     * @dev Only admin can call this function
     * @param token Address of the STONE token contract
     */
    function setStoneContract(IERC20Metadata token) external onlyRole(ADMIN_ROLE) {
        if (address(token) == address(0)) {
            revert InvalidBeneficiary();
        }
        stoneContract = token;
        emit StoneContractSet(address(token));
    }

    /**
     * @notice Update the price per vSTONE token
     * @dev Only admin can call this function
     * @param newPrice New price in wei (should be scaled by EXP)
     */
    function setPrice(uint256 newPrice) external onlyRole(ADMIN_ROLE) {
        if (newPrice == 0) {
            revert InvalidPrice();
        }
        uint256 oldPrice = price;
        price = newPrice;
        emit PriceUpdated(oldPrice, newPrice);
    }

    /**
     * @notice Update the beneficiary address
     * @dev Only admin can call this function
     * @param newBeneficiary New beneficiary address
     */
    function setBeneficiary(address newBeneficiary) external onlyRole(ADMIN_ROLE) {
        if (newBeneficiary == address(0)) {
            revert InvalidBeneficiary();
        }
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    /**
     * @notice Get the total ETH amount purchased by a buyer
     * @param buyer Address of the buyer
     * @return Total ETH amount purchased
     */
    function getPurchaseAmount(address buyer) external view returns (uint256) {
        return purchaseAmount[buyer];
    }

    /**
     * @notice Pause the contract
     * @dev Only pauser role can call this function
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only pauser role can call this function
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Purchase vSTONE tokens with ETH
     * @dev Tokens can only be purchased during the sale period and within limits
     * @param amount Number of tokens to purchase (in wei, scaled by EXP)
     */
    function buy(uint256 amount) external payable nonReentrant whenNotPaused {
        if (totalSupply() + amount > maxSupply) {
            revert MaxSupplyExceeded();
        }
        if (msg.value > MAX_BUY) {
            revert MaxBuyExceeded();
        }
        if (purchaseAmount[_msgSender()] + msg.value > MAX_BUY) {
            revert MaxBuyExceeded();
        }
        
        uint256 requiredPayment = (price * amount) / EXP;
        if (msg.value < requiredPayment) {
            revert InsufficientPayment();
        }

        // Transfer ETH to beneficiary
        (bool success, ) = payable(beneficiary).call{value: msg.value}("");
        if (!success) {
            revert TransferFailed();
        }

        // Mint tokens and update purchase tracking
        _mint(_msgSender(), amount);
        purchaseAmount[_msgSender()] += msg.value;

        emit TokensPurchased(_msgSender(), amount, msg.value);
    }

    /**
     * @notice Claim STONE tokens by burning vSTONE tokens
     * @dev Users can exchange their vSTONE tokens 1:1 for STONE tokens
     */
    function claimSTONE() external nonReentrant whenNotPaused {
        if (address(stoneContract) == address(0)) {
            revert StoneContractNotSet();
        }
        
        uint256 userBalance = balanceOf(_msgSender());
        if (userBalance == 0) {
            revert NoTokensToRedeem();
        }

        // Burn vSTONE tokens first
        _burn(_msgSender(), userBalance);
        
        // Transfer STONE tokens to user
        stoneContract.safeTransfer(_msgSender(), userBalance);

        emit STONEClaimed(_msgSender(), userBalance);
    }

    /**
     * @notice Emergency function to recover accidentally sent tokens
     * @dev Only admin can call this function
     * @param token Address of the token to recover
     * @param amount Amount to recover
     */
    function emergencyTokenRecovery(
        IERC20 token,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        SafeERC20.safeTransfer(token, _msgSender(), amount);
    }

    /**
     * @notice Emergency function to recover ETH
     * @dev Only admin can call this function
     */
    function emergencyETHRecovery() external onlyRole(ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(_msgSender()).call{value: balance}("");
            if (!success) {
                revert TransferFailed();
            }
        }
    }

    /**
     * @notice Override to prevent transfers when paused
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override whenNotPaused {
        super._update(from, to, value);
    }

    /**
     * @notice Check if the contract supports an interface
     * @param interfaceId Interface identifier
     * @return True if the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}