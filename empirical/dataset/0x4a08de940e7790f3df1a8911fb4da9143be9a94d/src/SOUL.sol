// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/*
 ██████╗  ██████╗ ██╗   ██╗██╗     ██████╗  ██████╗ ██╗   ██╗███╗   ██╗██████╗
 ██╔════╝ ██╔═══██╗██║   ██║██║     ██╔══██╗██╔═══██╗██║   ██║████╗  ██║██╔══██╗
 ╚█████╗  ██║   ██║██║   ██║██║     ██████╔╝██║   ██║██║   ██║██╔██╗ ██║██║  ██║
  ╚═══██╗ ██║   ██║██║   ██║██║     ██╔══██╗██║   ██║██║   ██║██║╚██╗██║██║  ██║
 ██████╔╝ ╚██████╔╝╚██████╔╝███████╗██████╔╝╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝
 ╚═════╝   ╚═════╝  ╚═════╝ ╚══════╝╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝

  Website : https://soulbound.zip
  X       : https://x.com/soulboundzip
*/

/// @title  SOUL
/// @notice Fixed-supply (1M) burnable ERC-20. No owner. No mint after deploy.
///         Anyone can burn their balance. Supports EIP-2612 permit.
contract SOUL {
    string public constant name = "SOULBOUND";
    string public constant symbol = "SOUL";
    uint8 public constant decimals = 18;
    uint256 public constant MAX_SUPPLY = 1_000_000 * 1e18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public nonces;
    uint256 private immutable _INITIAL_CHAIN_ID;
    bytes32 private immutable _INITIAL_DOMAIN_SEPARATOR;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Burn(address indexed burner, uint256 amount);

    error InsufficientBalance();
    error InsufficientAllowance();
    error PermitExpired();
    error InvalidSignature();

    constructor() {
        totalSupply = MAX_SUPPLY;
        balanceOf[msg.sender] = MAX_SUPPLY;
        emit Transfer(address(0), msg.sender, MAX_SUPPLY);

        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[msg.sender] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked { allowance[from][msg.sender] = allowed - amount; }
        }
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function burn(uint256 amount) external {
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[msg.sender] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
        emit Burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked { allowance[from][msg.sender] = allowed - amount; }
        }
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
        emit Burn(from, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert PermitExpired();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline
                    )
                )
            )
        );

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != owner) revert InvalidSignature();

        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _INITIAL_CHAIN_ID
            ? _INITIAL_DOMAIN_SEPARATOR
            : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
}
