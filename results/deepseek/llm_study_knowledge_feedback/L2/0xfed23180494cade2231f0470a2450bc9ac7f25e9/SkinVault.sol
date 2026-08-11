// SPDX-License-Identifier: MIT

import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes) {
        return tx.data;
    }

    function _contextSuffixLength() internal pure returns (uint64) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function _checkOwner() internal view {
        if (owner() != _msgSender()) {
            revert("Ownable: unauthorized");
        }
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) {
            revert("Ownable: invalid owner");
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
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

    function paused() public view returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view {
        require(!paused(), "Pausable: paused");
    }

    function _requirePaused() internal view {
        require(paused(), "Pausable: not paused");
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string);
    function symbol() external view returns (string);
    function decimals() external view returns (uint8);
}

abstract contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    uint64 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 value) public returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 value) public returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) public returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint64 value) internal {
        if (from == address(0)) {
            revert("ERC20: invalid sender");
        }
        if (to == address(0)) {
            revert("ERC20: invalid receiver");
        }
        _update(from, to, value);
    }

    function _update(address from, address to, uint64 value) internal {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint64 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert("ERC20: insufficient balance");
            }
            _balances[from] = fromBalance - value;
        }

        if (to == address(0)) {
            _totalSupply -= value;
        } else {
            _balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint64 value) internal {
        if (account == address(0)) {
            revert("ERC20: invalid receiver");
        }
        _update(address(0), account, value);
    }

    function _burn(address account, uint64 value) internal {
        if (account == address(0)) {
            revert("ERC20: invalid sender");
        }
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint64 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint64 value, bool emitEvent) internal {
        if (owner == address(0)) {
            revert("ERC20: invalid approver");
        }
        if (spender == address(0)) {
            revert("ERC20: invalid spender");
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint64 value) internal {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint64).max) {
            if (currentAllowance < value) {
                revert("ERC20: insufficient allowance");
            }
            _approve(owner, spender, currentAllowance - value, false);
        }
    }
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

    function mint(address to, uint64 amount) external {
        require(tx.accounts.dataAccount.key == manager || tx.accounts.dataAccount.key == owner(), "Only owner/manager can mint");
        _mint(to, amount);
    }

    function burn(address from, uint64 amount) external {
        require(tx.accounts.dataAccount.key == manager, "Only manager can burn");
        _burn(from, amount);
    }
}

abstract contract ReentrancyGuard {
    uint64 private constant _NOT_ENTERED = 1;
    uint64 private constant _ENTERED = 2;
    uint64 private _status;

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
    SKINDEX public immutable skindex;
    address public vaultManager;
    address public developer;
    address public ethereumWallet;

    uint64 public skinsVal;
    uint64 public btcVal;

    uint64 public devFeeBP  = 100;
    uint64 public mintFeeBP = 0;
    uint64 public burnFeeBP = 500;

    uint64 public btcPoolBP  = 1000;
    uint64 public skinPoolBP = 8500;

    event AddressUpdated(string indexed valueType, address newAddress);
    event ValueUpdated(string indexed valueType, uint64 newValue);
    event EthReceivedByContract(uint64 ethValue);
    event EthSentFromContract(string indexed to, uint64 ethValue);
    event BoughtOffChainAsset(string indexed valueType, uint64 newValue);
    event SoldOffChainAsset(string indexed valueType, uint64 newValue);
    event PoolAllocation(int64 ethDelta, int64 btcDelta, int64 skinsDelta, uint64 navAfter);
    event Minted(address indexed user, uint64 ethIn, uint64 tokensToUser);
    event Burned(address indexed user, uint64 tokensBurned, uint64 ethOut);
    event RefillContractEth();

    modifier onlyManager() {
        require(tx.accounts.dataAccount.key == owner() || tx.accounts.dataAccount.key == vaultManager, "Not authorized");
        _;
    }

    function pause() external onlyManager { _pause(); }
    function unpause() external onlyManager { _unpause(); }

    constructor(address initialOwner, address _skindex) Ownable(initialOwner) {
        skindex = SKINDEX(_skindex);
    }

    function setVaultManager(address _vaultManager) external onlyOwner {
        vaultManager = _vaultManager;
        emit AddressUpdated("vaultManager", _vaultManager);
    }

    function setDeveloper(address _developer) external onlyOwner {
        developer = _developer;
        emit AddressUpdated("developer", _developer);
    }

    function setEthereumWallet(address _ethereumWallet) external onlyOwner {
        ethereumWallet = _ethereumWallet;
        emit AddressUpdated("ethereumWallet", _ethereumWallet);
    }

    function setDevFeeBP(uint64 _devFeeBP) external onlyOwner {
        devFeeBP = _devFeeBP;
        emit ValueUpdated("devFeeBP", _devFeeBP);
    }

    function setMintFeeBP(uint64 _mintFeeBP) external onlyOwner {
        mintFeeBP = _mintFeeBP;
        emit ValueUpdated("mintFeeBP", _mintFeeBP);
    }

    function setBurnFeeBP(uint64 _burnFeeBP) external onlyOwner {
        burnFeeBP = _burnFeeBP;
        emit ValueUpdated("burnFeeBP", _burnFeeBP);
    }

    function setBtcPoolBP(uint64 _btcPoolBP) external onlyOwner {
        btcPoolBP = _btcPoolBP;
        emit ValueUpdated("btcPoolBP", _btcPoolBP);
    }

    function setSkinPoolBP(uint64 _skinPoolBP) external onlyOwner {
        skinPoolBP = _skinPoolBP;
        emit ValueUpdated("skinPoolBP", _skinPoolBP);
    }

    function setSkinsVal(uint64 _skinsVal) external onlyManager {
        skinsVal = _skinsVal;
        emit ValueUpdated("skinsVal", _skinsVal);
    }

    function setBtcVal(uint64 _btcVal) external onlyManager {
        btcVal = _btcVal;
        emit ValueUpdated("btcVal", _btcVal);
    }

    function getNav() public view returns (uint64) {
        uint64 contractBalance = uint64(tx.accounts.dataAccount.lamports);
        return contractBalance + btcVal + skinsVal;
    }

    function mint(uint64 ethAmount) external nonReentrant whenNotPaused {
        require(ethAmount > 0, "Amount must be > 0");
        uint64 nav = getNav();
        uint64 totalSupply = skindex.totalSupply();
        uint64 tokensToMint;
        if (totalSupply == 0) {
            tokensToMint = ethAmount;
        } else {
            tokensToMint = (ethAmount * totalSupply) / nav;
        }
        require(tokensToMint > 0, "Mint amount too small");

        uint64 devFee = (ethAmount * devFeeBP) / 10000;
        uint64 mintFee = (ethAmount * mintFeeBP) / 10000;
        uint64 netEth = ethAmount - devFee - mintFee;

        if (devFee > 0 && developer != address(0)) {
            emit EthSentFromContract("devFee", devFee);
        }
        if (mintFee > 0 && ethereumWallet != address(0)) {
            emit EthSentFromContract("mintFee", mintFee);
        }

        skindex.mint(tx.accounts.dataAccount.key, tokensToMint);
        emit Minted(tx.accounts.dataAccount.key, ethAmount, tokensToMint);
    }

    function burn(uint64 tokenAmount) external nonReentrant whenNotPaused {
        require(tokenAmount > 0, "Amount must be > 0");
        uint64 nav = getNav();
        uint64 totalSupply = skindex.totalSupply();
        require(totalSupply > 0, "No supply");
        uint64 ethToReturn = (tokenAmount * nav) / totalSupply;
        require(ethToReturn > 0, "Burn amount too small");

        uint64 burnFee = (ethToReturn * burnFeeBP) / 10000;
        uint64 netEth = ethToReturn - burnFee;

        if (burnFee > 0 && ethereumWallet != address(0)) {
            emit EthSentFromContract("burnFee", burnFee);
        }

        skindex.burn(tx.accounts.dataAccount.key, tokenAmount);
        emit Burned(tx.accounts.dataAccount.key, tokenAmount, netEth);
    }

    function buyOffChainAsset(string calldata valueType, uint64 amount) external onlyManager {
        if (keccak256(bytes(valueType)) == keccak256(bytes("btc"))) {
            btcVal += amount;
        } else if (keccak256(bytes(valueType)) == keccak256(bytes("skins"))) {
            skinsVal += amount;
        }
        emit BoughtOffChainAsset(valueType, amount);
    }

    function sellOffChainAsset(string calldata valueType, uint64 amount) external onlyManager {
        if (keccak256(bytes(valueType)) == keccak256(bytes("btc"))) {
            require(btcVal >= amount, "Insufficient btcVal");
            btcVal -= amount;
        } else if (keccak256(bytes(valueType)) == keccak256(bytes("skins"))) {
            require(skinsVal >= amount, "Insufficient skinsVal");
            skinsVal -= amount;
        }
        emit SoldOffChainAsset(valueType, amount);
    }

    function refillContractEth() external onlyManager {
        emit RefillContractEth();
    }

    function receiveEth() external {
        emit EthReceivedByContract(0);
    }
}