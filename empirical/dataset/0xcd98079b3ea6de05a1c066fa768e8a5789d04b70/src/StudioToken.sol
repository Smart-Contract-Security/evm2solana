// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStudioToken} from "./interfaces/IStudioToken.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title StudioToken
/// @notice Soulbound governance token controlled exclusively by `StudioVault`.
/// @dev Transfers and approvals are disabled; balance snapshots power governance voting.
contract StudioToken is IStudioToken {
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    /// @notice Address of the controlling vault allowed to mint and force-transfer.
    address public immutable VAULT;
    /// @notice Fixed token decimals.
    uint8 public constant DECIMALS = 18;

    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => Checkpoints.Trace208) private _balanceCheckpoints;
    Checkpoints.Trace208 private _totalSupplyCheckpoints;

    /// @param name_ ERC20-style token name.
    /// @param symbol_ ERC20-style token symbol.
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        VAULT = msg.sender;
    }

    /// @dev Restricts privileged operations to the vault contract.
    modifier onlyVault() {
        if (msg.sender != VAULT) revert NotVault();
        _;
    }

    /// @notice Returns the token name.
    function name() external view returns (string memory) {
        return _name;
    }

    /// @notice Returns the token symbol.
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the fixed number of decimals used for display.
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice Mints governance tokens to `to`.
    /// @param to Mint recipient.
    /// @param amount Amount to mint.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Moves tokens between holders under vault authority.
    /// @param from Source holder.
    /// @param to Destination holder.
    /// @param amount Amount to move.
    function forceTransfer(address from, address to, uint256 amount) external {
        _forceTransfer(from, to, amount);
    }

    /// @notice Returns voting units for an account at `blockNumber`.
    /// @param account Account to query.
    /// @param blockNumber Historical block number.
    /// @return Voting units at the requested block.
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        return _balanceCheckpoints[account].upperLookupRecent(blockNumber.toUint48());
    }

    /// @notice Returns total supply at `blockNumber`.
    /// @param blockNumber Historical block number.
    /// @return Total supply at the requested block.
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _totalSupplyCheckpoints.upperLookupRecent(blockNumber.toUint48());
    }

    /// @notice Returns the current total token supply.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Returns the current balance of `account`.
    /// @param account Account to query.
    /// @return Token balance of `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Disabled for soulbound governance token.
    function transfer(address, uint256) external pure returns (bool) {
        revert SoulboundDisabled();
    }

    /// @notice Returns zero because approvals are disabled.
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    /// @notice Disabled for soulbound governance token.
    function approve(address, uint256) external pure returns (bool) {
        revert SoulboundDisabled();
    }

    /// @notice Disabled for soulbound governance token.
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert SoulboundDisabled();
    }

    /// @dev Mints new voting units and checkpoint updates for governance snapshots.
    function _mint(address to, uint256 amount) internal onlyVault {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _balances[to] += amount;
        _totalSupply += amount;

        uint48 blockNumber = block.number.toUint48();
        _balanceCheckpoints[to].push(blockNumber, _balances[to].toUint208());
        _totalSupplyCheckpoints.push(blockNumber, _totalSupply.toUint208());

        emit Transfer(address(0), to, amount);
    }

    /// @dev Moves voting units between holders and updates per-account checkpoints.
    function _forceTransfer(address from, address to, uint256 amount) internal onlyVault {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (from == to) revert SelfTransfer();
        if (_balances[from] < amount) revert InsufficientBalance();

        _balances[from] -= amount;
        _balances[to] += amount;

        uint48 blockNumber = block.number.toUint48();
        _balanceCheckpoints[from].push(blockNumber, _balances[from].toUint208());
        _balanceCheckpoints[to].push(blockNumber, _balances[to].toUint208());

        emit Transfer(from, to, amount);
        emit ForcedTransfer(from, to, amount);
    }
}
