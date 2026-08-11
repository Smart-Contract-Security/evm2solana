// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDMeth} from "../interfaces/IDMeth.sol";

/**
 * @title GenesisSale
 * @notice Pre-TGE genesis sale of dMETH paid for **exclusively in ETH**. Owner
 * configures six tranches with an ETH price per whole dMETH (1e18 wei). Buys
 * automatically walk forward through tranches when a tranche sells out within
 * the same transaction. Each wallet has a rolling cap that loosens over time:
 *  - First 24h after sale start: 20,000 dMETH
 *  - 24h to 48h: 50,000 dMETH
 *  - After 48h: 100,000 dMETH
 *
 * dMETH minted via this contract is permanent — there is no USD or oracle
 * pricing. Overpayment is refunded; underpayment reverts. The contract holds
 * received ETH until the owner withdraws it to the treasury.
 */
contract GenesisSale is Ownable, ReentrancyGuard {
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            STORAGE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    address public dmeth;
    address public treasury;
    uint64 public saleStart;

    struct Tranche {
        uint256 supply;            // dMETH wei available in this tranche
        uint256 sold;              // dMETH wei already sold in this tranche
        uint256 priceWeiPerDmeth;  // ETH (wei) per whole dMETH unit (1e18 wei dMETH)
    }

    uint8 public constant NUM_TRANCHES = 6;
    Tranche[NUM_TRANCHES] public tranches;
    uint8 public currentTranche;

    mapping(address => uint256) public walletPurchased;

    uint256 public cap24h  = 20_000e18;
    uint256 public cap48h  = 50_000e18;
    uint256 public capLate = 100_000e18;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            EVENTS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    event TrancheConfigured(uint8 indexed idx, uint256 supply, uint256 priceWeiPerDmeth);
    event SaleStarted(uint64 timestamp);
    event Purchased(address indexed buyer, uint256 dmethAmount, uint256 ethPaid, uint8 finalTranche);
    event CapsUpdated(uint256 cap24h, uint256 cap48h, uint256 capLate);
    event ConfigUpdated(string indexed key, address value);
    event ETHWithdrawn(address indexed to, uint256 amount);

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            ERRORS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    error SaleNotStarted();
    error SaleEnded();
    error InsufficientETH();
    error WalletCapExceeded();
    error ZeroAmount();
    error ZeroAddress();
    error InvalidTranche();
    error TransferFailed();
    error NotConfigured();

    constructor() Ownable(msg.sender) {}

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         USER FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Buy up to `dmethAmount` dMETH. If the active tranche cannot
    /// fill the full amount, the buy walks into subsequent tranches at their
    /// own prices. ETH overpayment is refunded; insufficient ETH reverts.
    function buy(uint256 dmethAmount) external payable nonReentrant {
        if (dmeth == address(0)) revert NotConfigured();
        if (saleStart == 0 || block.timestamp < saleStart) revert SaleNotStarted();
        if (currentTranche >= NUM_TRANCHES) revert SaleEnded();
        if (dmethAmount == 0) revert ZeroAmount();

        uint256 cap = _walletCap();
        if (walletPurchased[msg.sender] + dmethAmount > cap) revert WalletCapExceeded();

        uint256 remaining = dmethAmount;
        uint256 totalCost = 0;
        uint8 cursor = currentTranche;

        while (remaining > 0 && cursor < NUM_TRANCHES) {
            Tranche storage t = tranches[cursor];
            uint256 available = t.supply - t.sold;
            if (available == 0) {
                cursor += 1;
                continue;
            }
            uint256 fill = remaining > available ? available : remaining;
            totalCost += (fill * t.priceWeiPerDmeth) / 1e18;
            t.sold += fill;
            remaining -= fill;
            if (t.sold == t.supply) cursor += 1;
        }

        uint256 actuallyBought = dmethAmount - remaining;
        if (actuallyBought == 0) revert SaleEnded();
        if (msg.value < totalCost) revert InsufficientETH();

        currentTranche = cursor;
        walletPurchased[msg.sender] += actuallyBought;

        IDMeth(dmeth).mint(msg.sender, actuallyBought);

        // Refund any ETH overpayment.
        if (msg.value > totalCost) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - totalCost}("");
            if (!ok) revert TransferFailed();
        }

        emit Purchased(msg.sender, actuallyBought, totalCost, cursor);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         VIEW FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @notice Quote the ETH cost to buy `dmethAmount`, walking tranches if
    /// needed. Returns the cost and the `dmethAmount` that can actually be filled.
    function quote(uint256 dmethAmount) external view returns (uint256 cost, uint256 filled) {
        uint256 remaining = dmethAmount;
        uint8 cursor = currentTranche;

        while (remaining > 0 && cursor < NUM_TRANCHES) {
            Tranche memory t = tranches[cursor];
            uint256 available = t.supply - t.sold;
            if (available == 0) {
                cursor += 1;
                continue;
            }
            uint256 fill = remaining > available ? available : remaining;
            cost += (fill * t.priceWeiPerDmeth) / 1e18;
            remaining -= fill;
            cursor += 1;
        }
        filled = dmethAmount - remaining;
    }

    function currentWalletCap() external view returns (uint256) {
        if (saleStart == 0) return 0;
        return _walletCap();
    }

    function remainingInWallet(address buyer) external view returns (uint256) {
        if (saleStart == 0) return 0;
        uint256 cap = _walletCap();
        uint256 spent = walletPurchased[buyer];
        return spent >= cap ? 0 : cap - spent;
    }

    function getTranche(uint8 idx) external view returns (Tranche memory) {
        if (idx >= NUM_TRANCHES) revert InvalidTranche();
        return tranches[idx];
    }

    function _walletCap() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - saleStart;
        if (elapsed < 24 hours) return cap24h;
        if (elapsed < 48 hours) return cap48h;
        return capLate;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        ADMIN FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function setTranche(uint8 idx, uint256 supply, uint256 priceWeiPerDmeth) external onlyOwner {
        _setTranche(idx, supply, priceWeiPerDmeth);
    }

    /// @notice Configure multiple tranches atomically, starting at `startIdx`
    /// and writing `supplies[i]` / `prices[i]` to index `startIdx + i`. Reverts
    /// the entire batch on any failure (including any target tranche having
    /// existing sales).
    function batchSetTranches(
        uint8 startIdx,
        uint256[] calldata supplies,
        uint256[] calldata prices
    ) external onlyOwner {
        if (supplies.length != prices.length) revert InvalidTranche();
        for (uint256 i = 0; i < supplies.length; i++) {
            _setTranche(uint8(startIdx + i), supplies[i], prices[i]);
        }
    }

    function _setTranche(uint8 idx, uint256 supply, uint256 priceWeiPerDmeth) internal {
        if (idx >= NUM_TRANCHES) revert InvalidTranche();
        Tranche storage t = tranches[idx];
        // Only allow reconfiguration if nothing has been sold from this tranche.
        require(t.sold == 0, "tranche has sales");
        t.supply = supply;
        t.priceWeiPerDmeth = priceWeiPerDmeth;
        emit TrancheConfigured(idx, supply, priceWeiPerDmeth);
    }

    function startSale(uint64 _start) external onlyOwner {
        require(saleStart == 0, "already started");
        saleStart = _start == 0 ? uint64(block.timestamp) : _start;
        emit SaleStarted(saleStart);
    }

    function setCaps(uint256 _c24, uint256 _c48, uint256 _cLate) external onlyOwner {
        cap24h = _c24;
        cap48h = _c48;
        capLate = _cLate;
        emit CapsUpdated(_c24, _c48, _cLate);
    }

    function setDMeth(address _dmeth) external onlyOwner {
        if (_dmeth == address(0)) revert ZeroAddress();
        dmeth = _dmeth;
        emit ConfigUpdated("dmeth", _dmeth);
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit ConfigUpdated("treasury", _treasury);
    }

    function withdrawETH() external onlyOwner nonReentrant {
        if (treasury == address(0)) revert ZeroAddress();
        uint256 bal = address(this).balance;
        (bool ok, ) = payable(treasury).call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit ETHWithdrawn(treasury, bal);
    }
}
