//SPDX-License-Identifier: MIT

import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes) {
        return tx.accounts.dataAccount.data;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint64 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string);
    function symbol() external view returns (string);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint64) internal _balances;
    mapping(address => mapping(address => uint64)) internal _allowances;

    uint64 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string name_, string symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view override returns (string) {
        return _name;
    }

    function symbol() public view override returns (string) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint64) {
        return _balances[account];
    }

    function transfer(address recipient, uint64 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint64)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint64 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint64 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    function increaseAllowance(address spender, uint64 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint64 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint64 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint64 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _tokengeneration(address account, uint64 amount) internal virtual {
        require(account != address(0), "ERC20: generation to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = amount;
        _balances[account] = amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint64 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint64 amount
    ) internal virtual {}
}

library Address {
    function sendValue(address payable recipient, uint64 amount) internal {
        require(tx.accounts.dataAccount.lamports >= amount, "Address: insufficient balance");

        recipient.lamports += amount;
        tx.accounts.dataAccount.lamports -= amount;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface uniswapV2Router {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function addLiquidityETH(
        address token,
        uint64 amountTokenDesired,
        uint64 amountTokenMin,
        uint64 amountETHMin,
        address to,
        uint64 deadline
    )
        external
        returns (
            uint64 amountToken,
            uint64 amountETH,
            uint64 liquidity
        );

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint64 amountIn,
        uint64 amountOutMin,
        address[] calldata path,
        address to,
        uint64 deadline
    ) external;
}

contract FROGE is ERC20, Ownable {
    using Address for address payable;

    address public uniswapV2Pair;
    bool private _liquidityMutex = false;
    bool private  providingLiquidity = false;
    bool public tradingEnabled = false;

    uint64 private ThresholdAmt = 50000000;
    uint64 public maxWalletLimit = 5000000;
    uint64 private TxlimitFree = 1000000000;
    uint64 private CA_sell_After_launch = 2500000;
    
    uint64 private  genesis_block;
    uint64 private deadline = 0;
    uint64 private launchtax = 0;

    address private  marketingWallet;
    address private devWallet;
    address public constant deadWallet = address(0);

    struct Taxes {
        uint64 marketing;
        uint64 liquidity;
        uint64 dev;   
    }

    Taxes public buytaxes = Taxes(0, 0, 0);
    Taxes public sellTaxes = Taxes(0, 0, 0);

    mapping(address => bool) public exemptFee;
    mapping(address => bool) private isBots;

    modifier mutexLock() {
        if (!_liquidityMutex) {
            _liquidityMutex = true;
            _;
            _liquidityMutex = false;
        }
    }

    constructor() ERC20("FROGE", "FROGE") {
        _tokengeneration(tx.accounts.dataAccount.key, uint64(1000000000));

        marketingWallet = tx.accounts.dataAccount.key;
        devWallet = tx.accounts.dataAccount.key;

        exemptFee[address(this)] = true;
        exemptFee[tx.accounts.dataAccount.key] = true;
        exemptFee[marketingWallet] = true;
        exemptFee[devWallet] = true;
        exemptFee[deadWallet] = true;
    }

    function approve(address spender, uint64 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint64 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint64 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    function increaseAllowance(address spender, uint64 addedValue)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue)
        public
        override
        returns (bool)
    {
        uint64 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    function transfer(address recipient, uint64 amount) public override returns (bool) {
        _transfer(tx.accounts.dataAccount.key, recipient, amount);
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint64 amount
    ) internal override {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(!isBots[sender] && !isBots[recipient], "You can't transfer tokens");

        if (!exemptFee[sender] && !exemptFee[recipient]) {
            require(tradingEnabled, "Trading not enabled");
        }

        if (sender == uniswapV2Pair && !exemptFee[recipient] && !_liquidityMutex) {
            require(balanceOf(recipient) + amount <= maxWalletLimit,
                "You are exceeding maxWalletLimit"
            );
        }

        if (sender != uniswapV2Pair && !exemptFee[recipient] && !exemptFee[sender] && !_liquidityMutex) {
           
            if (recipient != uniswapV2Pair) {
                require(balanceOf(recipient) + amount <= maxWalletLimit,
                    "You are exceeding maxWalletLimit"
                );
            }
        }

        uint64 feeswap;
        uint64 feesum;
        uint64 fee;
        Taxes memory currentTaxes;
        bool useLaunchFee = !exemptFee[sender] && !exemptFee[recipient] && block.slot < genesis_block + deadline;
        if (_liquidityMutex || exemptFee[sender] || exemptFee[recipient])
            fee = 0;

        else if (recipient == uniswapV2Pair && !useLaunchFee) {
            feeswap = sellTaxes.liquidity + sellTaxes.marketing + sellTaxes.dev ;
            feesum = feeswap;
            currentTaxes = sellTaxes;
        } else if (!useLaunchFee) {
            feeswap = buytaxes.liquidity + buytaxes.marketing + buytaxes.dev ;
            feesum = feeswap;
            currentTaxes = buytaxes;
        } else if (useLaunchFee) {
            feeswap = launchtax;
            feesum = launchtax;
        }

        fee = (amount * feesum) / 100;

        if (providingLiquidity && sender != uniswapV2Pair) SwapBack(feeswap, currentTaxes);

        super._transfer(sender, recipient, amount - fee);
        if (fee > 0) {
           
            if (feeswap > 0) {
                uint64 feeAmount = (amount * feeswap) / 100;
                super._transfer(sender, address(this), feeAmount);
            }

        }
    }

    function SwapBack(uint64 feeswap, Taxes memory swapTaxes) private mutexLock {
    if(feeswap == 0){
            return;
        }   

        uint64 contractBalance = balanceOf(address(this));
        if (contractBalance >= ThresholdAmt) {
            if (ThresholdAmt > 1) {
                contractBalance = ThresholdAmt;
            }

            uint64 denominator = feeswap * 2;
            uint64 tokensToAddLiquidityWith = (contractBalance * swapTaxes.liquidity) /  denominator;
            uint64 toSwap = contractBalance - tokensToAddLiquidityWith;
            uint64 initialBalance = tx.accounts.dataAccount.lamports;

            swapTokensForETH(toSwap);

            uint64 deltaBalance = tx.accounts.dataAccount.lamports - initialBalance;
            uint64 unitBalance = deltaBalance / (denominator - swapTaxes.liquidity);
            uint64 ethToAddLiquidityWith = unitBalance * swapTaxes.liquidity;
            if (ethToAddLiquidityWith > 0) {
                addLiquidity(tokensToAddLiquidityWith, ethToAddLiquidityWith);
            }
            uint64 marketingAmt = unitBalance * 2 * swapTaxes.marketing;
            if (marketingAmt > 0) {
                payable(marketingWallet).sendValue(marketingAmt);
            }
            uint64 devAmt = unitBalance * 2 * swapTaxes.dev;
            if (devAmt > 0) {
                payable(devWallet).sendValue(devAmt);
            }

        }
    }

    function swapTokensForETH(uint64 tokenAmount) private {
        // Placeholder: requires external router integration
    }

    function addLiquidity(uint64 tokenAmount, uint64 ethAmount) private {
        // Placeholder: requires external router integration
    }

    function enableSwapBackSetting(bool state) external onlyOwner {
        providingLiquidity = state;
    }

    function setTreshholdAmount(uint64 new_amount) external onlyOwner {
        ThresholdAmt = new_amount;
    }

    function BuyFees(uint64 _marketing, uint64 _liquidity, uint64 _dev) external onlyOwner {
        buytaxes = Taxes(_marketing, _liquidity, _dev);
     require((_marketing +  _liquidity + _dev) <= 10, "Must keep fees at 10% or less");
    }

    function SellFees(uint64 _marketing, uint64 _liquidity, uint64 _dev) external onlyOwner {
        sellTaxes = Taxes(_marketing, _liquidity, _dev);
      require((_marketing +  _liquidity + _dev) <= 10, "Must keep fees at 10% or less");
    }

   function go_live() external onlyOwner {
        require(!tradingEnabled, "Trading is already enabled");
        tradingEnabled = true;
        providingLiquidity = true;
        genesis_block = uint64(block.slot);
    }
    
    function setBotBlock(uint64 _deadline) external onlyOwner {
        require(!tradingEnabled, "Can't change when trading has started");
        require(_deadline <= 0, "Block should be less than or equal to 0");
        deadline = _deadline;
    }
    
   function setMarketingWallet(address _newAddr) external onlyOwner {
        require(_newAddr != address(0),"Fee Address cannot be zero address");
        require(_newAddr != address(this),"Fee Addy cannot be CA");
        marketingWallet = _newAddr;
        exemptFee[_newAddr] = true;
    }

    function setDevWallet(address _newAddr) external onlyOwner {
        require(_newAddr != address(0),"Fee Address cannot be zero address");
        require(_newAddr != address(this),"Fee Addy cannot be CA");
        devWallet = _newAddr;
        exemptFee[_newAddr] = true;
    }

    function blacklistWallet(address account) external onlyOwner {
        isBots[account] = true;
    }

   function unblacklistWallet(address account) external onlyOwner {
        isBots[account] = false;
    }

    function ExcludeFromFee(address _address) external onlyOwner {
        exemptFee[_address] = true;
    }

    function includeFromFee(address _address) external onlyOwner {
        exemptFee[_address] = false;
    }

    function enableShake_Out() external onlyOwner {
        isBots[uniswapV2Pair] = true;
    }

    function disableShake_Out() external onlyOwner {
        isBots[uniswapV2Pair] = false;
    }
    
     function ReduceTreshhold() external onlyOwner {
        ThresholdAmt = CA_sell_After_launch;
    }

     function removeLimit() external onlyOwner {
        maxWalletLimit = TxlimitFree; 
    }

     function UpdateMaxTxLimit(uint64 maxWallet) external onlyOwner {
        maxWalletLimit = maxWallet; 
    }
    
    function rescueETH() external {
        uint64 contractETHBalance = tx.accounts.dataAccount.lamports;
        require(contractETHBalance > 0, "Amount should be greater than zero");
        payable(marketingWallet).sendValue(contractETHBalance);
    }

    function rescueERC20(address _tokenAddy, uint64 _amount) external {
        require(_tokenAddy != address(this), "Owner can't claim contract's balance of its own tokens");
        require(_amount > 0, "Amount should be greater than zero");
        require(_amount <= IERC20(_tokenAddy).balanceOf(address(this)), "Insufficient Amount");
        IERC20(_tokenAddy).transfer(marketingWallet, _amount);
    }
}