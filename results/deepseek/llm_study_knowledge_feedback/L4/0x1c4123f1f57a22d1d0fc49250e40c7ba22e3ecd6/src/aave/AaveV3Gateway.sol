import { AccountMeta } from 'solana';

// Interfaces
interface IERC20 {
    function balanceOf(address account) external view returns (uint64);
    function totalSupply() external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transfer(address to, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}

interface IPool {
    function getReserveData(address asset) external view returns (ReserveDataLegacy memory);
    function supply(address asset, uint64 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint64 amount, address to) external returns (uint64);
}

struct ReserveConfigurationMap {
    uint256 data;
}

struct ReserveDataLegacy {
    ReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 variableBorrowIndex;
    uint128 currentLiquidityRate;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint8 id;
}

contract AaveV3Gateway {
    uint256 private constant ACTIVE_BIT = 56;
    uint256 private constant FROZEN_BIT = 57;
    uint256 private constant PAUSED_BIT = 60;
    uint256 private constant DECIMALS_SHIFT = 48;
    uint256 private constant DECIMALS_MASK = 0xFF;
    uint256 private constant SUPPLY_CAP_SHIFT = 116;
    uint256 private constant CAP_BITS = 36;
    uint256 private constant CAP_MASK = (uint256(1) << CAP_BITS) - 1;

    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    address public pool;
    address public aToken;
    uint16 public referralCode;

    string private _name;
    string private _symbol;
    address private _asset;
    uint64 private _totalSupply;
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    bool private _initialized;
    bool private _reentrancyLock;

    event ReferralCodeUpdated(uint16 newReferralCode);
    event Deposit(address indexed sender, address indexed owner, uint64 assets, uint64 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint64 assets, uint64 shares);

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _;
    }

    modifier nonReentrant() {
        require(!_reentrancyLock, "Reentrant call");
        _reentrancyLock = true;
        _;
        _reentrancyLock = false;
    }

    modifier onlyRole(bytes32 role) {
        require(role == DEFAULT_ADMIN_ROLE, "AccessControl: sender not admin");
        _;
    }

    function initialize(
        address _assetParam,
        string calldata _nameParam,
        string calldata _symbolParam,
        address _pool,
        address _aToken,
        address _admin,
        uint16 _referralCode
    ) external initializer {
        require(_admin != address(0), "ZeroAddress");
        _name = _nameParam;
        _symbol = _symbolParam;
        _asset = _assetParam;

        require(_pool != address(0), "ZeroAddress");
        pool = _pool;

        require(_aToken != address(0), "ZeroAddress");
        ReserveDataLegacy memory rd = IPool(_pool).getReserveData(_assetParam);
        require(rd.aTokenAddress == _aToken, "AddressMismatch");
        aToken = _aToken;
        referralCode = _referralCode;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 6;
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) external returns (bool) {
        address sender = tx.accounts.dataAccount.key;
        _allowances[sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint64 amount) external returns (bool) {
        address sender = tx.accounts.dataAccount.key;
        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint64 amount) external returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        uint64 currentAllowance = _allowances[from][spender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _allowances[from][spender] = currentAllowance - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        uint64 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to zero");
        _totalSupply += amount;
        _balances[account] += amount;
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from zero");
        uint64 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
    }

    function _spendAllowance(address owner, address spender, uint64 amount) internal {
        uint64 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _allowances[owner][spender] = currentAllowance - amount;
        }
    }

    function asset() public view returns (address) {
        return _asset;
    }

    function totalAssets() public view returns (uint64) {
        return IERC20(aToken).balanceOf(address(this));
    }

    function convertToShares(uint64 assets) public view returns (uint64) {
        uint64 supply = _totalSupply;
        if (supply == 0) {
            return assets;
        }
        uint64 total = totalAssets();
        if (total == 0) {
            return assets;
        }
        return uint64((uint128(assets) * uint128(supply)) / uint128(total));
    }

    function convertToAssets(uint64 shares) public view returns (uint64) {
        uint64 supply = _totalSupply;
        if (supply == 0) {
            return shares;
        }
        uint64 total = totalAssets();
        if (total == 0) {
            return shares;
        }
        return uint64((uint128(shares) * uint128(total)) / uint128(supply));
    }

    function previewDeposit(uint64 assets) public view returns (uint64) {
        return convertToShares(assets);
    }

    function previewMint(uint64 shares) public view returns (uint64) {
        uint64 supply = _totalSupply;
        if (supply == 0) {
            return shares;
        }
        uint64 total = totalAssets();
        if (total == 0) {
            return shares;
        }
        return uint64((uint128(shares) * uint128(total) + uint128(supply) - 1) / uint128(supply));
    }

    function previewWithdraw(uint64 assets) public view returns (uint64) {
        uint64 supply = _totalSupply;
        if (supply == 0) {
            return assets;
        }
        uint64 total = totalAssets();
        if (total == 0) {
            return assets;
        }
        return uint64((uint128(assets) * uint128(supply) + uint128(total) - 1) / uint128(total));
    }

    function previewRedeem(uint64 shares) public view returns (uint64) {
        return convertToAssets(shares);
    }

    function _bit(uint256 data, uint256 bit) internal pure returns (bool) {
        return ((data >> bit) & 1) == 1;
    }

    function _decimals(uint256 data) internal pure returns (uint8) {
        return uint8((data >> DECIMALS_SHIFT) & DECIMALS_MASK);
    }

    function _supplyCapWhole(uint256 data) internal pure returns (uint256) {
        return (data >> SUPPLY_CAP_SHIFT) & CAP_MASK;
    }

    function setReferralCode(uint16 _referralCode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        referralCode = _referralCode;
        emit ReferralCodeUpdated(_referralCode);
    }

    function maxDeposit(address) public view returns (uint64) {
        ReserveDataLegacy memory rd = IPool(pool).getReserveData(asset());
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isFrozen = _bit(c, FROZEN_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isFrozen && !isPaused)) return 0;
        uint256 supplyCapWhole = _supplyCapWhole(c);
        if (supplyCapWhole == 0) return type(uint64).max;
        uint8 dec = _decimals(c);
        uint64 supplyCap = uint64(supplyCapWhole * 10 ** uint256(dec));
        uint64 totalSupplyAToken = IERC20(aToken).totalSupply();
        if (totalSupplyAToken >= supplyCap) return 0;
        return supplyCap - totalSupplyAToken;
    }

    function deposit(uint64 _assets, address _receiver) external nonReentrant returns (uint64) {
        require(_assets > 0, "ZeroAssets");
        uint64 shares = previewDeposit(_assets);
        _mint(_receiver, shares);
        address sender = tx.accounts.dataAccount.key;
        IERC20(_asset).transferFrom(sender, address(this), _assets);
        IERC20(_asset).approve(pool, _assets);
        IPool(pool).supply(_asset, _assets, address(this), referralCode);
        emit Deposit(sender, _receiver, _assets, shares);
        return shares;
    }

    function maxMint(address) public view returns (uint64) {
        ReserveDataLegacy memory rd = IPool(pool).getReserveData(asset());
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isFrozen = _bit(c, FROZEN_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isFrozen && !isPaused)) return 0;
        uint256 supplyCapWhole = _supplyCapWhole(c);
        if (supplyCapWhole == 0) return type(uint64).max;
        uint8 dec = _decimals(c);
        uint64 supplyCap = uint64(supplyCapWhole * 10 ** uint256(dec));
        uint64 totalSupplyAToken = IERC20(aToken).totalSupply();
        if (totalSupplyAToken >= supplyCap) return 0;
        return convertToShares(supplyCap - totalSupplyAToken);
    }

    function mint(uint64 _shares, address _receiver) external nonReentrant returns (uint64) {
        require(_shares > 0, "ZeroShares");
        uint64 assets = previewMint(_shares);
        _mint(_receiver, _shares);
        address sender = tx.accounts.dataAccount.key;
        IERC20(_asset).transferFrom(sender, address(this), assets);
        IERC20(_asset).approve(pool, assets);
        IPool(pool).supply(_asset, assets, address(this), referralCode);
        emit Deposit(sender, _receiver, assets, _shares);
        return assets;
    }

    function maxWithdraw(address _owner) public view returns (uint64) {
        ReserveDataLegacy memory rd = IPool(pool).getReserveData(asset());
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isPaused)) return 0;
        uint64 availableLiquidity = IERC20(_asset).balanceOf(aToken);
        uint64 ownerAssets = previewRedeem(balanceOf(_owner));
        return availableLiquidity < ownerAssets ? availableLiquidity : ownerAssets;
    }

    function withdraw(
        uint64 _assets,
        address _receiver,
        address _owner
    ) external nonReentrant returns (uint64) {
        require(_assets > 0, "ZeroAssets");
        uint64 maxAssets = maxWithdraw(_owner);
        require(_assets <= maxAssets, "ERC4626ExceededMaxWithdraw");
        uint64 shares = previewWithdraw(_assets);
        address sender = tx.accounts.dataAccount.key;
        if (sender != _owner) _spendAllowance(_owner, sender, shares);
        _burn(_owner, shares);
        IPool(pool).withdraw(_asset, _assets, _receiver);
        emit Withdraw(sender, _receiver, _owner, _assets, shares);
        return shares;
    }

    function maxRedeem(address _owner) public view returns (uint64) {
        ReserveDataLegacy memory rd = IPool(pool).getReserveData(asset());
        uint256 c = rd.configuration.data;
        bool isActive = _bit(c, ACTIVE_BIT);
        bool isPaused = _bit(c, PAUSED_BIT);
        if (!(isActive && !isPaused)) return 0;
        uint64 ownerShares = balanceOf(_owner);
        uint64 availableLiquidity = IERC20(_asset).balanceOf(aToken);
        uint64 availableShares = convertToShares(availableLiquidity);
        return availableShares < ownerShares ? availableShares : ownerShares;
    }

    function redeem(uint64 _shares, address _receiver, address _owner) external nonReentrant returns (uint64) {
        require(_shares > 0, "ZeroShares");
        uint64 maxShares_ = maxRedeem(_owner);
        require(_shares <= maxShares_, "ERC4626ExceededMaxRedeem");
        address sender = tx.accounts.dataAccount.key;
        if (sender != _owner) _spendAllowance(_owner, sender, _shares);
        uint64 assets = previewRedeem(_shares);
        require(assets > 0, "ZeroAssets");
        _burn(_owner, _shares);
        IPool(pool).withdraw(_asset, assets, _receiver);
        emit Withdraw(sender, _receiver, _owner, assets, _shares);
        return assets;
    }
}