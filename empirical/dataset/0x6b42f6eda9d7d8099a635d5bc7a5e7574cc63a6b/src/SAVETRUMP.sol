// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// forgefmt: disable-start
/**

$SAVETRUMP Token
https://t.me/savetrumptoken (telegram)
1 Token For Each Felony


  /$$$$$$   /$$$$$$  /$$    /$$ /$$$$$$$$ /$$$$$$$$ /$$$$$$$  /$$   /$$ /$$      /$$ /$$$$$$$ 
 /$$__  $$ /$$__  $$| $$   | $$| $$_____/|__  $$__/| $$__  $$| $$  | $$| $$$    /$$$| $$__  $$
| $$  \__/| $$  \ $$| $$   | $$| $$         | $$   | $$  \ $$| $$  | $$| $$$$  /$$$$| $$  \ $$
|  $$$$$$ | $$$$$$$$|  $$ / $$/| $$$$$      | $$   | $$$$$$$/| $$  | $$| $$ $$/$$ $$| $$$$$$$/
 \____  $$| $$__  $$ \  $$ $$/ | $$__/      | $$   | $$__  $$| $$  | $$| $$  $$$| $$| $$____/ 
 /$$  \ $$| $$  | $$  \  $$$/  | $$         | $$   | $$  \ $$| $$  | $$| $$\  $ | $$| $$      
|  $$$$$$/| $$  | $$   \  $/   | $$$$$$$$   | $$   | $$  | $$|  $$$$$$/| $$ \/  | $$| $$      
 \______/ |__/  |__/    \_/    |________/   |__/   |__/  |__/ \______/ |__/     |__/|__/                   


**/

// forgefmt: disable-end

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

/// @title SAVETRUMP Token
/// @notice Bigly gas optimized ERC20 token with fees
/// @author SAVETRUMP (https://t.me/savetrumptoken)
/// @author Modified from GasliteToken (https://github.com/PopPunkLLC/gaslite-core/blob/main/src/GasliteToken.sol)
/// @author Modified from Harrison (@PopPunkOnChain)
/// @author Modified from 0xjustadev (@0xjustadev)
/// @author Modified from (@GasliteGG)
contract SAVETRUMP is Ownable {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public immutable totalSupply;
    uint256 public immutable TAX_SWAP_THRESHOLD;
    uint256 public immutable MAX_TAX_SWAP;

    address private lpTokenRecipient;
    address public developmentWallet;
    address public magaWallet;

    uint8 public constant TRADING_DISABLED = 0;
    uint8 public constant TRADING_ENABLED = 1;
    uint8 public constant BUY_TOTAL_FEES = 10;            // BUY_TOTAL_FEES / 1000         =  1%
    uint8 public constant SELL_TOTAL_FEES = 10;           // SELL_TOTAL_FEES / 1000        =  1%
    uint8 public constant PERCENTAGE_FEE_TO_MAGA = 50;    // PERCENTAGE_FEE_TO_MAGA / 100  = 50%
    uint8 public tradingStatus = TRADING_DISABLED;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private automatedMarketMakerPairs;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    error ZeroAddress();
    error InsufficientAllowance();
    error InsufficientBalance();
    error CannotRemoveV2Pair();
    error WithdrawalFailed();
    error InvalidState();
    error TradingDisabled();

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Constructor
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _totalSupply Total supply of the token
    /// @param _lpTokenRecipient Address to receive LP tokens
    /// @param _developmentWallet Address to receive fees
    /// @param _magaWallet Address to receive fees
    /// @param _uniswapV2RouterAddress Address of Uniswap V2 Router
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _lpTokenRecipient,
        address _developmentWallet,
        address _magaWallet,
        address _uniswapV2RouterAddress
    ) payable Ownable(_lpTokenRecipient) {
        if (_uniswapV2RouterAddress == address(0)) revert ZeroAddress();

        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        lpTokenRecipient = _lpTokenRecipient;
        magaWallet = _magaWallet;
        developmentWallet = _developmentWallet;

        TAX_SWAP_THRESHOLD = _totalSupply * 10 / 10_000;
        MAX_TAX_SWAP = _totalSupply * 100 / 10_000;

        uniswapV2Router = IUniswapV2Router02(_uniswapV2RouterAddress);

        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        automatedMarketMakerPairs[uniswapV2Pair] = true;

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[_developmentWallet] = true;
        _isExcludedFromFees[_magaWallet] = true;

        _balances[address(this)] = _totalSupply;
        emit Transfer(address(0), address(this), _totalSupply);

        _approve(address(this), address(uniswapV2Router), type(uint256).max);
    }

    receive() external payable {}

    /// @notice Adds liquidity to Uniswap
    function fundLP() external payable onlyOwner {
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this), totalSupply, 0, 0, lpTokenRecipient, block.timestamp
        );
    }

    /// @notice Gets balance of an address
    /// @param account Address to check balance of
    /// @return Balance of the address
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /// @notice Gets allowance of an address
    /// @param owner Address of the owner
    /// @param spender Address of the spender
    /// @return Allowance of the address
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Approves an address to spend tokens
    /// @param spender Address of the spender
    /// @param amount Amount to approve
    /// @return True if successful
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Internal approve
    /// @param owner Address of the owner
    /// @param spender Address of the spender
    /// @param amount Amount to approve
    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0)) revert ZeroAddress();
        if (spender == address(0)) revert ZeroAddress();

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /// @notice Transfers tokens to an address
    /// @param recipient Address of the recipient
    /// @param amount Amount to transfer
    /// @return True if successful
    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Transfers tokens from an address to another address
    /// @param sender Address of the sender
    /// @param recipient Address of the recipient
    /// @param amount Amount to transfer
    /// @return True if successful
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            unchecked {
                _approve(sender, msg.sender, currentAllowance - amount);
            }
        }

        _transfer(sender, recipient, amount);

        return true;
    }

    /// @notice Internal transfer
    /// @param from Address of the sender
    /// @param to Address of the recipient
    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();

        if (tradingStatus == TRADING_DISABLED) {
            if (from != owner() && from != magaWallet && from != developmentWallet && from != address(this) && to != owner()) {
                revert TradingDisabled();
            }
        }

        bool takeFee = true;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 senderBalance = _balances[from];
        if (senderBalance < amount) revert InsufficientBalance();

        uint256 fees = 0;
        if (takeFee) {
            if (automatedMarketMakerPairs[to] && SELL_TOTAL_FEES > 0) {
                fees = (amount * SELL_TOTAL_FEES) / 1000;
            } else if (automatedMarketMakerPairs[from] && BUY_TOTAL_FEES > 0) {
                fees = (amount * BUY_TOTAL_FEES) / 1000;
            }

            if (fees > 0) {
                uint256 tokenBalance = balanceOf(address(this));
                if (tokenBalance > TAX_SWAP_THRESHOLD && to == uniswapV2Pair) {
                    uint256 minOfAll;
                    if (tokenBalance < MAX_TAX_SWAP) minOfAll = tokenBalance < amount ? tokenBalance : amount;
                    else minOfAll = MAX_TAX_SWAP < amount ? MAX_TAX_SWAP : amount;

                    uint256 preEthBalance = address(this).balance;
                    // this.swapTokensForEth(minOfAll);

                    address[] memory path = new address[](2);
                    path[0] = address(this);
                    path[1] = uniswapV2Router.WETH();
                    _approve(address(this), address(uniswapV2Router), minOfAll);
                    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                        minOfAll,
                        0,
                        path,
                        address(this),
                        block.timestamp
                    );

                    uint256 ethBalance = address(this).balance - preEthBalance;
                    if (ethBalance > 0) {
                        uint256 magaETHFees = ethBalance * PERCENTAGE_FEE_TO_MAGA / 100;
                        payable(magaWallet).transfer(magaETHFees);
                        payable(developmentWallet).transfer(ethBalance - magaETHFees);
                    }

                }
                unchecked {
                    amount = amount - fees;
                    _balances[from] -= fees;
                    _balances[address(this)] += fees;
                }
                emit Transfer(from, address(this), fees);
            }
        }
        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }


    /// @notice Enables trading
    function enableTrading() public onlyOwner {
        tradingStatus = TRADING_ENABLED;
    }

    /// @notice Sets AMM pair
    /// @param pair Address of the pair
    /// @param value True if AMM pair
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        if (pair == uniswapV2Pair) revert CannotRemoveV2Pair();
        automatedMarketMakerPairs[pair] = value;
    }

    /// @notice Withdraw tokens from the contract
    /// @param token Address of the token
    /// @param to Address to withdraw to
    function withdrawToken(address token, address to) external onlyOwner {
        uint256 _contractBalance = IERC20(token).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(token), to, _contractBalance);
    }

    /// @notice Withdraw ETH from the contract
    /// @param addr Address to withdraw to
    function withdrawETH(address addr) external onlyOwner {
        if (addr == address(0)) revert ZeroAddress();

        (bool success,) = addr.call{value: address(this).balance}("");
        if (!success) revert WithdrawalFailed();
    }

    
    uint256 lpUnlockTime;

    /// @notice Simple Locker Functionality
    /// @param unlockTime timestamp of when LP unlocks
    /// @param lpAmount the amount of LP tokens to lock
    function lockLPToken(uint256 unlockTime, uint256 lpAmount) external onlyOwner {
        if (lpUnlockTime != 0) revert();
        SafeERC20.safeTransferFrom(IERC20(uniswapV2Pair), msg.sender, address(this), lpAmount);
        lpUnlockTime = unlockTime;
    }

    function redeemLPToken() external onlyOwner {
        if (lpUnlockTime == 0) revert();
        if (block.timestamp < lpUnlockTime) revert();

        IERC20 pair = IERC20(uniswapV2Pair);
        SafeERC20.safeTransfer(pair, msg.sender, pair.balanceOf(address(this)));
    }
}