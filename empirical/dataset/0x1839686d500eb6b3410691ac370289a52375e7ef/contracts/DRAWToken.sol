// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DRAWToken is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 21_000_000 ether;

    uint256 public constant CLAIM_ALLOCATION = 12_134_000 ether;
    uint256 public constant LIQUIDITY_ALLOCATION = 5_250_000 ether;
    uint256 public constant TREASURY_ALLOCATION = 2_566_000 ether;
    uint256 public constant MARKETING_ALLOCATION = 1_050_000 ether;

    enum Allocation {
        NftHolderClaim,
        Liquidity,
        TreasuryDevelopment,
        MarketingRewards
    }

    mapping(uint8 allocation => uint256 amount) public allocationDistributed;

    event AllocationDistributed(Allocation indexed allocation, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error AllocationExceeded(uint256 cap, uint256 attemptedTotal);

    constructor(address initialOwner) ERC20("Draw", "DRAW") Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _mint(initialOwner, TOTAL_SUPPLY);
    }

    function allocationCap(Allocation allocation) public pure returns (uint256) {
        if (allocation == Allocation.NftHolderClaim) return CLAIM_ALLOCATION;
        if (allocation == Allocation.Liquidity) return LIQUIDITY_ALLOCATION;
        if (allocation == Allocation.TreasuryDevelopment) return TREASURY_ALLOCATION;
        return MARKETING_ALLOCATION;
    }

    function distributeAllocation(Allocation allocation, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint8 key = uint8(allocation);
        uint256 newDistributedTotal = allocationDistributed[key] + amount;
        uint256 cap = allocationCap(allocation);
        if (newDistributedTotal > cap) revert AllocationExceeded(cap, newDistributedTotal);

        allocationDistributed[key] = newDistributedTotal;
        _transfer(_msgSender(), to, amount);

        emit AllocationDistributed(allocation, to, amount);
    }
}
