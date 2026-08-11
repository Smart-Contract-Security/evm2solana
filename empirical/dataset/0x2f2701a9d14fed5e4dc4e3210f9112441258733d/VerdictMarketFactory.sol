// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./VerdictMarket.sol";
/**
 * @title VerdictMarketFactory
 * @author Verdict Protocol
 * @notice Factory contract to deploy and track individual prediction markets on Base mainnet.
 */
contract VerdictMarketFactory {
    
    // State variables
    address public owner;
    address public immutable usdcTokenAddress;
    address[] public allMarkets;
    
    // Mapping to verify if a market was deployed by this factory
    mapping(address => bool) public isVerdictMarket;
    event MarketCreated(
        address indexed marketAddress, 
        string title, 
        uint256 expirationTime, 
        address indexed oracle
    );
    modifier onlyOwner() {
        require(msg.sender == owner, "VerdictMarketFactory: Only owner can call");
        _;
    }
    /**
     * @param _usdcAddress Core USDC ERC20 contract address on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
     */
    constructor(address _usdcAddress) {
        require(_usdcAddress != address(0), "VerdictMarketFactory: Zero address invalid");
        owner = msg.sender;
        usdcTokenAddress = _usdcAddress;
    }
    /**
     * @notice Deploy a new prediction market contract.
     * @param _title Question being predicted
     * @param _description Rules of resolution
     * @param _resolutionSource News source or API
     * @param _expirationTime Expiration timestamp
     * @param _oracle Authorized resolution oracle address
     */
    function createMarket(
        string memory _title,
        string memory _description,
        string memory _resolutionSource,
        uint256 _expirationTime,
        address _oracle
    ) external onlyOwner returns (address) {
        
        // Deploy new VerdictMarket contract instance
        VerdictMarket newMarket = new VerdictMarket(
            usdcTokenAddress,
            _title,
            _description,
            _resolutionSource,
            _expirationTime,
            _oracle
        );
        
        address marketAddr = address(newMarket);
        allMarkets.push(marketAddr);
        isVerdictMarket[marketAddr] = true;
        
        emit MarketCreated(marketAddr, _title, _expirationTime, _oracle);
        
        return marketAddr;
    }
    /**
     * @notice Returns the list of all prediction markets created.
     */
    function getMarkets() external view returns (address[] memory) {
        return allMarkets;
    }
    /**
     * @notice Returns the total count of deployed markets.
     */
    function getMarketsCount() external view returns (uint256) {
        return allMarkets.length;
    }
    /**
     * @notice Transfer owner permissions.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "VerdictMarketFactory: New owner cannot be zero");
        owner = _newOwner;
    }
}
