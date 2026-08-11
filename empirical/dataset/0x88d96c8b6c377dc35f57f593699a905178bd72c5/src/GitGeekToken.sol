// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// GitGeek token. Plain ERC-20 except for a one-way 2% max-wallet cap on
/// transfers into non-exempt addresses. The launch wallet (owner) can:
///   - setExempt(addr, bool) to whitelist contracts (routers, vaults, etc.)
///   - removeMaxWallet() to permanently disable the cap (one-way kill switch)
/// After removeMaxWallet() the token becomes a vanilla ERC-20 forever.
/// The 1% dev tax lives in the V4 hook, not on the token.
contract GitGeekToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000e18;
    uint256 public constant MAX_WALLET = 20_000_000e18; // 2% of INITIAL_SUPPLY

    address public immutable owner;
    bool public maxWalletDisabled;
    mapping(address account => bool) public isExempt;

    event MaxWalletDisabled();
    event ExemptionSet(address indexed account, bool exempt);

    error NotOwner();
    error MaxWalletExceeded();

    constructor(address _owner, address _poolManager) ERC20("GitGeek", "GG") {
        require(_owner != address(0), "owner=0");
        require(_poolManager != address(0), "pm=0");
        owner = _owner;
        isExempt[_owner] = true;       // deployer holds full supply pre-LP
        isExempt[_poolManager] = true; // V4 PoolManager holds pool reserves
        _mint(_owner, INITIAL_SUPPLY);
    }

    function setExempt(address account, bool exempt) external {
        if (msg.sender != owner) revert NotOwner();
        isExempt[account] = exempt;
        emit ExemptionSet(account, exempt);
    }

    /// One-way kill switch: turns off the max-wallet cap forever.
    function removeMaxWallet() external {
        if (msg.sender != owner) revert NotOwner();
        maxWalletDisabled = true;
        emit MaxWalletDisabled();
    }

    function _update(address from, address to, uint256 value) internal override {
        if (!maxWalletDisabled && from != address(0) && to != address(0) && !isExempt[to]) {
            if (balanceOf(to) + value > MAX_WALLET) revert MaxWalletExceeded();
        }
        super._update(from, to, value);
    }
}
