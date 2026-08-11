// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract Web3AudioSplit {

    // ── State ────────────────────────────────────────────────────────────
    address public platform;
    bool private locked;
    uint256 public constant MAX_SELLERS = 20;      // gas limit protection
    uint256 public constant PLATFORM_FEE_BPS = 800; // 8% in basis points (800/10000)

    // ── Events ───────────────────────────────────────────────────────────
    event SellerPaid(address indexed seller, uint256 amount);
    event PlatformPaid(address indexed platform, uint256 amount);
    event PlatformUpdated(address indexed oldPlatform, address indexed newPlatform);

    // ── Constructor ──────────────────────────────────────────────────────
    constructor(address _platform) {
        require(_platform != address(0), "Invalid platform address");
        platform = _platform;
    }

    // ── Modifiers ────────────────────────────────────────────────────────
    modifier noReentrant() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    // ── Admin ────────────────────────────────────────────────────────────
    function updatePlatform(address _newPlatform) external {
        require(msg.sender == platform, "Only platform can update");
        require(_newPlatform != address(0), "Invalid address");
        emit PlatformUpdated(platform, _newPlatform);
        platform = _newPlatform;
    }

    // ── Main Function ────────────────────────────────────────────────────
    function payMultiple(
        address[] calldata sellers,
        uint256[] calldata amounts,
        uint256 deadline
    ) external payable noReentrant {

        // Deadline check
        require(block.timestamp <= deadline, "Transaction expired");

        // Array validation
        require(sellers.length == amounts.length, "Mismatched arrays");
        require(sellers.length > 0, "Empty arrays");
        require(sellers.length <= MAX_SELLERS, "Too many sellers");

        // Verify exact ETH sent matches sum of amounts
        uint256 total = 0;
        for(uint256 i = 0; i < amounts.length; i++){
            require(sellers[i] != address(0), "Invalid seller address");
            require(amounts[i] > 0, "Zero amount not allowed");
            total += amounts[i];
        }
        require(msg.value == total, "ETH amount mismatch");

        // Pay each seller (92%) and accumulate platform fee
        // Uses basis points (800/10000) to avoid integer truncation
        uint256 platformTotal = 0;

        for(uint256 i = 0; i < sellers.length; i++){
            uint256 platformFee = (amounts[i] * PLATFORM_FEE_BPS) / 10000;
            uint256 sellerAmount = amounts[i] - platformFee;
            platformTotal += platformFee;

            (bool sent,) = payable(sellers[i]).call{value: sellerAmount}("");
            require(sent, "Seller transfer failed");
            emit SellerPaid(sellers[i], sellerAmount);
        }

        // Pay platform in one transfer after all sellers succeed
        (bool platformSent,) = payable(platform).call{value: platformTotal}("");
        require(platformSent, "Platform transfer failed");
        emit PlatformPaid(platform, platformTotal);
    }
}