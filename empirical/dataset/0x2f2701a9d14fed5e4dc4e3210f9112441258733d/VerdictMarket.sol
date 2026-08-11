// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/**
 * @dev Interface for standard ERC20 token (USDC)
 */
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
/**
 * @title VerdictMarket
 * @author Verdict Protocol
 * @notice Binary prediction market settled in USDC on Base, featuring ERC-8021 transaction attribution.
 */
contract VerdictMarket {
    
    // Custom Structs
    struct MarketDetails {
        string title;
        string description;
        string resolutionSource;
        uint256 expirationTime;
        bool resolved;
        bool yesWins;
    }
    // State Variables
    IERC20 public immutable usdcToken;
    address public immutable factoryAddress;
    address public oracleAddress;
    
    MarketDetails public details;
    
    // Total shares pool values
    uint256 public totalYesShares;
    uint256 public totalNoShares;
    uint256 public totalUsdcLocked;
    
    // User shares ledger
    mapping(address => uint256) public userYesShares;
    mapping(address => uint256) public userNoShares;
    mapping(address => uint256) public userInvestedUsdc;
    // Events
    event TradeExecuted(address indexed trader, bool indexed isYes, uint256 usdcSpent, uint256 sharesMinted, string builderCode);
    event MarketResolved(bool indexed yesWins, uint256 totalPayout);
    event PayoutClaimed(address indexed trader, uint256 usdcClaimed);
    modifier onlyOracleOrFactory() {
        require(msg.sender == oracleAddress || msg.sender == factoryAddress, "VerdictMarket: Unauthorized caller");
        _;
    }
    modifier beforeExpiration() {
        require(block.timestamp < details.expirationTime, "VerdictMarket: Market has expired");
        _;
    }
    modifier afterResolution() {
        require(details.resolved, "VerdictMarket: Market not resolved yet");
        _;
    }
    /**
     * @param _usdcAddress The ERC20 address of USDC on Base mainnet (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
     * @param _title Question being predicted
     * @param _description Strict rules criteria
     * @param _resolutionSource Trusted reference news source
     * @param _expirationTime Unix timestamp of expiration
     * @param _oracle The designated oracle consensus key
     */
    constructor(
        address _usdcAddress,
        string memory _title,
        string memory _description,
        string memory _resolutionSource,
        uint256 _expirationTime,
        address _oracle
    ) {
        require(_expirationTime > block.timestamp, "VerdictMarket: Expiration must be future time");
        usdcToken = IERC20(_usdcAddress);
        factoryAddress = msg.sender;
        oracleAddress = _oracle;
        
        details = MarketDetails({
            title: _title,
            description: _description,
            resolutionSource: _resolutionSource,
            expirationTime: _expirationTime,
            resolved: false,
            yesWins: false
        });
    }
    /**
     * @notice Purchase YES or NO shares using USDC.
     * @dev Automatically parses the calldata to decode ERC-8021 builder code strings.
     * @param _usdcAmount Amount of USDC to spend (6 decimal places)
     * @param _buyYes True to buy YES shares, False to buy NO shares
     */
    function buyShares(uint256 _usdcAmount, bool _buyYes) external beforeExpiration {
        require(_usdcAmount > 0, "VerdictMarket: Zero deposit amount");
        
        // Transfer USDC from user
        bool success = usdcToken.transferFrom(msg.sender, address(this), _usdcAmount);
        require(success, "VerdictMarket: USDC transfer failed");
        
        // Calculate shares pricing.
        // For a production system, this uses a Constant Product Market Maker (CPMM) or LMSR.
        // Here we implement a simplified CPMM logic:
        uint256 sharesToMint = calculateSharesToMint(_usdcAmount, _buyYes);
        
        if (_buyYes) {
            userYesShares[msg.sender] += sharesToMint;
            totalYesShares += sharesToMint;
        } else {
            userNoShares[msg.sender] += sharesToMint;
            totalNoShares += sharesToMint;
        }
        
        userInvestedUsdc[msg.sender] += _usdcAmount;
        totalUsdcLocked += _usdcAmount;
        // Parse attribution suffix (ERC-8021) directly from raw calldata
        string memory builderCode = _parseAttributionCode();
        
        emit TradeExecuted(msg.sender, _buyYes, _usdcAmount, sharesToMint, builderCode);
    }
    /**
     * @notice Settle the market based on the verified real-world outcome.
     * @param _yesWins True if YES resolves as winner, False if NO wins
     */
    function resolveMarket(bool _yesWins) external onlyOracleOrFactory {
        require(!details.resolved, "VerdictMarket: Already resolved");
        
        details.resolved = true;
        details.yesWins = _yesWins;
        
        emit MarketResolved(_yesWins, totalUsdcLocked);
    }
    /**
     * @notice Withdraw payouts for winning shares (1 share = 1 USDC).
     */
    function claimPayout() external afterResolution {
        uint256 payoutAmount = 0;
        
        if (details.yesWins) {
            payoutAmount = userYesShares[msg.sender];
            userYesShares[msg.sender] = 0;
        } else {
            payoutAmount = userNoShares[msg.sender];
            userNoShares[msg.sender] = 0;
        }
        
        require(payoutAmount > 0, "VerdictMarket: No winning shares or already claimed");
        
        // Payout winning balance (in production, includes platform fees deduction)
        bool success = usdcToken.transfer(msg.sender, payoutAmount);
        require(success, "VerdictMarket: Payout transfer failed");
        
        emit PayoutClaimed(msg.sender, payoutAmount);
    }
    /**
     * @dev Simplified Constant Product shares calculation.
     * YES price = y / (y + n), NO price = n / (y + n).
     */
    function calculateSharesToMint(uint256 _usdcSpent, bool _isYes) public view returns (uint256) {
        // Initial fallback if pool is empty: 1 USDC = 2 shares (average $0.50 price)
        if (totalYesShares == 0 && totalNoShares == 0) {
            return _usdcSpent * 2;
        }
        
        uint256 yesPool = totalYesShares;
        uint256 noPool = totalNoShares;
        
        if (_isYes) {
            uint256 price = (yesPool * 1e18) / (yesPool + noPool);
            return (_usdcSpent * 1e18) / price;
        } else {
            uint256 price = (noPool * 1e18) / (yesPool + noPool);
            return (_usdcSpent * 1e18) / price;
        }
    }
    /**
     * @dev Internal helper to parse the ERC-8021 suffix from the raw msg.data.
     * Layout of EIP-8021 suffix at the end of msg.data:
     * [builder_code_ascii_bytes] + [code_length_byte (1 byte)] + [schema_id_byte (1 byte)] + [erc_marker_16_bytes (16 bytes)]
     */
    function _parseAttributionCode() internal pure returns (string memory) {
        uint256 len = msg.data.length;
        
        // ERC-8021 suffix requires at least 18 bytes (16 marker + 1 schema + 1 length)
        if (len < 18) {
            return "direct_rpc";
        }
        
        // Extract the last 16 bytes and verify the ERC marker: 0x80218021802180218021802180218021
        bytes16 marker;
        assembly {
            marker := calldataload(sub(len, 16))
        }
        
        if (marker != 0x80218021802180218021802180218021) {
            return "direct_rpc"; // No ERC-8021 suffix detected
        }
        
        // Read Schema ID (located 17 bytes from end)
        uint8 schemaId = uint8(msg.data[len - 17]);
        
        // Read Builder Code length in bytes (located 18 bytes from end)
        uint8 codeLen = uint8(msg.data[len - 18]);
        
        if (codeLen == 0 || len < 18 + codeLen) {
            return "direct_rpc";
        }
        
        // Extract ASCII bytes and convert to a memory string
        bytes memory codeBytes = new bytes(codeLen);
        uint256 startOffset = len - 18 - codeLen;
        for (uint256 i = 0; i < codeLen; i++) {
            codeBytes[i] = msg.data[startOffset + i];
        }
        
        return string(codeBytes);
    }
}