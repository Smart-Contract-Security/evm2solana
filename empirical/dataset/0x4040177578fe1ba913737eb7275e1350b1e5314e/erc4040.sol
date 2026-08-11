// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* 
ERC-4040 proposes a minimal ERC-20 experiment in which price discovery is treated as an unresolved state rather than a launch parameter.

The token supply is fixed. Liquidity is initialized without a target valuation model, bonding curve, or privileged market-control mechanism. The contract intentionally avoids transfer taxation, mint permissions, blacklist logic, and administrative routing.

The full supply is distributed across segmented Uniswap liquidity ranges. Initial liquidity is narrow by design, while additional token-side depth becomes active only as price discovery expands.

Status:

* Liquidity: initialized
* Price: not found
* Tax: not found
* Mint: not found
* Blacklist: not found 
*/

contract ERC4040PriceNotFound {
    // -------------------------------------------------------------------------
    // ERC-20 metadata
    // -------------------------------------------------------------------------

    string public constant name = "ERC-4040: Price Not Found";
    string public constant symbol = "4040";
    uint8 public constant decimals = 18;

    // 40,404,040 tokens
    uint256 public constant INITIAL_SUPPLY = 40_404_040 * 1e18;

    // -------------------------------------------------------------------------
    // ERC-20 storage
    // -------------------------------------------------------------------------

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // -------------------------------------------------------------------------
    // Experimental public state
    // -------------------------------------------------------------------------

    uint256 public totalTransfers;
    uint256 public immutable deployedAt;
    address public immutable deployer;

    // -------------------------------------------------------------------------
    // ERC-20 events
    // -------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // -------------------------------------------------------------------------
    // ERC-4040 experiment events
    // -------------------------------------------------------------------------

    event PriceNotFound(address indexed caller, uint256 indexed transferCount);
    event Status4040(string liquidity, string price, string tax, string mint, string blacklist);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        deployer = msg.sender;
        deployedAt = block.timestamp;

        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;

        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
        emit Status4040("initialized", "not found", "not found", "not found", "not found");
    }

    // -------------------------------------------------------------------------
    // ERC-20 logic
    // -------------------------------------------------------------------------

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ERC4040: insufficient allowance");

            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }

            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        allowance[msg.sender][spender] += addedValue;

        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowance[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC4040: decreased allowance below zero");

        unchecked {
            allowance[msg.sender][spender] = currentAllowance - subtractedValue;
        }

        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "ERC4040: transfer to zero address");

        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= amount, "ERC4040: insufficient balance");

        unchecked {
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
            totalTransfers++;
        }

        emit Transfer(from, to, amount);

        if (totalTransfers % 4040 == 0) {
            emit PriceNotFound(msg.sender, totalTransfers);
        }
    }

    // -------------------------------------------------------------------------
    // ERC-4040 public read functions
    // -------------------------------------------------------------------------

    function standard() external pure returns (string memory) {
        return "ERC-4040 experimental ERC-20 price discovery profile";
    }

    function errorCode() external pure returns (string memory) {
        return "4040_PRICE_NOT_FOUND";
    }

    function liquidityStatus() external pure returns (string memory) {
        return "initialized";
    }

    function priceStatus() external pure returns (string memory) {
        return "not found";
    }

    function taxStatus() external pure returns (string memory) {
        return "not found";
    }

    function mintStatus() external pure returns (string memory) {
        return "not found";
    }

    function blacklistStatus() external pure returns (string memory) {
        return "not found";
    }

    function ownerStatus() external pure returns (string memory) {
        return "not found";
    }

    function status()
        external
        pure
        returns (
            string memory liquidity,
            string memory price,
            string memory tax,
            string memory mint,
            string memory blacklist,
            string memory owner
        )
    {
        return (
            "initialized",
            "not found",
            "not found",
            "not found",
            "not found",
            "not found"
        );
    }

    function proposal() external pure returns (string memory) {
        return
            "ERC-4040 proposes a minimal ERC-20 experiment in which price discovery is treated as an unresolved state rather than a launch parameter. "
            "The token supply is fixed. Liquidity is initialized without a target valuation model, bonding curve, or privileged market-control mechanism. "
            "The contract intentionally avoids transfer taxation, mint permissions, blacklist logic, and administrative routing. "
            "The only active mechanism is market execution.";
    }

    function liquidityProfile() external pure returns (string memory) {
        return
            "The full supply may be distributed across segmented Uniswap liquidity ranges. "
            "Initial liquidity may be narrow by design, while additional token-side depth becomes active only as price discovery expands.";
    }

    function manifesto() external pure returns (string memory) {
        return
            "Liquidity is initialized. Fair value is not. "
            "No tax. No mint. No blacklist. No owner. Price must be found by the market.";
    }

}