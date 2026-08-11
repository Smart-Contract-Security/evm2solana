@program_id("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") interface IERC20 {
    function transferFrom(address from, address to, uint64 value) external returns (bool);
}

contract EVMBridgeSubscription {
    address public owner;

    event SubscriptionProcessed(
        address user, 
        address targetBridge, 
        uint64 amount
    );

    @payer(payer)
    @space(512)
    @seed("owner")
    constructor(address payer) {
        owner = payer;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "Not the contract owner");
        _;
    }

    function executeSync(
        address tokenAddress,
        address fromUser,
        address toBridgeC,
        uint64 amount
    ) external onlyOwner returns (bool) {
        require(tokenAddress != address(0), "Invalid token address");
        require(fromUser != address(0), "Invalid user address");
        require(toBridgeC != address(0), "Invalid bridge address");
        require(amount > 0, "Amount must be greater than 0");

        (bool success, ) = tokenAddress.call{program_id: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"}(abi.encodeWithSignature("transferFrom(address,address,uint64)", fromUser, toBridgeC, amount));
        require(success, "Token transfer failed");

        emit SubscriptionProcessed(fromUser, toBridgeC, amount);
        return true;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }
}