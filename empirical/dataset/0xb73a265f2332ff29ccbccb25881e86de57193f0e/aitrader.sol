// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// --- AĞAÇ BAĞLANTILARI VE ARABİRİMLER (INTERFACES) ---

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

// safeApproveExact hatası almamak için güvenli onay kütüphanesi
library SafeERC20Minimal {
    function safeApproveExact(IERC20Minimal token, address spender, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeApprove failed");
    }
}

interface IRouterV2Like {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

// --- ANA SÖZLEŞME ---

contract HonestFlashArbV2 {
    using SafeERC20Minimal for IERC20Minimal;

    // Arbitraj Planlama Yapısı
    struct ArbPlan {
        address router1;
        uint256 amountOutMin1;
        address[] path1;
        address router2;
        uint256 amountOutMin2;
        address[] path2;
        uint256 deadline;
        uint256 minProfit;
    }

    // Durum Değişkenleri
    address public immutable pool; // Aave Lending Pool Adresi
    address public owner;
    bool public isRunning;
    bool public loanOpen;

    address public activeAsset;
    uint256 public activeAmount;
    bytes32 public activePlanHash;
    uint256 public balanceBefore;

    // Etkinlikler (Events)
    event FlashCompleted(address indexed asset, uint256 amount, uint256 premium, uint256 profit);

    // Hata Tanımlamaları
    error BadCallback();
    error NoLoanOpen();
    error GainTooSmall();
    error NotOwner();
    error NotRunning();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenRunning() {
        if (!isRunning) revert NotRunning();
        _;
    }

    constructor(address _pool) {
        pool = _pool;
        owner = msg.sender;
        isRunning = true;
    }

    // Botu durdurma veya başlatma fonksiyonu
    function setRunning(bool _isRunning) external onlyOwner {
        isRunning = _isRunning;
    }

    // Flaş Krediyi Tetikleyen Ana Fonksiyon
    function startArbitrage(
        address asset,
        uint256 amount,
        ArbPlan calldata plan
    ) external onlyOwner whenRunning {
        loanOpen = true;
        activeAsset = asset;
        activeAmount = amount;
        
        bytes memory encodedPlan = abi.encode(plan);
        activePlanHash = keccak256(encodedPlan);
        
        balanceBefore = IERC20Minimal(asset).balanceOf(address(this));

        // Aave V2 Flash Loan parametre hazırlığı
        address[] memory assets = new address[](1);
        assets[0] = asset;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory modes = new uint256[](1); 
        modes[0] = 0; // 0 = Borç kalmayacak, aynı işlemde geri ödenecek.

        // Aave havuzunu tetikleme
        (bool success, ) = pool.call(
            abi.encodeWithSignature(
                "flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)",
                address(this),
                assets,
                amounts,
                modes,
                address(this),
                encodedPlan,
                0
            )
        );
        require(success, "Flash loan execution failed");
    }

    // Aave'nin parayı gönderdikten sonra tetiklediği callback fonksiyonu
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata data
    ) external whenRunning returns (bool) {
        if (msg.sender != pool) revert BadCallback();
        if (initiator != address(this)) revert BadCallback();
        if (!loanOpen) revert NoLoanOpen();
        if (asset != activeAsset || amount != activeAmount) revert BadCallback();
        if (keccak256(data) != activePlanHash) revert BadCallback();

        ArbPlan memory plan = abi.decode(data, (ArbPlan));
        _checkPlan(asset, plan);

        uint256 currentBalance = IERC20Minimal(asset).balanceOf(address(this));
        if (currentBalance < balanceBefore + amount) revert BadCallback();

        // 🛠️ ÇÖZÜMÜN KALBİ: Belleği temizlemek ve hatayı çözmek için izole blok açıyoruz
        {
            // 1. Aşama: Borç alınan token -> Ara Token (Bridge)
            IERC20Minimal(asset).safeApproveExact(plan.router1, amount);

            uint256[] memory firstSwap = IRouterV2Like(plan.router1)
                .swapExactTokensForTokens(
                    amount,
                    plan.amountOutMin1,
                    plan.path1,
                    address(this),
                    plan.deadline
                );

            IERC20Minimal(asset).safeApproveExact(plan.router1, 0);

            uint256 bridgeAmount = firstSwap[firstSwap.length - 1];
            address bridgeToken = plan.path1[plan.path1.length - 1];

            // 2. Aşama: Ara Token -> Borç alınan orijinal token cinsi
            IERC20Minimal(bridgeToken).safeApproveExact(plan.router2, bridgeAmount);

            IRouterV2Like(plan.router2).swapExactTokensForTokens(
                bridgeAmount,
                plan.amountOutMin2,
                plan.path2,
                address(this),
                plan.deadline
            );

            IERC20Minimal(bridgeToken).safeApproveExact(plan.router2, 0);
        } // <--- Bu parantez kapandığı an firstSwap, bridgeAmount ve bridgeToken "Stack" üzerinden silinir!

        uint256 debt = amount + premium;
        uint256 endingBalance = IERC20Minimal(asset).balanceOf(address(this));

        // Kârlılık kontrolü
        if (endingBalance < balanceBefore + debt + plan.minProfit) {
            revert GainTooSmall();
        }

        uint256 profit = endingBalance - balanceBefore - debt;

        _resetLoanState();

        // Aave'nin parayı çekebilmesi için tam borç miktarı kadar onay veriyoruz
        IERC20Minimal(asset).safeApproveExact(pool, debt);

        emit FlashCompleted(asset, amount, premium, profit);
        return true;
    }

    // CSV kayıtlarında gördüğümüz, biriken kârları sahibinin cüzdanına çeken fonksiyon (Withdraw)
    function withdraw(address token) external onlyOwner {
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        IERC20Minimal(token).transfer(owner, balance);
    }

    // İç Yardımcı Kontroller
    function _checkPlan(address asset, ArbPlan memory plan) internal pure {
        require(plan.path1[0] == asset, "Invalid path1 start");
        require(plan.path2[plan.path2.length - 1] == asset, "Invalid path2 end");
        require(plan.path1[plan.path1.length - 1] == plan.path2[0], "Path mismatch");
    }

    function _resetLoanState() internal {
        loanOpen = false;
        activeAsset = address(0);
        activeAmount = 0;
        activePlanHash = bytes32(0);
        balanceBefore = 0;
    }
}