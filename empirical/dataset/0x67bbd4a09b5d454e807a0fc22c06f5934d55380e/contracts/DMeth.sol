// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DMeth
 * @notice Soulbound, non-transferable game-fuel ledger for Mining ETH.
 *
 * dMETH is the in-game currency used to buy rooms (room 2+), buy miners, open Packs,
 * and pay power bills. It is minted by authorized minters (Genesis sale, METH→dMETH
 * converter, Bag redemption) and burned by authorized burners (Mining system,
 * Packs, etc.). It can never be transferred, and it can never convert into METH.
 *
 * The ERC20 transfer/approve surface reverts so that wallets and explorers treat
 * dMETH as account-bound. Standard `balanceOf` / `totalSupply` reads are exposed.
 */
contract DMeth is Ownable {
    string public constant name = "Distilled METH";
    string public constant symbol = "dMETH";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    uint256 public totalBurned;
    uint256 public totalMinted;

    mapping(address => uint256) private _balances;
    mapping(address => bool) public authorizedMinters;
    mapping(address => bool) public authorizedBurners;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event MinterUpdated(address indexed minter, bool authorized);
    event BurnerUpdated(address indexed burner, bool authorized);

    error NotAuthorizedMinter();
    error NotAuthorizedBurner();
    error InsufficientBalance();
    error NonTransferable();
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Mint dMETH. Restricted to authorized minters.
    function mint(address to, uint256 amount) external {
        if (!authorizedMinters[msg.sender]) revert NotAuthorizedMinter();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        _totalSupply += amount;
        totalMinted += amount;
        _balances[to] += amount;

        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }

    /// @notice Burn dMETH from `from`. Restricted to authorized burners.
    function burn(address from, uint256 amount) external {
        if (!authorizedBurners[msg.sender]) revert NotAuthorizedBurner();
        if (amount == 0) return;
        uint256 bal = _balances[from];
        if (bal < amount) revert InsufficientBalance();

        unchecked {
            _balances[from] = bal - amount;
            _totalSupply -= amount;
        }
        totalBurned += amount;

        emit Transfer(from, address(0), amount);
        emit Burn(from, amount);
    }

    function setMinter(address minter, bool authorized) external onlyOwner {
        if (minter == address(0)) revert ZeroAddress();
        authorizedMinters[minter] = authorized;
        emit MinterUpdated(minter, authorized);
    }

    function setBurner(address burner, bool authorized) external onlyOwner {
        if (burner == address(0)) revert ZeroAddress();
        authorizedBurners[burner] = authorized;
        emit BurnerUpdated(burner, authorized);
    }

    // ━━━ Non-transferable enforcement ━━━

    function transfer(address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    function approve(address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }
}
