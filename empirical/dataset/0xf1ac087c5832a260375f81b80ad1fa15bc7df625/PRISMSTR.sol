// ============================
//           $PRISMSTR
//   BUYING $PRISM WITH FEES
//      AND REFLECTING IT
//         0.3% POOL FEE
//         1.2% PRISM FEE
// ============================

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PRISMSTR is ERC20 {
    uint256 public constant SCALE = 1e36;

    address public constant POOL_MANAGER =
        0x000000000004444c5dc75cB358380D2e3dE08A90;

    address public constant UNIVERSAL_ROUTER =
        0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    address public immutable deployer;
    address public hook;

    uint256 public reflectionIndex;
    uint256 public accountedReflectionBucket;
    uint256 public excludedSupply;

    mapping(address => uint256) public userIndex;
    mapping(address => bool) public excludedFromReflection;

    error NotHook();
    error HookAlreadySet();
    error ZeroHook();
    error InsufficientReflectionBucket();

    event HookSet(address indexed hook);
    event ReflectionNotified(uint256 amount, uint256 newIndex);
    event ReflectionSettled(address indexed account, uint256 amount);
    event ReflectionExcluded(address indexed account, bool excluded);

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    constructor() ERC20("Prism Strategy","PRISMSTR") {
        deployer = msg.sender;

        _mint(msg.sender, 1_000_000_000 * 1e18);

        _setExcluded(address(this), true);
        _setExcluded(POOL_MANAGER, true);
        _setExcluded(UNIVERSAL_ROUTER, true);
        _setExcluded(msg.sender, true);
    }

    function setHook(address _hook) external {
        if (_hook == address(0)) revert ZeroHook();
        if (hook != address(0)) revert HookAlreadySet();

        hook = _hook;
        _setExcluded(_hook, true);

        emit HookSet(_hook);
    }

    function balanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return super.balanceOf(account) + pendingReflection(account);
    }

    function settledBalanceOf(address account)
        external
        view
        returns (uint256)
    {
        return super.balanceOf(account);
    }

    function pendingReflection(address account)
        public
        view
        returns (uint256)
    {
        if (excludedFromReflection[account]) return 0;

        uint256 bal = super.balanceOf(account);
        if (bal == 0) return 0;

        return (bal * (reflectionIndex - userIndex[account])) / SCALE;
    }

    function eligibleSupply() public view returns (uint256) {
        return totalSupply() - excludedSupply;
    }

    function notifyReflection() external onlyHook returns (uint256 amount) {
        uint256 currentBucket = super.balanceOf(address(this));

        if (currentBucket <= accountedReflectionBucket) {
            return 0;
        }

        uint256 supply = eligibleSupply();

        // If only excluded addresses exist so far, leave the new tokens
        // unaccounted in the bucket. A later notifyReflection() will include
        // them once eligible supply exists.
        if (supply == 0) {
            return 0;
        }

        amount = currentBucket - accountedReflectionBucket;

        accountedReflectionBucket = currentBucket;
        reflectionIndex += (amount * SCALE) / supply;

        emit ReflectionNotified(amount, reflectionIndex);
    }

    function syncReflection(address account) external {
        _settle(account);
    }

    function _settle(address account) internal {
        if (account == address(0)) return;

        if (excludedFromReflection[account]) {
            userIndex[account] = reflectionIndex;
            return;
        }

        uint256 pending = pendingReflection(account);
        userIndex[account] = reflectionIndex;

        if (pending == 0) return;

        if (accountedReflectionBucket < pending) {
            revert InsufficientReflectionBucket();
        }

        accountedReflectionBucket -= pending;

        // Materializes pending reflection into real OZ _balances without minting.
        // Direct super call avoids recursively entering this contract's _update().
        super._update(address(this), account, pending);

        emit ReflectionSettled(account, pending);
    }

    function _update(address from, address to, uint256 value)
        internal
        override
    {
        if (from != address(0)) _settle(from);
        if (to != address(0)) _settle(to);

        super._update(from, to, value);

        if (from != address(0) && excludedFromReflection[from]) {
            excludedSupply -= value;
        }

        if (to != address(0) && excludedFromReflection[to]) {
            excludedSupply += value;
        }
    }

    function _setExcluded(address account, bool excluded) internal {
        if (excludedFromReflection[account] == excluded) return;

        if (excluded) {
            _settle(account);

            excludedFromReflection[account] = true;
            userIndex[account] = reflectionIndex;

            excludedSupply += super.balanceOf(account);
        } else {
            excludedSupply -= super.balanceOf(account);

            excludedFromReflection[account] = false;
            userIndex[account] = reflectionIndex;
        }

        emit ReflectionExcluded(account, excluded);
    }
}