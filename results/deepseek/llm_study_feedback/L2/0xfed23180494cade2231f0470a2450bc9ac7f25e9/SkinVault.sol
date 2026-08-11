// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts[0].key;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: invalid owner");
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: unauthorized");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: invalid owner");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract Pausable is Context {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

interface IERC20Errors {
    // Errors are not supported as custom errors on Solana, using require strings instead.
}

interface IERC721Errors {
    // Errors are not supported as custom errors on Solana, using require strings instead.
}

interface IERC1155Errors {
    // Errors are not supported as custom errors on Solana, using require strings instead.
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

abstract contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: invalid sender");
        require(to != address(0), "ERC20: invalid receiver");
        _update(from, to, value);
    }

    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            require(fromBalance >= value, "ERC20: insufficient balance");
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "ERC20: invalid receiver");
        _update(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: invalid sender");
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        require(owner != address(0), "ERC20: invalid approver");
        require(spender != address(0), "ERC20: invalid spender");
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

// Forward declaration of SKINDEX interface to break circular dependency
interface ISKINDEX {
    function totalSupply() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

contract SKINDEX is ERC20, Ownable {
    address public manager;

    constructor(address initialOwner)
        ERC20("SkinVault ETF", "SKINDEX")
        Ownable(initialOwner)
    {}

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    function mint(address to, uint256 amount) external {
        require(tx.accounts[0].key == manager || tx.accounts[0].key == owner(), "Only owner/manager can mint");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(tx.accounts[0].key == manager, "Only manager can burn");
        _burn(from, amount);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

contract SkinVault is Ownable, Pausable, ReentrancyGuard {
    ISKINDEX public immutable skindex;
    address public vaultManager;
    address public developer;
    address public ethereumWallet;

    uint256 public skinsVal;
    uint256 public btcVal;

    uint256 public devFeeBP  = 100;
    uint256 public mintFeeBP = 0;
    uint256 public burnFeeBP = 500;

    uint256 public btcPoolBP  = 1000;
    uint256 public skinPoolBP = 8500;

    event AddressUpdated(string indexed valueType, address newAddress);
    event ValueUpdated(string indexed valueType, uint256 newValue);
    event EthReceivedByContract(uint256 ethValue);
    event EthSentFromContract(string indexed to, uint256 ethValue);
    event BoughtOffChainAsset(string indexed valueType, uint256 newValue);
    event SoldOffChainAsset(string indexed valueType, uint256 newValue);
    event PoolAllocation(int256 ethDelta, int256 btcDelta, int256 skinsDelta, uint256 navAfter);
    event Minted(address indexed user, uint256 ethIn, uint256 tokensToUser);
    event Burned(address indexed user, uint256 tokensBurned, uint256 ethOut);
    event RefillContractEth();

    modifier onlyManager() {
        require(tx.accounts[0].key == owner() || tx.accounts[0].key == vaultManager, "Not authorized");
        _;
    }

    function pause() external onlyManager { _pause(); }
    function unpause() external onlyManager { _unpause(); }

    constructor(address _initialOwner, address _skindex, address _EthWallet) Ownable(_initialOwner) {
        require(_initialOwner != address(0), "Dev address zero");
        skindex = ISKINDEX(_skindex);
        developer = _initialOwner;
        ethereumWallet = _EthWallet;
    }

    function setVaultManager(address manager) external onlyManager {
        vaultManager = manager;
        emit AddressUpdated("Vault Manager", vaultManager);
    }

    function setDeveloper(address devWallet) external onlyManager {
        require(devWallet != address(0), "Dev wallet zero");
        developer = devWallet;
        emit AddressUpdated("Dev Wallet", devWallet);
    }

    function setEthWallet(address ethWallet) external onlyManager {
        ethereumWallet = ethWallet;
        emit AddressUpdated("Eth Wallet", ethWallet);
    }

    function setValSkins(uint256 skinsValue) external onlyManager whenNotPaused {
        skinsVal = skinsValue;
        emit ValueUpdated("SKINS", skinsVal);
    }

    function setValBtc(uint256 btcValue) external onlyManager whenNotPaused {
        btcVal = btcValue;
        emit ValueUpdated("BTC", btcVal);
    }

    function setDevFeeBP(uint256 newDevFeeBP) external onlyManager whenNotPaused {
        require(newDevFeeBP <= 500, "Dev fee too high");
        devFeeBP = newDevFeeBP;
        emit ValueUpdated("Dev Fee", devFeeBP);
    }

    function setMintFeeBP(uint256 newMintFeeBP) external onlyManager whenNotPaused {
        require(newMintFeeBP <= 500, "Mint fee too high");
        mintFeeBP = newMintFeeBP;
        emit ValueUpdated("Mint Fee", mintFeeBP);
    }

    function setBurnFeeBP(uint256 newBurnFeeBP) external onlyManager whenNotPaused {
        require(newBurnFeeBP <= 1000, "Burn fee too high");
        burnFeeBP = newBurnFeeBP;
        emit ValueUpdated("Burn Fee", burnFeeBP);
    }

    function setSkinPoolBP(uint256 newSkinBP) external onlyManager whenNotPaused {
        require(newSkinBP + btcPoolBP <= 10000, "Total allocation exceeds 100%");
        skinPoolBP = newSkinBP;
        emit ValueUpdated("Skin Pool Allocation", skinPoolBP);
    }

    function setBtcPoolBP(uint256 newBtcBP) external onlyManager whenNotPaused {
        require(newBtcBP + skinPoolBP <= 10000, "Total allocation exceeds 100%");
        btcPoolBP = newBtcBP;
        emit ValueUpdated("BTC Pool Allocation", btcPoolBP);
    }

    function setPools(uint256 newSkinBP, uint256 newBtcBP) external onlyManager whenNotPaused {
        require(newSkinBP + newBtcBP <= 10000, "Total allocation exceeds 100%");
        skinPoolBP = newSkinBP;
        btcPoolBP = newBtcBP;
        emit ValueUpdated("BTC Pool Allocation", btcPoolBP);
        emit ValueUpdated("Skin Pool Allocation", skinPoolBP);
    }

    function getSkinTargetValue() public view returns (uint256) {
        return skinPoolBP * NAV();
    }

    function getSkinPoolBP() public view returns (uint256) {
        return skinPoolBP;
    }

    function getBtcTargetValue() public view returns (uint256) {
        return btcPoolBP * NAV();
    }

    function getBtcPoolBP() public view returns (uint256) {
        return btcPoolBP;
    }

    function getEthTargetValue() public view returns (uint256) {
        return (10000 - skinPoolBP - btcPoolBP) * NAV();
    }

    function getEthPoolBP() public view returns (uint256) {
        return 10000 - skinPoolBP - btcPoolBP;
    }

    // Solana does not support receive() functions. Use a dedicated payable function instead.
    // receive() external payable { mint(); }

    function manualBalancePools() external onlyManager
    returns (int256, int256, int256, uint256) {
        (int256 deltaEth, int256 deltaBtc, int256 deltaSkins, uint256 futureNAV) = _calculatePoolDeltas(true, 0);
        emit PoolAllocation(deltaEth, deltaBtc, deltaSkins, futureNAV);
        return (deltaEth, deltaBtc, deltaSkins, futureNAV);
    }

    function autoBalancePools(bool isMint, uint256 amountEth) internal
    returns (int256, int256, int256, uint256) {
        (int256 deltaEth, int256 deltaBtc, int256 deltaSkins, uint256 futureNAV) = _calculatePoolDeltas(isMint, amountEth);
        emit PoolAllocation(deltaEth, deltaBtc, deltaSkins, futureNAV);
        return (deltaEth, deltaBtc, deltaSkins, futureNAV);
    }

    function _mulDiv(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        require(z != 0, "Div by zero");
        return (x * y) / z;
    }

    function _calculatePoolDeltas(bool isMint, uint256 amountEth ) internal view
    returns (int256 deltaEth, int256 deltaBtc, int256 deltaSkins, uint256 futureNAV) {
        uint256 currNAV = NAV();
        futureNAV = isMint ? (currNAV + amountEth) : (currNAV > amountEth ? currNAV - amountEth : 0);

        uint256 targetSkins = _mulDiv(futureNAV, skinPoolBP, 10000);
        uint256 targetBtc   = _mulDiv(futureNAV, btcPoolBP , 10000);
        uint256 targetEth   =  futureNAV - targetSkins - targetBtc;

        deltaEth   = int256(targetEth)   - int256(ETH());
        deltaBtc   = int256(targetBtc)   - int256(btcVal);
        deltaSkins = int256(targetSkins) - int256(skinsVal);
    }

    // Public mint function that accepts lamports via the Solana runtime.
    // The user must send lamports to this function call.
    function mint() public payable whenNotPaused nonReentrant {
        uint256 value = tx.accounts[0].lamports;
        require(value > 0, "No ETH sent");
        require(NAV() > 0, "No Value could be established");

        uint256 rawMint = _mulDiv(value, SUPPLY(), NAV());

        uint256 dFee = _mulDiv(rawMint, devFeeBP , 10000);
        uint256 mFee = _mulDiv(rawMint, mintFeeBP, 10000);

        uint256 toUser = rawMint - dFee - mFee;

        skindex.mint(tx.accounts[0].key, toUser);
        if (dFee > 0) skindex.mint(developer, dFee);

        emit Minted(tx.accounts[0].key, value, toUser);
        autoBalancePools(true, value);
    }

    function mintTo(address recipient, uint256 ethValue) external onlyManager whenNotPaused nonReentrant {
        require(ethValue > 0, "No value");
        require(NAV() > 0, "No Value could be established");

        uint256 rawMint = _mulDiv(ethValue, SUPPLY(), NAV());

        uint256 dFee = _mulDiv(rawMint, devFeeBP , 10000);
        uint256 mFee = _mulDiv(rawMint, mintFeeBP, 10000);

        uint256 toUser = rawMint - dFee - mFee;

        skindex.mint(recipient, toUser);
        if (dFee > 0) skindex.mint(developer, dFee);

        emit Minted(recipient, ethValue, toUser);
        autoBalancePools(true, ethValue);
    }

    function burn(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount zero");

        uint256 ethValue = _mulDiv(amount, NAV(), SUPPLY());
        uint256 fee      = _mulDiv(ethValue, burnFeeBP, 10000);
        uint256 payout   = ethValue - fee;

        uint256 contractEth = tx.accounts[0].lamports;

        if (contractEth < payout) {
            emit RefillContractEth();
            revert("Not enough ETH in contract for burn payout");
        }

        skindex.burn(tx.accounts[0].key, amount);
        // Solana CPI cannot transfer native value directly. Use a transfer via system program.
        // For simplicity, we assume the contract account can transfer lamports.
        payable(tx.accounts[0].key).transfer(payout);

        emit Burned(tx.accounts[0].key, amount, payout);
        autoBalancePools(false, payout);
    }

    function SUPPLY() internal view returns (uint256) {
        return skindex.totalSupply();
    }

    function ETH() internal view returns (uint256) {
        // On Solana, balance is obtained via tx.accounts. We assume the contract account is at index 0.
        // For ethereumWallet, we cannot directly query its balance. We'll use a stored value or assume it's tracked off-chain.
        // As a simplification, we use the contract's lamports only. In a real implementation, you'd need to track ETH-like balances differently.
        return tx.accounts[0].lamports;
    }

    function NAV() internal view returns (uint256) {
        return skinsVal + btcVal + ETH();
    }

    function getBalETH() external view returns (uint256) {
        return ETH();
    }

    function getNAV() external view returns (uint256) {
        return NAV();
    }

    function getNavPerToken() external view returns (uint256) {
        uint256 supply = SUPPLY();
        return supply == 0 ? 0 : _mulDiv(NAV(), 1e18, supply);
    }

    function recieveEth() external payable onlyManager whenNotPaused nonReentrant {
        uint256 value = tx.accounts[0].lamports;
        require(value > 0, "No ETH sent");
        emit EthReceivedByContract(value);
    }

    function sendEthToWallet(uint256 ETHValue) external onlyManager nonReentrant {
        require(ETHValue <= tx.accounts[0].lamports, "Insufficient ETH");
        payable(ethereumWallet).transfer(ETHValue);
        emit EthSentFromContract("Wallet", ETHValue);
    }

    function EthToBtc(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        btcVal += ETHValue;
        emit BoughtOffChainAsset("BTC", ETHValue);
    }

    function BtcToEth(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        btcVal -= ETHValue;
        emit SoldOffChainAsset("BTC", ETHValue);
    }

    function EthToSkins(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        skinsVal += ETHValue;
        emit BoughtOffChainAsset("Skins", ETHValue);
    }

    function SkinsToEth(uint256 ETHValue) external onlyManager whenNotPaused {
        require(ETHValue > 0, "No ETH sent");
        skinsVal -= ETHValue;
        emit SoldOffChainAsset("Skins", ETHValue);
    }
}