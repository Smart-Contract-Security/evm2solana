// SPDX-License-Identifier: MIT
// ════════════════════════════════════════════════════════════════
//   Pawn-5D · PAWN
//   Website  : https://pawn5d.com
//   App      : https://app.pawn5d.com
//   Twitter  : https://x.com/Pawn_ERC5D
// ════════════════════════════════════════════════════════════════
// ██████╗░░█████╗░░██╗░░░░░░░██╗███╗░░██╗
// ██╔══██╗██╔══██╗░██║░░██╗░░██║████╗░██║
// ██████╔╝███████║░╚██╗████╗██╔╝██╔██╗██║
// ██╔═══╝░██╔══██║░░████╔═████║░██║╚████║
// ██║░░░░░██║░░██║░░╚██╔╝░╚██╔╝░██║░╚███║
// ╚═╝░░░░░╚═╝░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░░╚══╝
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPawnTreasury} from "./interfaces/IPawnTreasury.sol";
import {PawnNFT404} from "./base/PawnNFT404.sol";
import {PawnTaxEngine} from "./base/PawnTaxEngine.sol";
import {PawnRescue} from "./base/PawnRescue.sol";

contract PawnToken is PawnRescue {
    constructor(address marketingWallet_, address treasury_, address router_)
        Ownable(msg.sender)
        PawnNFT404(treasury_)
        PawnTaxEngine(marketingWallet_, router_)
    {
        require(marketingWallet_ != address(0), "zero marketing wallet");
        require(treasury_ != address(0), "zero treasury");

        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);

        _setExempt(msg.sender, true);
        nftExempt[address(this)] = true;
        _setExempt(treasury_, true);
        _setExempt(marketingWallet_, true);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0) && to != address(0), "zero address");
        require(amount > 0, "zero amount");
        require(!bots[from] && !bots[to], "bot blocked");

        if (!tradingOpen) {
            require(
                _isExcludedFromFee[from] || _isExcludedFromFee[to],
                "trading not open"
            );
        }

        uint256 taxAmount;
        bool isBuy = (from == uniswapV2Pair);
        bool isSell = (to == uniswapV2Pair);

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to] && !inSwap) {
            if (isBuy) {
                require(amount <= _maxTxAmount, "exceeds maxTx");
                require(_balances[to] + amount <= _maxWalletSize, "exceeds maxWallet");
                _buyCount++;
                taxAmount = amount * (_buyCount > _reduceBuyTaxAt ? _finalBuyTax : _initialBuyTax)
                    / 100;
            } else if (isSell) {
                taxAmount = amount
                    * (_buyCount > _reduceSellTaxAt ? _finalSellTax : _initialSellTax) / 100;
            }
        }

        _maybeTriggerSwap(isSell, from, amount);

        _balances[from] -= amount;
        uint256 netAmount = amount - taxAmount;
        if (taxAmount > 0) {
            _balances[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[to] += netAmount;
        emit Transfer(from, to, netAmount);

        if (!nftExempt[from]) _reconcileNFTs(from, true);
        if (!nftExempt[to]) _reconcileNFTs(to, false);
    }

    function skipPawn(bool skip) external {
        address holder = msg.sender;

        if (skip) {
            require(!nftExempt[holder], "already opted out");
            if (TREASURY != address(0)) {
                try IPawnTreasury(TREASURY).settleHolder(holder) {} catch {}
            }
            nftExempt[holder] = true;
            uint256 count = _nftCount[holder];
            for (uint256 i; i < count; i++) {
                _burnLastNFT(holder, false);
            }
            emit SkipPawnSet(holder, true);
        } else {
            require(nftExempt[holder], "not opted out");
            nftExempt[holder] = false;
            uint256 expected = _balances[holder] / 1e18;
            for (uint256 i; i < expected; i++) {
                _mintNFT(holder);
            }
            emit SkipPawnSet(holder, false);
        }
    }

    function setPawned(address[] calldata wallets, bool status) external onlyOwner {
        for (uint256 i; i < wallets.length; i++) {
            _setExempt(wallets[i], status);
        }
    }

    function setPawnI(string calldata uri) external onlyOwner {
        require(bytes(_customT1).length == 0, "T1 locked");
        require(bytes(uri).length > 0, "empty");
        _customT1 = uri;
        emit PawnArtSet(1, uri);
    }

    function setPawnII(string calldata uri) external onlyOwner {
        require(bytes(_customT2).length == 0, "T2 locked");
        require(bytes(uri).length > 0, "empty");
        _customT2 = uri;
        emit PawnArtSet(2, uri);
    }

    function setPawnIII(string calldata uri) external onlyOwner {
        require(bytes(_customT3).length == 0, "T3 locked");
        require(bytes(uri).length > 0, "empty");
        _customT3 = uri;
        emit PawnArtSet(3, uri);
    }

    function setPawnIV(string calldata uri) external onlyOwner {
        require(bytes(_customT4).length == 0, "T4 locked");
        require(bytes(uri).length > 0, "empty");
        _customT4 = uri;
        emit PawnArtSet(4, uri);
    }

    function website() external pure returns (string memory) {
        return "https://pawn5d.com";
    }

    function app() external pure returns (string memory) {
        return "https://app.pawn5d.com";
    }

    function twitter() external pure returns (string memory) {
        return "https://x.com/Pawn_ERC5D";
    }

    receive() external payable {}
}
