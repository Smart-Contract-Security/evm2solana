// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Bot Version 3.21 (kolay sürüm)

// Sözleşmenin kullandığı küçük ERC20 arayüzü.
interface IERC20Minimal {
    function balanceOf(address who) external view returns (uint256);
    function transfer(address recipient, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

// Aave V3 tek varlık flash loan giriş noktası.
interface IAaveSimplePool {
    function flashLoanSimple(
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        uint16 referralCode
    ) external;
}

// Aave'in flash loan alıcısından beklediği callback.
interface IAaveSimpleFlashBorrower {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata data
    ) external returns (bool);
}

// Uniswap V2 tarzı router (her iki swap bacağında kullanılır).
interface IRouterV2Like {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 minAmountOut,
        address[] calldata route,
        address recipient,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

// Tutarsız dönüş davranışı olan tokenlar için ERC20 yardımcıları.
library TokenOps {
    error TokenCallReverted(address token);
    error TokenCallReturnedFalse(address token);

    function safeSend(IERC20Minimal token, address recipient, uint256 value) internal {
        _invoke(token, abi.encodeWithSelector(token.transfer.selector, recipient, value));
    }

    function safeApproveExact(IERC20Minimal token, address spender, uint256 value) internal {
        bytes memory payload = abi.encodeWithSelector(token.approve.selector, spender, value);
        if (!_invokeBool(token, payload)) {
            _invoke(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
            _invoke(token, payload);
        }
    }

    function _invoke(IERC20Minimal token, bytes memory payload) private {
        (bool ok, bytes memory ret) = address(token).call(payload);
        if (!ok) revert TokenCallReverted(address(token));
        if (ret.length > 0 && !abi.decode(ret, (bool))) {
            revert TokenCallReturnedFalse(address(token));
        }
    }

    function _invokeBool(IERC20Minimal token, bytes memory payload) private returns (bool) {
        (bool ok, bytes memory ret) = address(token).call(payload);
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }
}

// İki bacaklı flash-loan arbitraj sözleşmesi.
contract HonestFlashArbV2 is IAaveSimpleFlashBorrower {
    using TokenOps for IERC20Minimal;

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error BadPlan();
    error BadCallback();
    error LoanAlreadyOpen();
    error NoLoanOpen();
    error RouterNotAllowed(address router);
    error TokenNotAllowed(address token);
    error GainTooSmall();
    error ContractPaused();
    error MustBePaused();
    error NativeTransfersDisabled();

    // Aave callback'i içinde çözülen swap tarifi.
    struct ArbPlan {
        address router1;
        address router2;
        address[] path1;
        address[] path2;
        uint256 amountOutMin1;
        uint256 amountOutMin2;
        uint256 minProfit;
        uint256 deadline;
    }

    // =========================================================
    //  VARSAYILAN ADRESLER (Ethereum mainnet) - deploy'da sorulmaz
    // =========================================================
    // Aave V3 Pool
    address private constant DEFAULT_POOL =
        0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    // Uniswap V2 Router02
    address private constant ROUTER_UNISWAP =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // SushiSwap Router
    address private constant ROUTER_SUSHI =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    // WETH / USDC / DAI
    address private constant TOKEN_WETH =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant TOKEN_USDC =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant TOKEN_DAI =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Kalıcı ayarlar.
    address public immutable owner;
    address public immutable pool;

    // Çalışma zamanı anahtarları.
    bool public paused;
    bool public loanOpen;

    // İzin verilen router ve tokenlar.
    mapping(address => bool) public routerWhitelist;
    mapping(address => bool) public tokenWhitelist;

    // Flash callback doğrulaması için geçici değerler.
    bytes32 public activePlanHash;
    address public activeAsset;
    uint256 public activeAmount;
    uint256 public balanceBefore;

    event PauseStatusChanged(bool isPaused);
    event FlashRequested(address indexed asset, uint256 amount);
    event FlashCompleted(address indexed asset, uint256 amount, uint256 premium, uint256 profit);
    event TokenRecovered(address indexed token, address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenRunning() {
        if (paused) revert ContractPaused();
        _;
    }

    // Parametresiz constructor: tüm adresler kodun içinde sabit.
    // Remix'te deploy ederken hiçbir şey girmen gerekmez.
    constructor() {
        owner = msg.sender;
        pool = DEFAULT_POOL;

        // Router beyaz listesi
        routerWhitelist[ROUTER_UNISWAP] = true;
        routerWhitelist[ROUTER_SUSHI] = true;

        // Token beyaz listesi
        tokenWhitelist[TOKEN_WETH] = true;
        tokenWhitelist[TOKEN_USDC] = true;
        tokenWhitelist[TOKEN_DAI] = true;
    }

    // Stratejiyi durdur (acil durdurma).
    function pause() external onlyOwner {
        paused = true;
        emit PauseStatusChanged(true);
    }

    // Stratejiyi tekrar çalıştır.
    function unpause() external onlyOwner {
        paused = false;
        emit PauseStatusChanged(false);
    }

    // ---- BAŞLAT ----
    // Arbitrajı başlatır: flash loan alır, iki swap yapar, borcu öder.
    // Sadece owner, sadece duraklatılmamışken çağırabilir.
    function start(address asset, uint256 amount, ArbPlan calldata plan)
        external
        onlyOwner
        whenRunning
    {
        if (loanOpen) revert LoanAlreadyOpen();
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _checkPlan(asset, plan);

        uint256 startingBalance = IERC20Minimal(asset).balanceOf(address(this));
        bytes memory encodedPlan = abi.encode(plan);

        loanOpen = true;
        activePlanHash = keccak256(encodedPlan);
        activeAsset = asset;
        activeAmount = amount;
        balanceBefore = startingBalance;

        emit FlashRequested(asset, amount);

        IAaveSimplePool(pool).flashLoanSimple(address(this), asset, amount, encodedPlan, 0);

        if (loanOpen) revert BadCallback();
    }

    // Aave borç verdikten sonra bunu çağırır. Sen elle çağırmazsın.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata data
    ) external override whenRunning returns (bool) {
        if (msg.sender != pool) revert BadCallback();
        if (initiator != address(this)) revert BadCallback();
        if (!loanOpen) revert NoLoanOpen();

        if (asset != activeAsset || amount != activeAmount) revert BadCallback();
        if (keccak256(data) != activePlanHash) revert BadCallback();

        ArbPlan memory plan = abi.decode(data, (ArbPlan));
        _checkPlan(asset, plan);

        {
            uint256 currentBalance = IERC20Minimal(asset).balanceOf(address(this));
            if (currentBalance < balanceBefore + amount) revert BadCallback();
        }

        // Her iki swap bacağı stack derinlik sınırını aşmamak için ayrı fonksiyonda.
        _runSwaps(asset, amount, plan);

        uint256 debt = amount + premium;
        uint256 profit;
        {
            uint256 endingBalance = IERC20Minimal(asset).balanceOf(address(this));
            if (endingBalance < balanceBefore + debt + plan.minProfit) revert GainTooSmall();
            profit = endingBalance - balanceBefore - debt;
        }

        _resetLoanState();

        // Aave'in anapara + ücreti geri çekmesine izin ver.
        IERC20Minimal(asset).safeApproveExact(pool, debt);

        emit FlashCompleted(asset, amount, premium, profit);
        return true;
    }

    // İki arbitraj bacağı: borç alınan varlık -> köprü token -> borç alınan varlık.
    function _runSwaps(address asset, uint256 amount, ArbPlan memory plan) internal {
        // 1. bacak: borç alınan varlık -> köprü token.
        IERC20Minimal(asset).safeApproveExact(plan.router1, amount);

        uint256[] memory firstSwap = IRouterV2Like(plan.router1).swapExactTokensForTokens(
            amount, plan.amountOutMin1, plan.path1, address(this), plan.deadline
        );

        IERC20Minimal(asset).safeApproveExact(plan.router1, 0);

        uint256 bridgeAmount = firstSwap[firstSwap.length - 1];
        address bridgeToken = plan.path1[plan.path1.length - 1];

        // 2. bacak: köprü token -> orijinal borç alınan varlık.
        IERC20Minimal(bridgeToken).safeApproveExact(plan.router2, bridgeAmount);

        IRouterV2Like(plan.router2).swapExactTokensForTokens(
            bridgeAmount, plan.amountOutMin2, plan.path2, address(this), plan.deadline
        );

        IERC20Minimal(bridgeToken).safeApproveExact(plan.router2, 0);
    }

    // ---- PARA ÇEK ----
    // Sözleşmedeki bir tokeni çeker. ÖNEMLİ: önce pause() çağırmalısın,
    // aksi halde MustBePaused hatası alırsın (güvenlik için).
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        if (!paused) revert MustBePaused();
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20Minimal(token).safeSend(to, amount);
        emit TokenRecovered(token, to, amount);
    }

    // ---- BAKİYE ----
    // Sözleşmenin elindeki belirtilen token miktarını döndürür.
    function balance(address token) external view returns (uint256) {
        return IERC20Minimal(token).balanceOf(address(this));
    }

    // Router, token yolları, minimumlar ve son kullanma tarihini doğrula.
    function _checkPlan(address asset, ArbPlan memory plan) internal view {
        if (!tokenWhitelist[asset]) revert TokenNotAllowed(asset);
        if (!routerWhitelist[plan.router1]) revert RouterNotAllowed(plan.router1);
        if (!routerWhitelist[plan.router2]) revert RouterNotAllowed(plan.router2);
        if (plan.path1.length < 2 || plan.path2.length < 2) revert BadPlan();
        if (plan.path1[0] != asset) revert BadPlan();
        if (plan.path2[plan.path2.length - 1] != asset) revert BadPlan();

        address bridgeA = plan.path1[plan.path1.length - 1];
        address bridgeB = plan.path2[0];
        if (bridgeA != bridgeB) revert BadPlan();

        if (plan.amountOutMin1 == 0 || plan.amountOutMin2 == 0 || plan.minProfit == 0) revert BadPlan();
        if (block.timestamp > plan.deadline) revert BadPlan();

        _checkWhitelistedPath(plan.path1);
        _checkWhitelistedPath(plan.path2);
    }

    // Yoldaki her token önceden onaylanmış olmalı.
    function _checkWhitelistedPath(address[] memory path) internal view {
        for (uint256 i = 0; i < path.length; ) {
            address token = path[i];
            if (!tokenWhitelist[token]) revert TokenNotAllowed(token);
            unchecked { ++i; }
        }
    }

    // Geçici flash-loan kayıtlarını temizle.
    function _resetLoanState() internal {
        loanOpen = false;
        activePlanHash = bytes32(0);
        activeAsset = address(0);
        activeAmount = 0;
        balanceBefore = 0;
    }

    // Native coin (ETH) gönderimleri kasıtlı olarak desteklenmez.
    receive() external payable {
        revert NativeTransfersDisabled();
    }

    fallback() external payable {
        revert NativeTransfersDisabled();
    }
}
