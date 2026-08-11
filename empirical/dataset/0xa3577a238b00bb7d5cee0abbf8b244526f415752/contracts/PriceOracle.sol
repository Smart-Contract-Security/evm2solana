// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

error InvalidAddress(string); // dev: Address cannot be zero
error PriceCantBeZero(); // dev: Price cannot be zero

/**
 * @title PriceOracle Contract
 * @notice This contract is used to get/set the price of nvTokens.
 * @dev This contract handles getting/setting the price of nvTokens.
 * @author NU Blockchain Technologies
 */
contract PriceOracle is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlEnumerableUpgradeable
{
    // --- Constants ---
    /// @dev Role identifier for pricing.
    bytes32 public constant PRICING_ROLE = keccak256("PRICING_ROLE");

    // --- State Variables ---

    /// @notice The current price of nvToken.
    uint256 private currentPrice;

    /// @notice The timestamp when the price was last updated.
    uint256 public lastUpdated;

    // --- Events ---

    /**
     * @notice Emitted when the price is initialized.
     */
    event PriceOracleInitialized();

    /**
     * @notice Emitted when the price is set.
     * @param price The new price of nvToken.
     */
    event PriceSet(uint256 price);

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice constructor
    constructor() {
        _disableInitializers();
    }

    // --- Initializer ---

    /**
     * @notice Initializes the contract.
     * @dev Can only be called once during contract deployment.
     */
    function initialize() external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender); // Ownable2Step uses this internal call
        __AccessControlEnumerable_init();

        emit PriceOracleInitialized();
    }

    // --- Public Functions ---

    /**
     * @notice Grants the PRICING_ROLE to a specified address.
     * @param _pricer The address to be granted the PRICING_ROLE.
     */
    function addPricing(address _pricer) external onlyOwner {
        if (_pricer == address(0)) revert InvalidAddress("pricer");
        _grantRole(PRICING_ROLE, _pricer);
    }

    /**
     * @notice Revokes the PRICING_ROLE from a specified address.
     * @param _pricer The address to have the PRICING_ROLE revoked.
     */
    function removePricing(address _pricer) external onlyOwner {
        if (_pricer == address(0)) revert InvalidAddress("pricer");
        _revokeRole(PRICING_ROLE, _pricer);
    }

    /**
     * @notice Set the current price.
     * @dev Can only be called by the pricing role.
     * @param _price The new price.
     */
    function setCgPricePerShare(
        uint256 _price
    ) external onlyRole(PRICING_ROLE) {
        if (_price == 0) revert PriceCantBeZero();

        lastUpdated = block.timestamp;
        currentPrice = _price;

        emit PriceSet(_price);
    }

    /**
     * @dev This is the exact function CoinGecko will track via `eth_call`.
     * @return The current virtual price of the token.
     */
    function cgPricePerShare() external view returns (uint256) {
        return currentPrice;
    }

    // --- Private Helper Functions ---

    // --- Upgrade Safety ---
    // 2 slots used: currentPrice, lastUpdated
    uint256[48] private __gap;

    /**
     * @notice Authorizes a contract upgrade.
     * @dev Only callable by the owner.
     * @param newImplementation Address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        // Upgrade authorized
    }
}
