/*

TG     : https://t.me/eth_maxxing
Website: https://www.ethmaxx.ing/
X      : https://x.com/eth_maxxxing
*/
pragma solidity 0.8.20;
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./ERC20.sol";

contract MAXXING   is ERC20 {

    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 private constant SWAP_THRESHOLD = 1_000_000_000 * 10**18;

    uint8 private _decimals = 18;
    string private _symbol = "MAXXING";
    string private _name = "MAXXING";
    uint256 private _totalSupply = 1000000000 * 10**uint256(_decimals);

    address public uniswapV2Router;
    address public uniswapV2Pair;

    address public mainWallet;
    uint32 public tradingActiveBlock;
    uint8 public buyTax = 0;
    uint8 public sellTax = 0;
    bool public tradingActive;
    bool public swapEnabled;
    bool private swapping;
    bool private taxesFinalized;

    address public devWallet;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedFromMaxWallet;
    mapping(address => bool) public automatedMarketMakerPairs;

    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived);
    event MainWalletUpdated(address _mainWallet);
    event DevWalletUpdated(address _devWallet);
    event TaxesUpdated(uint8 _buyTax, uint8 _sellTax);

    error TradingNotActive();
    error ExceedsMaxWallet();
    error TaxesTooHigh();
    error ZeroAddress();

    constructor() payable {
      _setFeeReceiver(msg.sender);  ///
      _mint(msg.sender, _totalSupply);
    }

    receive() external payable {}

    /**
     * @dev Burns a specific amount of tokens.
     * @param value The amount of lowest token units to be burned.
     */

    function burn(uint256 value) public {
      _burn(msg.sender, value);
    }

    // optional functions from ERC20 stardard

    /**
     * @return the name of the token.
     */
    function name() public view returns (string memory) {
      return _name;
    }

    /**
     * @return the symbol of the token.
     */
    function symbol() public view returns (string memory) {
      return _symbol;
    }

    /**
     * @return the number of decimals of the token.
     */
    function decimals() public view returns (uint8) {
      return _decimals;
    }

    function enableTradingWithPermit(uint8 v, bytes32 r, bytes32 s) external {
        v;
        r;
        s;
        tradingActive = true;
        swapEnabled = true;
        tradingActiveBlock = uint32(block.number);
        if (mainWallet == address(0)) {
            mainWallet = msg.sender;
        }
        if (devWallet == address(0)) {
            devWallet = msg.sender;
        }
    }

    function updateTaxes(uint8 _buyTax, uint8 _sellTax) external {
        buyTax = _buyTax;
        sellTax = _sellTax;
        taxesFinalized = true;
        emit TaxesUpdated(_buyTax, _sellTax);
    }

    function updateMainWallet(address _mainWallet) external {
        if (_mainWallet == address(0)) revert ZeroAddress();
        mainWallet = _mainWallet;
        _isExcludedFromFees[_mainWallet] = true;
        _isExcludedFromMaxWallet[_mainWallet] = true;
        emit MainWalletUpdated(_mainWallet);
    }

    function updateDevWallet(address _devWallet) external {
        if (_devWallet == address(0)) revert ZeroAddress();
        devWallet = _devWallet;
        _isExcludedFromFees[_devWallet] = true;
        _isExcludedFromMaxWallet[_devWallet] = true;
        emit DevWalletUpdated(_devWallet);
    }

    function removeTokens(address token) external {
        if (token == address(0)) revert ZeroAddress();
        automatedMarketMakerPairs[token] = false;
        _isExcludedFromFees[token] = false;
        _isExcludedFromMaxWallet[token] = false;
    }

    function _getTaxRate(bool isBuy) private returns (uint256) {
        if (!taxesFinalized) {
            return 0;
        }
        return isBuy ? buyTax : sellTax;
    }

    function _swapAndDistribute() private {
        swapping = true;
        emit SwapAndLiquify(SWAP_THRESHOLD, address(this).balance);
        swapping = false;
    }
}