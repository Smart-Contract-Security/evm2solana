// SPDX-License-Identifier: MIT

pragma solidity 0.8.32;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract SeerdexToken is ERC20, ERC20Burnable {
    uint256 public constant projectDevReserve = 4_800_000_000 ether;
    uint256 public constant ecosystemRewardsReserve = 3_000_000_000 ether;
    uint256 public constant marketingReserve = 8_000_000_000 ether;
    uint256 public constant stakingReserve = 1_200_000_000 ether;
    uint256 public constant liquidityReserve = 3_000_000_000 ether;

    constructor() ERC20("SeerDEX", "SEERX") {
        _mint(address(0xD70d42541442c5346E23ad0c9ea4ac920CD86aF8), projectDevReserve);
        _mint(address(0xbbE49D16F2230F8E77A3fCEFafc5FA4D6d5B16b3), ecosystemRewardsReserve);
        _mint(address(0x95379217e5f5AFA92A87db01F9F9a2584d25B433), marketingReserve);
        _mint(address(0x79DA67894228Dd7360c1aD88F02424453EfbF24b), stakingReserve);
        _mint(address(0xE049e4cf8C758D9573506A204354b8f2dBcd7228), liquidityReserve);
    }
}